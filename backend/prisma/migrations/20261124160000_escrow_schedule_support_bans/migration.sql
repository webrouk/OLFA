-- Escrow for consultations, counselor scheduling, support tickets with
-- attachments + FAQ, review replies, and permanent / temporary account bans.

-- ═════════════ 1. Account bans: permanent (BANNED) or until a date (SUSPENDED) ═════════════
ALTER TABLE users
  ADD COLUMN suspended_until timestamptz,
  ADD COLUMN restriction_reason varchar(300),
  ADD COLUMN restricted_at timestamptz;
-- A suspension with a date ends by itself (also checked on every request).
CREATE FUNCTION olfa_lift_expired_suspensions() RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  UPDATE users SET status = 'ACTIVE', suspended_until = NULL, restriction_reason = NULL, restricted_at = NULL
  WHERE status = 'SUSPENDED' AND suspended_until IS NOT NULL AND suspended_until <= now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
CREATE INDEX users_suspension_idx ON users (suspended_until) WHERE status = 'SUSPENDED' AND suspended_until IS NOT NULL;

-- ═════════════ 2. Escrow: the counselor is paid only after the client confirms ═════════════
-- PAID → money HELD. The counselor completes the session; the client answers the
-- questionnaire (rating + "did the session take place?"). Yes → RELEASED to the
-- counselor's wallet. No → DISPUTED until support decides (release or refund).
CREATE TYPE escrow_status AS ENUM ('HELD', 'RELEASED', 'DISPUTED', 'REFUNDED');
ALTER TABLE consultations
  ADD COLUMN escrow_status escrow_status,
  ADD COLUMN escrow_released_at timestamptz,
  ADD COLUMN dispute_reason varchar(500);
UPDATE consultations SET escrow_status = CASE WHEN status = 'REFUNDED' THEN 'REFUNDED'::escrow_status ELSE 'RELEASED'::escrow_status END,
                         escrow_released_at = completed_at
WHERE status IN ('COMPLETED', 'REFUNDED') AND paid_at IS NOT NULL;
UPDATE consultations SET escrow_status = 'HELD' WHERE status IN ('PAID', 'CONFIRMED');
ALTER TABLE consultation_reviews
  ADD COLUMN session_happened boolean,
  ADD COLUMN counselor_reply varchar(1000),
  ADD COLUMN counselor_replied_at timestamptz;
-- "The session did not take place": no rating is invented — only the report (handled by support).
ALTER TABLE consultation_reviews ALTER COLUMN rating DROP NOT NULL;
ALTER TABLE consultation_reviews ADD CONSTRAINT consultation_reviews_rating_required
  CHECK (rating IS NOT NULL OR session_happened IS FALSE);
-- the questionnaire is required only for sessions that took place
ALTER TABLE consultation_reviews DROP CONSTRAINT consultation_reviews_complete;
ALTER TABLE consultation_reviews ADD CONSTRAINT consultation_reviews_complete CHECK (
  questionnaire_version IS NULL OR session_happened IS FALSE OR (
    quality IS NOT NULL AND commitment IS NOT NULL AND effectiveness IS NOT NULL AND outcome IS NOT NULL AND
    next_session IS NOT NULL AND next_channel IS NOT NULL AND contact_shared IS NOT NULL AND
    off_platform_payment IS NOT NULL AND external_channel IS NOT NULL));

-- Rating shown on the counselor card: only rated, visible reviews.
CREATE OR REPLACE FUNCTION olfa_review_aggregate() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cid uuid := COALESCE(NEW.counselor_id, OLD.counselor_id);
BEGIN
  UPDATE counselor_profiles cp SET
    rating_count = s.n, rating_avg = COALESCE(round(s.avg, 2), 0), updated_at = now()
  FROM (SELECT count(rating) AS n, avg(rating)::numeric AS avg FROM consultation_reviews
        WHERE counselor_id = cid AND NOT hidden AND rating IS NOT NULL) s
  WHERE cp.user_id = cid;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION olfa_consultation_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ok boolean; pay payments%ROWTYPE; pct int;
BEGIN
  IF NEW.status = OLD.status THEN NEW.updated_at := now(); RETURN NEW; END IF;
  ok := (OLD.status, NEW.status) IN (
    ('AWAITING_PAYMENT','PAID'), ('AWAITING_PAYMENT','CANCELLED'), ('AWAITING_PAYMENT','EXPIRED'),
    ('PAID','CONFIRMED'), ('PAID','DECLINED'), ('PAID','CANCELLED'), ('PAID','REFUNDED'),
    ('CONFIRMED','COMPLETED'), ('CONFIRMED','CANCELLED'), ('CONFIRMED','REFUNDED'),
    ('DECLINED','REFUNDED'), ('CANCELLED','REFUNDED'), ('COMPLETED','REFUNDED'));
  IF NOT ok THEN
    RAISE EXCEPTION 'invalid consultation transition % -> %', OLD.status, NEW.status USING ERRCODE = 'P0001';
  END IF;
  IF NEW.status = 'PAID' THEN
    SELECT * INTO pay FROM payments WHERE id = NEW.payment_id;
    IF pay.id IS NULL OR pay.status <> 'SUCCEEDED' OR pay.consultation_id <> NEW.id
       OR pay.amount_minor <> NEW.price_minor OR pay.currency <> NEW.currency THEN
      RAISE EXCEPTION 'consultation % is not paid in full', NEW.id USING ERRCODE = 'P0002';
    END IF;
    NEW.paid_at := now();
    pct := olfa_setting_int('consultations.platformFeePercent', 15);
    NEW.platform_fee_percent := pct;
    NEW.platform_fee_minor := floor((NEW.price_minor::bigint * pct + 50) / 100);
    NEW.counselor_net_minor := NEW.price_minor - NEW.platform_fee_minor;
    NEW.escrow_status := 'HELD';
  ELSIF NEW.status = 'CONFIRMED' THEN NEW.confirmed_at := now();
  ELSIF NEW.status = 'COMPLETED' THEN NEW.completed_at := now();
  ELSIF NEW.status IN ('CANCELLED','DECLINED','EXPIRED') THEN NEW.cancelled_at := now();
  END IF;
  IF NEW.status = 'REFUNDED' AND NEW.escrow_status IS DISTINCT FROM 'RELEASED' THEN
    NEW.escrow_status := 'REFUNDED';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- Completion no longer pays the counselor; only a release does.
CREATE OR REPLACE FUNCTION olfa_consultation_wallet() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- A refund after the money was released takes it back from the counselor.
  IF NEW.status = 'REFUNDED' AND OLD.status <> 'REFUNDED' AND OLD.escrow_status = 'RELEASED' AND NEW.counselor_net_minor > 0 THEN
    INSERT INTO wallet_entries (counselor_id, currency, kind, amount_minor, consultation_id, memo)
    VALUES (NEW.counselor_id, NEW.currency, 'EARNING_REVERSAL', -NEW.counselor_net_minor, NEW.id, 'consultation refunded')
    ON CONFLICT DO NOTHING;
    UPDATE consultations SET escrow_status = 'REFUNDED' WHERE id = NEW.id;
  END IF;
  RETURN NULL;
END $$;

-- The only way money reaches a counselor's wallet. Idempotent.
CREATE FUNCTION olfa_release_escrow(p_consultation uuid, p_memo text) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE c consultations%ROWTYPE;
BEGIN
  UPDATE consultations SET escrow_status = 'RELEASED', escrow_released_at = now()
  WHERE id = p_consultation AND status = 'COMPLETED' AND escrow_status IN ('HELD', 'DISPUTED')
  RETURNING * INTO c;
  IF c.id IS NULL THEN RETURN false; END IF;
  IF c.counselor_net_minor > 0 THEN
    INSERT INTO wallet_entries (counselor_id, currency, kind, amount_minor, consultation_id, available_at, memo)
    VALUES (c.counselor_id, c.currency, 'EARNING', c.counselor_net_minor, c.id,
            now() + make_interval(days => olfa_setting_int('wallet.holdDays', 0)),
            coalesce(p_memo, 'released') || ' · net of ' || c.platform_fee_percent || '% platform fee')
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN true;
END $$;

-- The client's questionnaire releases (session took place) or disputes it.
CREATE FUNCTION olfa_review_escrow() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.session_happened IS FALSE THEN
    UPDATE consultations SET escrow_status = 'DISPUTED', dispute_reason = 'client: the session did not take place'
    WHERE id = NEW.consultation_id AND escrow_status = 'HELD';
  ELSE
    PERFORM olfa_release_escrow(NEW.consultation_id, 'confirmed and rated by the client');
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER consultation_reviews_escrow AFTER INSERT ON consultation_reviews FOR EACH ROW EXECUTE FUNCTION olfa_review_escrow();

-- Optional safety net (admin setting, 0 = never): release completed sessions the
-- client never confirmed after N days. Off by default — money stays held.
CREATE FUNCTION olfa_auto_release_escrow() RETURNS int LANGUAGE plpgsql AS $$
DECLARE d int := olfa_setting_int('escrow.autoReleaseDays', 0); n int := 0; r record;
BEGIN
  IF d <= 0 THEN RETURN 0; END IF;
  FOR r IN SELECT id FROM consultations
           WHERE status = 'COMPLETED' AND escrow_status = 'HELD' AND completed_at < now() - make_interval(days => d) LOOP
    IF olfa_release_escrow(r.id, 'auto-released after ' || d || ' days without client response') THEN n := n + 1; END IF;
  END LOOP;
  RETURN n;
END $$;
-- The escrow replaces the old 7-day hold: released money is available at once.
UPDATE system_settings SET value = '0', description = 'Extra days released consultation earnings stay pending (escrow already waits for the client)' WHERE key = 'wallet.holdDays';
INSERT INTO system_settings (key, value, description) VALUES
  ('escrow.autoReleaseDays', '0', 'Release completed consultations the client never confirmed after N days (0 = never; support releases or refunds)')
ON CONFLICT (key) DO NOTHING;
CREATE INDEX consultations_escrow_idx ON consultations (counselor_id, escrow_status) WHERE escrow_status IN ('HELD', 'DISPUTED');

-- ═════════════ 3. Counselor scheduling ═════════════
CREATE TABLE counselor_schedules (
  counselor_id     uuid PRIMARY KEY REFERENCES counselor_profiles(user_id) ON DELETE CASCADE,
  timezone         varchar(64) NOT NULL DEFAULT 'Asia/Dubai',
  buffer_minutes   smallint NOT NULL DEFAULT 10 CHECK (buffer_minutes BETWEEN 0 AND 60),
  min_notice_hours smallint NOT NULL DEFAULT 12 CHECK (min_notice_hours BETWEEN 1 AND 168),
  max_days_ahead   smallint NOT NULL DEFAULT 30 CHECK (max_days_ahead BETWEEN 1 AND 90),
  accepting        boolean NOT NULL DEFAULT true,
  updated_at       timestamptz NOT NULL DEFAULT now()
);
-- Weekly windows in the counselor's time zone. weekday: 1 = Monday … 7 = Sunday (ISO).
CREATE TABLE counselor_availability (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  counselor_id uuid NOT NULL REFERENCES counselor_profiles(user_id) ON DELETE CASCADE,
  weekday      smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),
  start_minute smallint NOT NULL CHECK (start_minute BETWEEN 0 AND 1435),
  end_minute   smallint NOT NULL CHECK (end_minute BETWEEN 5 AND 1440),
  CHECK (end_minute > start_minute),
  EXCLUDE USING gist (counselor_id WITH =, weekday WITH =, int4range(start_minute, end_minute) WITH &&)
);
CREATE TABLE counselor_time_off (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  counselor_id uuid NOT NULL REFERENCES counselor_profiles(user_id) ON DELETE CASCADE,
  starts_at    timestamptz NOT NULL,
  ends_at      timestamptz NOT NULL,
  note         varchar(120),
  CHECK (ends_at > starts_at)
);
CREATE INDEX counselor_time_off_idx ON counselor_time_off (counselor_id, ends_at);

-- One booking per counselor per time: an open booking reserves its slot, so two
-- clients can never pay for the same time (race-proof at the database level).
-- Adding whole minutes doesn't depend on the session time zone, so this is
-- safely IMMUTABLE (Postgres marks timestamptz + interval as STABLE because of day/month units).
CREATE FUNCTION olfa_slot(p_start timestamptz, p_minutes int) RETURNS tstzrange
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN p_start IS NULL THEN NULL
              ELSE tstzrange(p_start, p_start + p_minutes * interval '1 minute', '[)') END
$$;
ALTER TABLE consultations ADD COLUMN slot tstzrange
  GENERATED ALWAYS AS (olfa_slot(coalesce(scheduled_at, preferred_time), duration_minutes)) STORED;
ALTER TABLE consultations ADD CONSTRAINT consultations_no_double_booking
  EXCLUDE USING gist (counselor_id WITH =, slot WITH &&) WHERE (status IN ('AWAITING_PAYMENT', 'PAID', 'CONFIRMED') AND slot IS NOT NULL);

-- ═════════════ 4. Support tickets: threads, attachments, read state; FAQ ═════════════
ALTER TABLE support_tickets
  ADD COLUMN last_message_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN user_last_read_at timestamptz,
  ADD COLUMN staff_last_read_at timestamptz;
CREATE INDEX support_tickets_user_idx ON support_tickets (user_id, last_message_at DESC);
ALTER TABLE ticket_messages ALTER COLUMN body SET DEFAULT '';
CREATE INDEX ticket_messages_ticket_idx ON ticket_messages (ticket_id, created_at);

CREATE TYPE attachment_status AS ENUM ('PENDING', 'READY');
CREATE TABLE ticket_attachments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- uploaded before the message is sent (even before a new ticket exists); linked on send
  ticket_id   uuid REFERENCES support_tickets(id) ON DELETE CASCADE,
  message_id  uuid REFERENCES ticket_messages(id) ON DELETE CASCADE,
  uploader_id uuid NOT NULL,
  storage_key varchar(200) NOT NULL UNIQUE,
  file_name   varchar(120) NOT NULL,
  mime        varchar(80) NOT NULL CHECK (mime IN ('image/jpeg', 'image/png', 'image/heic', 'image/webp', 'application/pdf')),
  bytes       int NOT NULL CHECK (bytes BETWEEN 1 AND 10485760),
  status      attachment_status NOT NULL DEFAULT 'PENDING',
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (message_id IS NULL OR ticket_id IS NOT NULL)
);
CREATE INDEX ticket_attachments_message_idx ON ticket_attachments (message_id);
CREATE FUNCTION olfa_ticket_attachment_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.message_id IS NOT NULL AND (SELECT count(*) FROM ticket_attachments WHERE message_id = NEW.message_id AND id <> NEW.id) >= 3 THEN
    RAISE EXCEPTION 'at most 3 attachments per support message' USING ERRCODE = 'P0021';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ticket_attachments_guard BEFORE INSERT OR UPDATE OF message_id ON ticket_attachments FOR EACH ROW EXECUTE FUNCTION olfa_ticket_attachment_guard();
-- A message keeps the ticket's order and reopens a resolved ticket when the user writes.
CREATE FUNCTION olfa_ticket_message_touch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE support_tickets SET last_message_at = NEW.created_at,
         status = CASE WHEN NEW.author_type = 'USER' AND status IN ('RESOLVED', 'PENDING_USER') THEN 'OPEN'::ticket_status
                       WHEN NEW.author_type = 'ADMIN' AND status = 'OPEN' THEN 'PENDING_USER'::ticket_status
                       ELSE status END
  WHERE id = NEW.ticket_id AND status <> 'CLOSED';
  RETURN NULL;
END $$;
CREATE TRIGGER ticket_messages_touch AFTER INSERT ON ticket_messages FOR EACH ROW EXECUTE FUNCTION olfa_ticket_message_touch();

CREATE TABLE faq_entries (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category   ticket_category NOT NULL DEFAULT 'OTHER',
  question   jsonb NOT NULL CHECK (question ? 'ar' AND question ? 'en' AND question ? 'fr'),
  answer     jsonb NOT NULL CHECK (answer ? 'ar' AND answer ? 'en' AND answer ? 'fr'),
  sort_order smallint NOT NULL DEFAULT 0,
  published  boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'SUPPORT_REPLY';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'ESCROW_RELEASED';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'ACCOUNT_RESTRICTED';

-- Deleted support attachments → their stored objects are removed by the hourly sweep.
CREATE TRIGGER ticket_attachments_garbage AFTER DELETE ON ticket_attachments
  FOR EACH ROW EXECUTE FUNCTION olfa_attachment_gc();

-- Account types, religion & sect, counselor wallet (15% commission, payouts),
-- mandatory post-consultation questionnaire + integrity cases, permanent bans
-- with re-registration block, and store-subscription state (App Store / Play).

-- ═════════════ 1. Account types ═════════════
-- Chosen once during sign-up, before the profile is created. A MEMBER looks for
-- marriage; professionals (psychologist / family counselor) never appear in
-- discovery, cannot like or match, and get the counselor workspace instead.
CREATE TYPE account_type AS ENUM ('MEMBER', 'PSYCHOLOGIST', 'FAMILY_COUNSELOR');
ALTER TABLE users ADD COLUMN account_type account_type;
ALTER TYPE account_status ADD VALUE IF NOT EXISTS 'BANNED';

-- Existing data: counselor-only accounts become professionals, everyone with a
-- marriage profile is a member.
UPDATE users u SET account_type = (CASE c.kind WHEN 'PSYCHOLOGIST' THEN 'PSYCHOLOGIST' ELSE 'FAMILY_COUNSELOR' END)::account_type
FROM counselor_profiles c WHERE c.user_id = u.id AND NOT EXISTS (SELECT 1 FROM user_profiles p WHERE p.user_id = u.id);
UPDATE users u SET account_type = 'MEMBER' WHERE account_type IS NULL AND EXISTS (SELECT 1 FROM user_profiles p WHERE p.user_id = u.id);
CREATE INDEX users_account_type_idx ON users (account_type) WHERE deleted_at IS NULL;

-- The type is locked once a profile of either kind exists.
CREATE FUNCTION olfa_account_type_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.account_type IS NOT NULL AND NEW.account_type IS DISTINCT FROM OLD.account_type
     AND (EXISTS (SELECT 1 FROM user_profiles WHERE user_id = NEW.id) OR EXISTS (SELECT 1 FROM counselor_profiles WHERE user_id = NEW.id)) THEN
    RAISE EXCEPTION 'account type is locked once the profile exists' USING ERRCODE = 'P0030';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER users_account_type_guard BEFORE UPDATE OF account_type ON users FOR EACH ROW EXECUTE FUNCTION olfa_account_type_guard();

-- A marriage profile needs a MEMBER account; a counselor profile needs the matching professional type.
CREATE FUNCTION olfa_member_profile_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t account_type;
BEGIN
  SELECT account_type INTO t FROM users WHERE id = NEW.user_id FOR UPDATE;
  IF t IS NULL THEN UPDATE users SET account_type = 'MEMBER' WHERE id = NEW.user_id;
  ELSIF t <> 'MEMBER' THEN RAISE EXCEPTION 'professional accounts have no marriage profile' USING ERRCODE = 'P0031';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER user_profiles_member_guard BEFORE INSERT ON user_profiles FOR EACH ROW EXECUTE FUNCTION olfa_member_profile_guard();

CREATE FUNCTION olfa_counselor_profile_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t account_type; want account_type := (CASE NEW.kind WHEN 'PSYCHOLOGIST' THEN 'PSYCHOLOGIST' ELSE 'FAMILY_COUNSELOR' END)::account_type;
BEGIN
  SELECT account_type INTO t FROM users WHERE id = NEW.user_id FOR UPDATE;
  IF t IS NULL THEN UPDATE users SET account_type = want WHERE id = NEW.user_id;
  ELSIF t <> want THEN RAISE EXCEPTION 'counselor kind must match the account type' USING ERRCODE = 'P0031';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER counselor_profiles_type_guard BEFORE INSERT OR UPDATE OF kind ON counselor_profiles FOR EACH ROW EXECUTE FUNCTION olfa_counselor_profile_guard();

-- Professional details collected at sign-up.
ALTER TABLE counselor_profiles
  ADD COLUMN gender gender,
  ADD COLUMN country_code char(2),
  ADD COLUMN city varchar(80),
  ADD COLUMN latitude double precision,
  ADD COLUMN longitude double precision,
  ADD COLUMN policy_version varchar(20),
  ADD COLUMN policy_accepted_at timestamptz;

-- Discovery and likes: members only (on top of the existing checks).
CREATE OR REPLACE FUNCTION olfa_candidate_ok(p_viewer uuid, p_cand uuid, p_min_photos int, p_cooldown_h int) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT
        EXISTS (SELECT 1 FROM users mu WHERE mu.id = p_cand AND mu.account_type = 'MEMBER')
    AND ((EXISTS (SELECT 1 FROM user_verifications v WHERE v.user_id = p_cand AND v.type = 'PROFILE_REVIEW' AND v.revoked_at IS NULL)
          AND (SELECT count(*) FROM user_photos ph WHERE ph.user_id = p_cand AND ph.status = 'APPROVED' AND ph.deleted_at IS NULL) >= p_min_photos)
         OR EXISTS (SELECT 1 FROM users nu WHERE nu.id = p_cand AND nu.status = 'PENDING_VERIFICATION'))
    AND NOT EXISTS (SELECT 1 FROM user_privacy_settings ps
                    WHERE ps.user_id = p_cand
                      AND (NOT ps.discoverable
                           OR (ps.incognito AND NOT EXISTS (SELECT 1 FROM likes il WHERE il.from_user_id = p_cand AND il.to_user_id = p_viewer))))
    AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = p_viewer AND b.blocked_id = p_cand)
    AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = p_cand AND b.blocked_id = p_viewer)
    AND NOT EXISTS (SELECT 1 FROM likes l WHERE l.from_user_id = p_viewer AND l.to_user_id = p_cand)
    AND NOT EXISTS (SELECT 1 FROM passes x WHERE x.from_user_id = p_viewer AND x.to_user_id = p_cand AND (x.expires_at IS NULL OR x.expires_at > now()))
    AND NOT EXISTS (SELECT 1 FROM matches m WHERE m.user_a_id = LEAST(p_viewer, p_cand) AND m.user_b_id = GREATEST(p_viewer, p_cand))
    AND NOT EXISTS (SELECT 1 FROM discovery_history h
                    WHERE h.viewer_id = p_viewer AND h.candidate_id = p_cand AND h.action = 'SHOWN'
                      AND h.created_at > now() - make_interval(hours => p_cooldown_h))
$$;

CREATE FUNCTION olfa_like_members_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.from_user_id AND account_type = 'MEMBER')
     OR NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.to_user_id AND account_type = 'MEMBER') THEN
    RAISE EXCEPTION 'likes are between marriage members only' USING ERRCODE = 'OLL02';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER likes_members_guard BEFORE INSERT ON likes FOR EACH ROW EXECUTE FUNCTION olfa_like_members_guard();

-- ═════════════ 2. Religion & sect ═════════════
CREATE TABLE religions (
  key        varchar(30) PRIMARY KEY,
  name_en    varchar(60) NOT NULL,
  name_ar    varchar(60) NOT NULL,
  sort_order smallint NOT NULL DEFAULT 0
);
CREATE TABLE sects (
  religion_key varchar(30) NOT NULL REFERENCES religions(key),
  key          varchar(40) NOT NULL,
  name_en      varchar(60) NOT NULL,
  name_ar      varchar(60) NOT NULL,
  sort_order   smallint NOT NULL DEFAULT 0,
  PRIMARY KEY (religion_key, key)
);
-- religions/sects rows: generated file, kept in sync with shared/reference/religions.tsv
-- GENERATED by shared/reference/generate.py from religions.tsv
INSERT INTO religions (key, name_en, name_ar, sort_order) VALUES
  ('islam', 'Islam', 'الإسلام', 0),
  ('christianity', 'Christianity', 'المسيحية', 1),
  ('druze', 'Druze', 'الدرزية', 2),
  ('judaism', 'Judaism', 'اليهودية', 3),
  ('other', 'Other', 'ديانة أخرى', 4),
  ('undisclosed', 'Prefer not to say', 'أفضّل عدم الإفصاح', 5)
ON CONFLICT (key) DO UPDATE SET name_en = EXCLUDED.name_en, name_ar = EXCLUDED.name_ar, sort_order = EXCLUDED.sort_order;
INSERT INTO sects (religion_key, key, name_en, name_ar, sort_order) VALUES
  ('islam', 'sunni', 'Sunni', 'سنّي', 0),
  ('islam', 'shia', 'Shia', 'شيعي', 1),
  ('islam', 'ibadi', 'Ibadi', 'إباضي', 2),
  ('islam', 'other', 'Other / prefer not to say', 'أخرى / أفضّل عدم التحديد', 3),
  ('christianity', 'coptic_orthodox', 'Coptic Orthodox', 'قبطي أرثوذكسي', 4),
  ('christianity', 'greek_orthodox', 'Greek Orthodox', 'روم أرثوذكس', 5),
  ('christianity', 'syriac_orthodox', 'Syriac Orthodox', 'سرياني أرثوذكسي', 6),
  ('christianity', 'armenian_orthodox', 'Armenian Orthodox', 'أرمني أرثوذكسي', 7),
  ('christianity', 'catholic', 'Catholic', 'كاثوليكي', 8),
  ('christianity', 'maronite', 'Maronite', 'ماروني', 9),
  ('christianity', 'melkite', 'Melkite Greek Catholic', 'روم كاثوليك', 10),
  ('christianity', 'protestant', 'Protestant', 'بروتستانتي', 11),
  ('christianity', 'evangelical', 'Evangelical', 'إنجيلي', 12),
  ('christianity', 'other', 'Other / prefer not to say', 'أخرى / أفضّل عدم التحديد', 13)
ON CONFLICT (religion_key, key) DO UPDATE SET name_en = EXCLUDED.name_en, name_ar = EXCLUDED.name_ar, sort_order = EXCLUDED.sort_order;

-- The sect must belong to the chosen religion (composite FK; a NULL sect is allowed
-- for religions without sects or when the member skips it).
ALTER TABLE user_profiles
  ADD COLUMN religion varchar(30) REFERENCES religions(key),
  ADD COLUMN sect varchar(40),
  ADD COLUMN religion_consent_at timestamptz,
  ADD CONSTRAINT user_profiles_sect_fk FOREIGN KEY (religion, sect) REFERENCES sects(religion_key, key),
  ADD CONSTRAINT user_profiles_sect_needs_religion CHECK (sect IS NULL OR religion IS NOT NULL),
  -- religion is special-category data: stored only with the member's explicit consent
  ADD CONSTRAINT user_profiles_religion_consent CHECK (religion IS NULL OR religion = 'undisclosed' OR religion_consent_at IS NOT NULL);
CREATE INDEX user_profiles_religion_idx ON user_profiles (religion, sect);

-- Partner preferences: accepted religions / sects (empty = any).
ALTER TABLE user_preferences
  ADD COLUMN religions varchar(30)[] NOT NULL DEFAULT '{}',
  ADD COLUMN sects varchar(71)[] NOT NULL DEFAULT '{}'; -- "religion.sect"

CREATE FUNCTION olfa_preferences_religion_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM unnest(NEW.religions) r WHERE r NOT IN (SELECT key FROM religions)) THEN
    RAISE EXCEPTION 'unknown religion in preferences' USING ERRCODE = '23503';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(NEW.sects) s
             WHERE NOT EXISTS (SELECT 1 FROM sects x WHERE x.religion_key || '.' || x.key = s)
                OR (cardinality(NEW.religions) > 0 AND split_part(s, '.', 1) <> ALL (NEW.religions))) THEN
    RAISE EXCEPTION 'sect does not belong to an accepted religion' USING ERRCODE = '23503';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER user_preferences_religion_guard BEFORE INSERT OR UPDATE OF religions, sects ON user_preferences FOR EACH ROW EXECUTE FUNCTION olfa_preferences_religion_guard();

-- ═════════════ 3. Wallet: commission snapshot, earnings, payouts ═════════════
-- The fee is fixed when the client pays (so later setting changes never alter it).
ALTER TABLE consultations
  ADD COLUMN platform_fee_percent smallint,
  ADD COLUMN platform_fee_minor int,
  ADD COLUMN counselor_net_minor int,
  ADD CONSTRAINT consultations_fee_sum CHECK (platform_fee_minor IS NULL OR platform_fee_minor + counselor_net_minor = price_minor);

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
  ELSIF NEW.status = 'CONFIRMED' THEN NEW.confirmed_at := now();
  ELSIF NEW.status = 'COMPLETED' THEN NEW.completed_at := now();
  ELSIF NEW.status IN ('CANCELLED','DECLINED','EXPIRED') THEN NEW.cancelled_at := now();
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE TYPE wallet_entry_kind AS ENUM ('EARNING', 'EARNING_REVERSAL', 'WITHDRAWAL', 'WITHDRAWAL_RETURN', 'ADJUSTMENT');
CREATE TYPE payout_method_kind AS ENUM ('BANK_IBAN', 'BANK_SWIFT', 'WISE', 'PAYPAL', 'PAYONEER');
CREATE TYPE withdrawal_status AS ENUM ('REQUESTED', 'PROCESSING', 'PAID', 'REJECTED', 'FAILED', 'CANCELLED');

-- Destinations: details sealed with AES-256-GCM by the API; only a mask and an
-- HMAC fingerprint are readable here.
CREATE TABLE payout_methods (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  counselor_id  uuid NOT NULL REFERENCES counselor_profiles(user_id) ON DELETE CASCADE,
  kind          payout_method_kind NOT NULL,
  holder_name   varchar(120) NOT NULL,
  country_code  char(2) NOT NULL,
  currency      char(3) NOT NULL,
  details_enc   bytea NOT NULL,
  details_mask  varchar(60) NOT NULL,
  fingerprint   char(64) NOT NULL,
  is_default    boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);
CREATE UNIQUE INDEX payout_methods_unique_live ON payout_methods (counselor_id, fingerprint) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX payout_methods_one_default ON payout_methods (counselor_id) WHERE is_default AND deleted_at IS NULL;

CREATE TABLE withdrawals (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  counselor_id      uuid NOT NULL REFERENCES counselor_profiles(user_id),
  payout_method_id  uuid NOT NULL REFERENCES payout_methods(id),
  amount_minor      int NOT NULL CHECK (amount_minor > 0),
  currency          char(3) NOT NULL,
  status            withdrawal_status NOT NULL DEFAULT 'REQUESTED',
  provider_ref      varchar(120),
  failure_reason    varchar(300),
  processed_by      uuid REFERENCES admin_users(id),
  requested_at      timestamptz NOT NULL DEFAULT now(),
  processed_at      timestamptz,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'PAID' OR provider_ref IS NOT NULL)
);
-- one open request per currency at a time
CREATE UNIQUE INDEX withdrawals_one_open ON withdrawals (counselor_id, currency) WHERE status IN ('REQUESTED', 'PROCESSING');
CREATE INDEX withdrawals_queue_idx ON withdrawals (status, requested_at);

-- Append-only ledger. Earnings become available after the hold period
-- (refund / dispute window); withdrawals reserve funds immediately.
CREATE TABLE wallet_entries (
  id               bigserial PRIMARY KEY,
  counselor_id     uuid NOT NULL REFERENCES counselor_profiles(user_id),
  currency         char(3) NOT NULL,
  kind             wallet_entry_kind NOT NULL,
  amount_minor     int NOT NULL CHECK (amount_minor <> 0),
  consultation_id  uuid REFERENCES consultations(id),
  withdrawal_id    uuid REFERENCES withdrawals(id),
  available_at     timestamptz NOT NULL DEFAULT now(),
  memo             varchar(200),
  created_by       uuid REFERENCES admin_users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind IN ('EARNING','WITHDRAWAL_RETURN','ADJUSTMENT') AND amount_minor > 0) OR (kind IN ('EARNING_REVERSAL','WITHDRAWAL') AND amount_minor < 0) OR kind = 'ADJUSTMENT'),
  CHECK (kind NOT IN ('EARNING','EARNING_REVERSAL') OR consultation_id IS NOT NULL),
  CHECK (kind NOT IN ('WITHDRAWAL','WITHDRAWAL_RETURN') OR withdrawal_id IS NOT NULL)
);
CREATE UNIQUE INDEX wallet_entries_once_per_consultation ON wallet_entries (consultation_id, kind) WHERE consultation_id IS NOT NULL;
CREATE UNIQUE INDEX wallet_entries_once_per_withdrawal ON wallet_entries (withdrawal_id, kind) WHERE withdrawal_id IS NOT NULL;
CREATE INDEX wallet_entries_counselor_idx ON wallet_entries (counselor_id, currency, created_at DESC);

CREATE FUNCTION olfa_wallet_entries_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'wallet entries are append-only' USING ERRCODE = 'P0040'; END $$;
CREATE TRIGGER wallet_entries_no_update BEFORE UPDATE OR DELETE ON wallet_entries FOR EACH ROW EXECUTE FUNCTION olfa_wallet_entries_immutable();

CREATE FUNCTION olfa_wallet_balance(p_counselor uuid, p_currency char(3), p_now timestamptz DEFAULT now())
RETURNS TABLE (available_minor bigint, pending_minor bigint) LANGUAGE sql STABLE AS $$
  SELECT COALESCE(sum(amount_minor) FILTER (WHERE available_at <= p_now OR amount_minor < 0), 0),
         COALESCE(sum(amount_minor) FILTER (WHERE available_at > p_now AND amount_minor > 0), 0)
  FROM wallet_entries WHERE counselor_id = p_counselor AND currency = p_currency
$$;

-- A withdrawal debit may never take the available balance below zero.
CREATE FUNCTION olfa_wallet_debit_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE avail bigint;
BEGIN
  IF NEW.kind <> 'WITHDRAWAL' THEN RETURN NEW; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('wallet:' || NEW.counselor_id::text || ':' || NEW.currency, 0));
  SELECT available_minor INTO avail FROM olfa_wallet_balance(NEW.counselor_id, NEW.currency, now());
  IF avail + NEW.amount_minor < 0 THEN
    RAISE EXCEPTION 'insufficient available balance' USING ERRCODE = 'P0041';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER wallet_entries_debit_guard BEFORE INSERT ON wallet_entries FOR EACH ROW EXECUTE FUNCTION olfa_wallet_debit_guard();

-- Earnings follow the consultation: credited (net of the fee) on completion,
-- reversed if a completed consultation is later refunded through Support.
CREATE FUNCTION olfa_consultation_wallet() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'COMPLETED' AND OLD.status <> 'COMPLETED' AND NEW.counselor_net_minor > 0 THEN
    INSERT INTO wallet_entries (counselor_id, currency, kind, amount_minor, consultation_id, available_at, memo)
    VALUES (NEW.counselor_id, NEW.currency, 'EARNING', NEW.counselor_net_minor, NEW.id,
            now() + make_interval(days => olfa_setting_int('wallet.holdDays', 7)),
            'net of ' || NEW.platform_fee_percent || '% platform fee')
    ON CONFLICT DO NOTHING;
  ELSIF NEW.status = 'REFUNDED' AND OLD.status = 'COMPLETED' AND NEW.counselor_net_minor > 0 THEN
    INSERT INTO wallet_entries (counselor_id, currency, kind, amount_minor, consultation_id, memo)
    VALUES (NEW.counselor_id, NEW.currency, 'EARNING_REVERSAL', -NEW.counselor_net_minor, NEW.id, 'consultation refunded')
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER consultations_wallet AFTER UPDATE OF status ON consultations FOR EACH ROW EXECUTE FUNCTION olfa_consultation_wallet();

-- Withdrawal lifecycle: the debit is written with the request; rejected,
-- failed or cancelled requests return the funds.
CREATE FUNCTION olfa_withdrawal_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ok boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT EXISTS (SELECT 1 FROM payout_methods pm WHERE pm.id = NEW.payout_method_id AND pm.counselor_id = NEW.counselor_id AND pm.deleted_at IS NULL) THEN
      RAISE EXCEPTION 'unknown payout method' USING ERRCODE = '23503';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.status = OLD.status THEN NEW.updated_at := now(); RETURN NEW; END IF;
  ok := (OLD.status, NEW.status) IN (('REQUESTED','PROCESSING'), ('REQUESTED','REJECTED'), ('REQUESTED','CANCELLED'),
                                    ('PROCESSING','PAID'), ('PROCESSING','FAILED'), ('PROCESSING','REJECTED'));
  IF NOT ok THEN RAISE EXCEPTION 'invalid withdrawal transition % -> %', OLD.status, NEW.status USING ERRCODE = 'P0042'; END IF;
  IF NEW.status IN ('PAID','REJECTED','FAILED','CANCELLED') THEN NEW.processed_at := now(); END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER withdrawals_guard BEFORE INSERT OR UPDATE ON withdrawals FOR EACH ROW EXECUTE FUNCTION olfa_withdrawal_guard();

CREATE FUNCTION olfa_withdrawal_ledger() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO wallet_entries (counselor_id, currency, kind, amount_minor, withdrawal_id, memo)
    VALUES (NEW.counselor_id, NEW.currency, 'WITHDRAWAL', -NEW.amount_minor, NEW.id, 'withdrawal request');
  ELSIF NEW.status IN ('REJECTED','FAILED','CANCELLED') AND OLD.status IN ('REQUESTED','PROCESSING') THEN
    INSERT INTO wallet_entries (counselor_id, currency, kind, amount_minor, withdrawal_id, memo)
    VALUES (NEW.counselor_id, NEW.currency, 'WITHDRAWAL_RETURN', NEW.amount_minor, NEW.id, 'withdrawal ' || lower(NEW.status::text));
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER withdrawals_ledger AFTER INSERT OR UPDATE OF status ON withdrawals FOR EACH ROW EXECUTE FUNCTION olfa_withdrawal_ledger();

-- ═════════════ 4. Mandatory questionnaire + integrity ═════════════
ALTER TABLE consultation_reviews
  ADD COLUMN questionnaire_version smallint,
  ADD COLUMN quality smallint CHECK (quality BETWEEN 1 AND 5),
  ADD COLUMN commitment smallint CHECK (commitment BETWEEN 1 AND 5),
  ADD COLUMN effectiveness smallint CHECK (effectiveness BETWEEN 1 AND 5),
  ADD COLUMN outcome smallint CHECK (outcome BETWEEN 1 AND 5),
  ADD COLUMN next_session varchar(20) CHECK (next_session IN ('BOOKED_IN_APP','PLAN_IN_APP','AGREED_OUTSIDE','NOT_DISCUSSED','NO')),
  ADD COLUMN next_channel varchar(12) CHECK (next_channel IN ('OLFA','DIRECT','OTHER_APP','UNDECIDED')),
  ADD COLUMN contact_shared varchar(6) CHECK (contact_shared IN ('NO','YES','UNSURE')),
  ADD COLUMN off_platform_payment varchar(6) CHECK (off_platform_payment IN ('NO','YES','UNSURE')),
  ADD COLUMN external_channel varchar(6) CHECK (external_channel IN ('NO','YES','UNSURE')),
  -- new questionnaires must be complete (legacy star-only reviews stay valid)
  ADD CONSTRAINT consultation_reviews_complete CHECK (questionnaire_version IS NULL OR (
    quality IS NOT NULL AND commitment IS NOT NULL AND effectiveness IS NOT NULL AND outcome IS NOT NULL AND
    next_session IS NOT NULL AND next_channel IS NOT NULL AND contact_shared IS NOT NULL AND
    off_platform_payment IS NOT NULL AND external_channel IS NOT NULL));

-- A client with a completed consultation they have not reviewed cannot book another one.
CREATE FUNCTION olfa_booking_review_gate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM consultations c
             WHERE c.client_id = NEW.client_id AND c.status = 'COMPLETED'
               AND NOT EXISTS (SELECT 1 FROM consultation_reviews r WHERE r.consultation_id = c.id)) THEN
    RAISE EXCEPTION 'please review your last consultation first' USING ERRCODE = 'P0050';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER consultations_review_gate BEFORE INSERT ON consultations FOR EACH ROW EXECUTE FUNCTION olfa_booking_review_gate();

CREATE TABLE counselor_integrity_signals (
  id               bigserial PRIMARY KEY,
  counselor_id     uuid NOT NULL REFERENCES counselor_profiles(user_id) ON DELETE CASCADE,
  client_id        uuid REFERENCES users(id) ON DELETE SET NULL,
  consultation_id  uuid REFERENCES consultations(id) ON DELETE SET NULL,
  kind             varchar(40) NOT NULL,
  weight           smallint NOT NULL,
  details          jsonb NOT NULL DEFAULT '{}',
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX counselor_integrity_signals_idx ON counselor_integrity_signals (counselor_id, created_at DESC);

CREATE TYPE integrity_case_status AS ENUM ('OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW', 'CLEARED', 'WARNED', 'SUSPENDED', 'BANNED');
CREATE TABLE counselor_integrity_cases (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  counselor_id          uuid NOT NULL REFERENCES counselor_profiles(user_id) ON DELETE CASCADE,
  status                integrity_case_status NOT NULL DEFAULT 'OPEN',
  score                 smallint NOT NULL,
  reasons               text[] NOT NULL DEFAULT '{}',
  opened_at             timestamptz NOT NULL DEFAULT now(),
  notified_at           timestamptz,
  response_due_at       timestamptz,
  counselor_response    varchar(3000),
  responded_at          timestamptz,
  decided_by            uuid REFERENCES admin_users(id),
  decided_at            timestamptz,
  decision_reason       varchar(1000),
  CHECK (status NOT IN ('CLEARED','WARNED','SUSPENDED','BANNED') OR (decided_by IS NOT NULL AND decision_reason IS NOT NULL))
);
CREATE UNIQUE INDEX counselor_integrity_one_open ON counselor_integrity_cases (counselor_id) WHERE status IN ('OPEN','AWAITING_RESPONSE','UNDER_REVIEW');

-- ═════════════ 5. Permanent bans + re-registration block ═════════════
-- Identifiers are stored only as HMAC-SHA256 with a server secret; a banned
-- person cannot sign up again with the same phone, device, licence or payout account.
CREATE TYPE ban_identity_kind AS ENUM ('PHONE', 'DEVICE', 'LICENSE', 'PAYOUT');
CREATE TABLE banned_identities (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind        ban_identity_kind NOT NULL,
  value_hash  char(64) NOT NULL,
  user_id     uuid REFERENCES users(id) ON DELETE SET NULL,
  case_id     uuid REFERENCES counselor_integrity_cases(id) ON DELETE SET NULL,
  reason      varchar(300) NOT NULL,
  created_by  uuid REFERENCES admin_users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  lifted_at   timestamptz,
  lifted_by   uuid REFERENCES admin_users(id)
);
CREATE UNIQUE INDEX banned_identities_live ON banned_identities (kind, value_hash) WHERE lifted_at IS NULL;

ALTER TYPE moderation_action_type ADD VALUE IF NOT EXISTS 'BAN';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'INTEGRITY_CASE';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'WITHDRAWAL_UPDATE';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'REVIEW_REQUIRED';

-- ═════════════ 6. Store subscriptions ═════════════
ALTER TYPE subscription_status ADD VALUE IF NOT EXISTS 'ON_HOLD';
ALTER TYPE subscription_status ADD VALUE IF NOT EXISTS 'PAUSED';
ALTER TYPE subscription_status ADD VALUE IF NOT EXISTS 'PENDING';
ALTER TABLE user_subscriptions
  ADD COLUMN pending_product_id varchar(120),
  ADD COLUMN grace_until timestamptz,
  ADD COLUMN sandbox boolean NOT NULL DEFAULT false,
  ADD COLUMN replaced_by uuid REFERENCES user_subscriptions(id),
  ADD COLUMN last_verified_at timestamptz,
  ADD COLUMN latest_transaction_id varchar(200);

-- Seed: wallet and commission settings
INSERT INTO system_settings (key, value, description) VALUES
  ('wallet.holdDays', '7', 'Days a completed consultation''s earnings stay pending before they can be withdrawn'),
  ('wallet.minWithdrawalMajor', '50', 'Minimum withdrawal in major units of the currency'),
  ('integrity.responseDays', '7', 'Days a counselor has to respond to an integrity case'),
  ('counselor.policyVersion', '"2026-11"', 'Current professional policy version counselors must accept')
ON CONFLICT (key) DO NOTHING;

-- OLFA — initial schema (PostgreSQL 16)
-- Canonical DDL. prisma/schema.prisma mirrors this file (verified by
-- test/db/check_prisma_vs_db.py). Timestamps are timestamptz (UTC).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ───────────────────────── enums ─────────────────────────
CREATE TYPE account_status      AS ENUM ('PENDING_VERIFICATION','ACTIVE','REJECTED','SUSPENDED','RESTRICTED','DELETED');
CREATE TYPE gender              AS ENUM ('MALE','FEMALE');
CREATE TYPE marital_status      AS ENUM ('NEVER_MARRIED','DIVORCED','WIDOWED');
CREATE TYPE education_level     AS ENUM ('HIGH_SCHOOL','DIPLOMA','BACHELOR','MASTER','DOCTORATE');
CREATE TYPE marriage_timeline   AS ENUM ('WITHIN_6_MONTHS','WITHIN_1_YEAR','WITHIN_2_YEARS','NOT_SURE');
CREATE TYPE app_locale          AS ENUM ('ar','en');
CREATE TYPE photo_status        AS ENUM ('UPLOADING','PROCESSING','PENDING_REVIEW','APPROVED','REJECTED');
CREATE TYPE verification_type   AS ENUM ('PROFILE_REVIEW','LIVENESS','IDENTITY');
CREATE TYPE verification_status AS ENUM ('PENDING','APPROVED','REJECTED','CANCELLED');
CREATE TYPE discovery_action    AS ENUM ('SHOWN','LIKED','PASSED');
CREATE TYPE match_status        AS ENUM ('ACTIVE','UNMATCHED','BLOCKED');
CREATE TYPE message_type        AS ENUM ('TEXT','SYSTEM');
CREATE TYPE plan_code           AS ENUM ('FREE','PLUS','PREMIUM');
CREATE TYPE subscription_status AS ENUM ('ACTIVE','GRACE_PERIOD','BILLING_RETRY','CANCELLED','EXPIRED','REFUNDED','REVOKED');
CREATE TYPE payment_provider    AS ENUM ('APPLE','GOOGLE','WEB','ADMIN_GRANT');
CREATE TYPE payment_status      AS ENUM ('PENDING','SUCCEEDED','FAILED','REFUNDED');
CREATE TYPE transaction_type    AS ENUM ('CHARGE','REFUND','CHARGEBACK','ADJUSTMENT');
CREATE TYPE notification_type   AS ENUM ('NEW_LIKE','NEW_MATCH','NEW_MESSAGE','VERIFICATION_APPROVED','VERIFICATION_REJECTED','SUBSCRIPTION','SYSTEM');
CREATE TYPE report_target       AS ENUM ('USER','PHOTO','MESSAGE');
CREATE TYPE report_reason       AS ENUM ('FAKE_PROFILE','INAPPROPRIATE_PHOTO','HARASSMENT','SPAM_SCAM','UNDERAGE','NOT_SERIOUS','OTHER');
CREATE TYPE report_status       AS ENUM ('OPEN','IN_REVIEW','ACTION_TAKEN','DISMISSED');
CREATE TYPE ticket_category     AS ENUM ('PAYMENT','ACCOUNT','VERIFICATION','TECHNICAL','OTHER');
CREATE TYPE ticket_status       AS ENUM ('OPEN','PENDING_USER','RESOLVED','CLOSED');
CREATE TYPE actor_type          AS ENUM ('ADMIN','USER','SYSTEM');
CREATE TYPE moderation_action_type AS ENUM ('APPROVE_PROFILE','REJECT_PROFILE','APPROVE_PHOTO','REJECT_PHOTO','WARN','RESTRICT','SUSPEND','REACTIVATE','DISMISS_REPORT');

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

-- ───────────────────────── identity & profile ─────────────────────────
CREATE TABLE users (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164            varchar(16) NOT NULL CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  phone_country         char(2) NOT NULL,
  phone_verified_at     timestamptz,
  status                account_status NOT NULL DEFAULT 'PENDING_VERIFICATION',
  locale                app_locale NOT NULL DEFAULT 'ar',
  timezone              varchar(64) NOT NULL DEFAULT 'UTC',
  age_confirmed_at      timestamptz,
  terms_version         varchar(20),
  terms_accepted_at     timestamptz,
  last_active_at        timestamptz,
  deletion_requested_at timestamptz,
  deleted_at            timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);
-- One live account per phone; a soft-deleted account frees the number.
CREATE UNIQUE INDEX users_phone_live_uq ON users (phone_e164) WHERE deleted_at IS NULL;
CREATE INDEX users_status_idx ON users (status) WHERE deleted_at IS NULL;
CREATE TRIGGER users_updated BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE user_profiles (
  user_id             uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name        varchar(40) NOT NULL,
  birth_date          date NOT NULL,
  gender              gender NOT NULL,
  country_code        char(2) NOT NULL,
  city                varchar(80) NOT NULL,
  show_location       boolean NOT NULL DEFAULT true,
  marital_status      marital_status NOT NULL,
  has_children        boolean,
  wants_children      boolean,
  education           education_level NOT NULL,
  occupation          varchar(80) NOT NULL,
  marriage_timeline   marriage_timeline NOT NULL,
  smoking             boolean,
  willing_to_relocate boolean,
  bio                 varchar(500) NOT NULL,
  lifestyle           jsonb NOT NULL DEFAULT '{}',
  completeness        smallint NOT NULL DEFAULT 0 CHECK (completeness BETWEEN 0 AND 100),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX user_profiles_discovery_idx ON user_profiles (gender, country_code, birth_date);
CREATE TRIGGER user_profiles_updated BEFORE UPDATE ON user_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE interests (
  id        serial PRIMARY KEY,
  key       varchar(40) NOT NULL UNIQUE,
  name_ar   varchar(60) NOT NULL,
  name_en   varchar(60) NOT NULL,
  category  varchar(40) NOT NULL,
  is_basic  boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE user_interests (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  interest_id int  NOT NULL REFERENCES interests(id),
  PRIMARY KEY (user_id, interest_id)
);
CREATE INDEX user_interests_interest_idx ON user_interests (interest_id);

CREATE TABLE user_preferences (
  user_id          uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  age_min          smallint NOT NULL DEFAULT 18 CHECK (age_min >= 18),
  age_max          smallint NOT NULL DEFAULT 60 CHECK (age_max <= 99),
  same_country_only boolean NOT NULL DEFAULT false,
  country_codes    char(2)[] NOT NULL DEFAULT '{}',
  cities           text[] NOT NULL DEFAULT '{}',
  marital_statuses marital_status[] NOT NULL DEFAULT '{}',
  education_levels education_level[] NOT NULL DEFAULT '{}',
  occupations      text[] NOT NULL DEFAULT '{}',
  wants_children   boolean,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (age_min <= age_max)
);
CREATE TRIGGER user_preferences_updated BEFORE UPDATE ON user_preferences FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE user_photos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  storage_key      text NOT NULL UNIQUE,          -- private bucket (original)
  mime_type        varchar(32),
  bytes            int CHECK (bytes > 0 AND bytes <= 10485760),
  width            int,
  height           int,
  sha256           char(64),
  phash            varchar(32),
  variants         jsonb NOT NULL DEFAULT '{}',    -- {"thumb": key, "card": key, "full": key}
  position         smallint NOT NULL CHECK (position BETWEEN 0 AND 5),
  status           photo_status NOT NULL DEFAULT 'UPLOADING',
  rights_confirmed boolean NOT NULL CHECK (rights_confirmed),
  moderation       jsonb,
  reject_reason    varchar(200),
  created_at       timestamptz NOT NULL DEFAULT now(),
  reviewed_at      timestamptz,
  deleted_at       timestamptz
);
CREATE UNIQUE INDEX user_photos_slot_uq ON user_photos (user_id, position) WHERE deleted_at IS NULL;
CREATE INDEX user_photos_phash_idx ON user_photos (phash) WHERE deleted_at IS NULL;
CREATE INDEX user_photos_review_idx ON user_photos (status, created_at) WHERE deleted_at IS NULL;

-- Granted badges (what the public profile may show).
CREATE TABLE user_verifications (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        verification_type NOT NULL,
  verified_at timestamptz NOT NULL DEFAULT now(),
  provider    varchar(40) NOT NULL DEFAULT 'olfa-review',
  reference   varchar(120),
  revoked_at  timestamptz,
  PRIMARY KEY (user_id, type)
);

-- ───────────────────────── administration (referenced below) ─────────────────────────
CREATE TABLE admin_users (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email           varchar(160) NOT NULL UNIQUE,
  name            varchar(80) NOT NULL,
  password_hash   text NOT NULL,
  totp_secret_enc text,
  is_active       boolean NOT NULL DEFAULT true,
  last_login_at   timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE roles (
  id   serial PRIMARY KEY,
  key  varchar(40) NOT NULL UNIQUE,
  name varchar(80) NOT NULL
);
CREATE TABLE permissions (
  id          serial PRIMARY KEY,
  key         varchar(60) NOT NULL UNIQUE,
  description varchar(200)
);
CREATE TABLE role_permissions (
  role_id       int NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id int NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);
CREATE TABLE admin_user_roles (
  admin_id uuid NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
  role_id  int  NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  PRIMARY KEY (admin_id, role_id)
);

CREATE TABLE verification_requests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type          verification_type NOT NULL,
  status        verification_status NOT NULL DEFAULT 'PENDING',
  selfie_key    text,
  auto_result   jsonb,
  reject_code   varchar(40),
  reject_reason varchar(300),
  reviewed_by   uuid REFERENCES admin_users(id),
  submitted_at  timestamptz NOT NULL DEFAULT now(),
  reviewed_at   timestamptz
);
-- At most one open request per user and type.
CREATE UNIQUE INDEX verification_requests_open_uq ON verification_requests (user_id, type) WHERE status = 'PENDING';
CREATE INDEX verification_requests_queue_idx ON verification_requests (status, type, submitted_at);

-- ───────────────────────── discovery & matching ─────────────────────────
CREATE TABLE likes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (from_user_id <> to_user_id),
  UNIQUE (from_user_id, to_user_id)
);
CREATE INDEX likes_to_idx ON likes (to_user_id, created_at DESC);

CREATE TABLE passes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz,                         -- resurfacing policy (system_settings)
  CHECK (from_user_id <> to_user_id),
  UNIQUE (from_user_id, to_user_id)
);

CREATE TABLE matches (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_b_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status     match_status NOT NULL DEFAULT 'ACTIVE',
  score      smallint,
  created_at timestamptz NOT NULL DEFAULT now(),
  ended_at   timestamptz,
  ended_by   uuid REFERENCES users(id),
  CHECK (user_a_id < user_b_id),                    -- canonical order → one row per pair
  UNIQUE (user_a_id, user_b_id)
);
CREATE INDEX matches_b_idx ON matches (user_b_id);

CREATE TABLE compatibility_scores (
  viewer_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  candidate_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  score           smallint NOT NULL CHECK (score BETWEEN 0 AND 100),
  breakdown       jsonb NOT NULL,
  weights_version int NOT NULL,
  computed_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (viewer_id, candidate_id)
);

CREATE TABLE discovery_history (
  id           bigserial PRIMARY KEY,
  viewer_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  candidate_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action       discovery_action NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX discovery_history_viewer_idx ON discovery_history (viewer_id, candidate_id, created_at DESC);

-- ───────────────────────── messaging ─────────────────────────
CREATE TABLE conversations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id        uuid NOT NULL UNIQUE REFERENCES matches(id) ON DELETE CASCADE,
  started_by      uuid NOT NULL REFERENCES users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_message_at timestamptz
);
CREATE INDEX conversations_last_idx ON conversations (last_message_at DESC);

CREATE TABLE conversation_members (
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at       timestamptz NOT NULL DEFAULT now(),
  last_read_at    timestamptz,
  muted           boolean NOT NULL DEFAULT false,
  PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX conversation_members_user_idx ON conversation_members (user_id);

CREATE TABLE messages (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id   uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_message_id uuid NOT NULL,
  type              message_type NOT NULL DEFAULT 'TEXT',
  body              varchar(2000) NOT NULL CHECK (length(btrim(body)) > 0),
  flagged           boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,
  UNIQUE (conversation_id, sender_id, client_message_id)   -- idempotent send
);
CREATE INDEX messages_conv_idx ON messages (conversation_id, created_at DESC);

CREATE TABLE message_receipts (
  message_id   uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  delivered_at timestamptz,
  read_at      timestamptz,
  PRIMARY KEY (message_id, user_id)
);

-- ───────────────────────── commercial ─────────────────────────
CREATE TABLE subscription_plans (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       plan_code NOT NULL UNIQUE,
  name_ar    varchar(40) NOT NULL,
  name_en    varchar(40) NOT NULL,
  is_active  boolean NOT NULL DEFAULT true,
  sort_order smallint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER subscription_plans_updated BEFORE UPDATE ON subscription_plans FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Plan → feature values (daily_likes, daily_messages, advanced_filters…). Admin-editable.
CREATE TABLE feature_entitlements (
  plan_id     uuid NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  feature_key varchar(60) NOT NULL,
  value       jsonb NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (plan_id, feature_key)
);

CREATE TABLE plan_products (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id        uuid NOT NULL REFERENCES subscription_plans(id),
  provider       payment_provider NOT NULL,
  product_id     varchar(120) NOT NULL,
  duration_days  smallint NOT NULL CHECK (duration_days > 0),
  is_active      boolean NOT NULL DEFAULT true,
  UNIQUE (provider, product_id)
);

CREATE TABLE user_subscriptions (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id                 uuid NOT NULL REFERENCES subscription_plans(id),
  provider                payment_provider NOT NULL,
  status                  subscription_status NOT NULL,
  original_transaction_id varchar(200),
  product_id              varchar(120),
  starts_at               timestamptz NOT NULL,
  expires_at              timestamptz NOT NULL,
  auto_renew              boolean NOT NULL DEFAULT true,
  cancelled_at            timestamptz,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_at > starts_at),
  UNIQUE (provider, original_transaction_id)
);
CREATE INDEX user_subscriptions_active_idx ON user_subscriptions (user_id, status, expires_at DESC);
CREATE TRIGGER user_subscriptions_updated BEFORE UPDATE ON user_subscriptions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Daily counters. period_* are UTC instants of the user's local-day bounds.
CREATE TABLE usage_counters (
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  counter_key  varchar(40) NOT NULL,
  period_start timestamptz NOT NULL,
  period_end   timestamptz NOT NULL,
  used         int NOT NULL DEFAULT 0 CHECK (used >= 0),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end > period_start),
  PRIMARY KEY (user_id, counter_key, period_start)
);

-- Append-only consumption ledger.
CREATE TABLE usage_events (
  id           bigserial PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  counter_key  varchar(40) NOT NULL,
  delta        int NOT NULL,
  period_start timestamptz NOT NULL,
  ref_type     varchar(40),
  ref_id       varchar(80),
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX usage_events_user_idx ON usage_events (user_id, created_at DESC);

CREATE TABLE payments (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subscription_id     uuid REFERENCES user_subscriptions(id),
  provider            payment_provider NOT NULL,
  provider_payment_id varchar(200) NOT NULL,
  amount_minor        int,
  currency            char(3),
  status              payment_status NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  refunded_at         timestamptz,
  UNIQUE (provider, provider_payment_id)
);
CREATE INDEX payments_user_idx ON payments (user_id, created_at DESC);

CREATE TABLE transactions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id   uuid NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
  type         transaction_type NOT NULL,
  amount_minor int NOT NULL,
  currency     char(3) NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Raw store / gateway notifications, de-duplicated by provider event id.
CREATE TABLE purchase_events (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider     payment_provider NOT NULL,
  event_id     varchar(200) NOT NULL,
  event_type   varchar(80) NOT NULL,
  user_id      uuid REFERENCES users(id) ON DELETE SET NULL,
  payload      jsonb NOT NULL,
  received_at  timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  error        text,
  UNIQUE (provider, event_id)
);

-- ───────────────────────── administration (logs) ─────────────────────────
CREATE TABLE audit_logs (
  id          bigserial PRIMARY KEY,
  actor_type  actor_type NOT NULL,
  actor_id    uuid,
  action      varchar(80) NOT NULL,
  entity_type varchar(40) NOT NULL,
  entity_id   varchar(80) NOT NULL,
  before      jsonb,
  after       jsonb,
  reason      varchar(300),
  ip_hash     char(64),
  request_id  varchar(64),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_entity_idx ON audit_logs (entity_type, entity_id, created_at DESC);
CREATE INDEX audit_logs_actor_idx ON audit_logs (actor_id, created_at DESC);

CREATE TABLE moderation_actions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id       uuid NOT NULL REFERENCES admin_users(id),
  target_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action         moderation_action_type NOT NULL,
  target_type    varchar(40),
  target_id      varchar(80),
  report_id      uuid,
  reason         varchar(300),
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX moderation_actions_user_idx ON moderation_actions (target_user_id, created_at DESC);

-- ───────────────────────── support & safety ─────────────────────────
CREATE TABLE reports (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reported_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type      report_target NOT NULL DEFAULT 'USER',
  target_id        uuid,
  reason           report_reason NOT NULL,
  details          varchar(1000),
  status           report_status NOT NULL DEFAULT 'OPEN',
  priority         smallint NOT NULL DEFAULT 0,
  handled_by       uuid REFERENCES admin_users(id),
  resolution       varchar(300),
  created_at       timestamptz NOT NULL DEFAULT now(),
  resolved_at      timestamptz,
  CHECK (reporter_id <> reported_user_id)
);
CREATE INDEX reports_queue_idx ON reports (status, priority DESC, created_at);
CREATE INDEX reports_user_idx ON reports (reported_user_id);
ALTER TABLE moderation_actions ADD CONSTRAINT moderation_actions_report_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE SET NULL;

CREATE TABLE blocked_users (
  blocker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (blocker_id <> blocked_id),
  PRIMARY KEY (blocker_id, blocked_id)
);
CREATE INDEX blocked_users_blocked_idx ON blocked_users (blocked_id);

CREATE TABLE support_tickets (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category    ticket_category NOT NULL,
  subject     varchar(150) NOT NULL,
  status      ticket_status NOT NULL DEFAULT 'OPEN',
  assigned_to uuid REFERENCES admin_users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX support_tickets_queue_idx ON support_tickets (status, category, created_at);
CREATE TRIGGER support_tickets_updated BEFORE UPDATE ON support_tickets FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE ticket_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id   uuid NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  author_type actor_type NOT NULL,
  author_id   uuid NOT NULL,
  body        varchar(4000) NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type       notification_type NOT NULL,
  title_key  varchar(80) NOT NULL,
  body_key   varchar(80) NOT NULL,
  params     jsonb NOT NULL DEFAULT '{}',
  data       jsonb NOT NULL DEFAULT '{}',
  read_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_idx ON notifications (user_id, created_at DESC);

CREATE TABLE system_settings (
  key         varchar(80) PRIMARY KEY,
  value       jsonb NOT NULL,
  description varchar(300),
  updated_by  uuid REFERENCES admin_users(id),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER system_settings_updated BEFORE UPDATE ON system_settings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────── auth support ─────────────────────────
CREATE TABLE otp_challenges (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164   varchar(16) NOT NULL,
  code_hash    char(64) NOT NULL,                  -- HMAC-SHA256, never the code
  attempts     smallint NOT NULL DEFAULT 0,
  max_attempts smallint NOT NULL DEFAULT 5,
  ip_hash      char(64),
  device_id    varchar(80),
  expires_at   timestamptz NOT NULL,
  consumed_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX otp_challenges_phone_idx ON otp_challenges (phone_e164, created_at DESC);

CREATE TABLE user_sessions (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  family_id          uuid NOT NULL,                -- refresh-token rotation family
  refresh_token_hash char(64) NOT NULL UNIQUE,
  device_id          varchar(80) NOT NULL,
  platform           varchar(10) NOT NULL CHECK (platform IN ('ios','android','web')),
  app_version        varchar(20),
  fcm_token          text,
  ip_hash            char(64),
  user_agent         varchar(200),
  created_at         timestamptz NOT NULL DEFAULT now(),
  last_used_at       timestamptz NOT NULL DEFAULT now(),
  expires_at         timestamptz NOT NULL,
  revoked_at         timestamptz,
  revoked_reason     varchar(40)
);
CREATE INDEX user_sessions_user_idx ON user_sessions (user_id) WHERE revoked_at IS NULL;
CREATE INDEX user_sessions_family_idx ON user_sessions (family_id);

-- ═════════════════════════ atomic operations ═════════════════════════
-- Error codes raised (SQLSTATE class "OL"): mapped to API errors by the backend.
--   OLQ01 quota exceeded · OLL01 duplicate like · OLL02 not eligible · OLL03 blocked

-- Consume one unit of a daily counter, refusing to exceed p_limit.
-- Safe under concurrency: the ON CONFLICT row lock serialises increments.
CREATE OR REPLACE FUNCTION olfa_consume_quota(
  p_user uuid, p_key text, p_period_start timestamptz, p_period_end timestamptz,
  p_limit int, p_ref_type text DEFAULT NULL, p_ref_id text DEFAULT NULL
) RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_used int;
BEGIN
  IF p_limit IS NULL OR p_limit <= 0 THEN
    RAISE EXCEPTION 'quota exceeded: %', p_key USING ERRCODE = 'OLQ01';
  END IF;
  INSERT INTO usage_counters AS c (user_id, counter_key, period_start, period_end, used)
  VALUES (p_user, p_key, p_period_start, p_period_end, 1)
  ON CONFLICT (user_id, counter_key, period_start)
  DO UPDATE SET used = c.used + 1, updated_at = now()
     WHERE c.used < p_limit
  RETURNING c.used INTO v_used;
  IF v_used IS NULL THEN
    RAISE EXCEPTION 'quota exceeded: %', p_key USING ERRCODE = 'OLQ01';
  END IF;
  INSERT INTO usage_events (user_id, counter_key, delta, period_start, ref_type, ref_id)
  VALUES (p_user, p_key, 1, p_period_start, p_ref_type, p_ref_id);
  RETURN p_limit - v_used;   -- remaining
END $$;

-- Like with quota, duplicate protection and race-free mutual match creation.
-- Preference compatibility is checked by the matching service before calling.
CREATE OR REPLACE FUNCTION olfa_like(
  p_from uuid, p_to uuid, p_period_start timestamptz, p_period_end timestamptz, p_limit int
) RETURNS TABLE (like_id uuid, match_id uuid, likes_remaining int) LANGUAGE plpgsql AS $$
DECLARE
  v_like uuid; v_match uuid; v_remaining int;
  v_a uuid := LEAST(p_from, p_to); v_b uuid := GREATEST(p_from, p_to);
BEGIN
  -- Serialise all like activity for this pair (both directions).
  PERFORM pg_advisory_xact_lock(hashtextextended(v_a::text || ':' || v_b::text, 0));

  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p_from AND u.status = 'ACTIVE' AND u.deleted_at IS NULL AND u.deletion_requested_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p_to AND u.status = 'ACTIVE' AND u.deleted_at IS NULL AND u.deletion_requested_at IS NULL) THEN
    RAISE EXCEPTION 'not eligible' USING ERRCODE = 'OLL02';
  END IF;
  IF EXISTS (SELECT 1 FROM blocked_users b WHERE (b.blocker_id = p_from AND b.blocked_id = p_to)
                                             OR (b.blocker_id = p_to AND b.blocked_id = p_from)) THEN
    RAISE EXCEPTION 'blocked' USING ERRCODE = 'OLL03';
  END IF;
  IF EXISTS (SELECT 1 FROM likes l WHERE l.from_user_id = p_from AND l.to_user_id = p_to) THEN
    RAISE EXCEPTION 'duplicate like' USING ERRCODE = 'OLL01';
  END IF;

  v_remaining := olfa_consume_quota(p_from, 'likes', p_period_start, p_period_end, p_limit, 'like', p_to::text);

  INSERT INTO likes (from_user_id, to_user_id) VALUES (p_from, p_to) RETURNING id INTO v_like;
  DELETE FROM passes p WHERE p.from_user_id = p_from AND p.to_user_id = p_to;
  INSERT INTO discovery_history (viewer_id, candidate_id, action) VALUES (p_from, p_to, 'LIKED');

  IF EXISTS (SELECT 1 FROM likes l WHERE l.from_user_id = p_to AND l.to_user_id = p_from) THEN
    INSERT INTO matches (user_a_id, user_b_id) VALUES (v_a, v_b)
    ON CONFLICT (user_a_id, user_b_id) DO NOTHING
    RETURNING id INTO v_match;
  END IF;

  RETURN QUERY SELECT v_like, v_match, v_remaining;
END $$;

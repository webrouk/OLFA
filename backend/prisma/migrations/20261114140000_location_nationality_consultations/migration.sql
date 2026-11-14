-- OLFA — location, nationality, occupation keys, outside-country entitlement,
-- and the family-consultation marketplace (counselors, bookings, payments, reviews).

-- ───────────── Profile: nationality + approximate location ─────────────
-- Coordinates are stored rounded to 2 decimals (~1 km) and never exposed;
-- the API only returns a rounded distance.
ALTER TABLE user_profiles
  ADD COLUMN nationality         char(2) CHECK (nationality ~ '^[A-Z]{2}$'),
  ADD COLUMN latitude            double precision CHECK (latitude BETWEEN -90 AND 90 AND latitude = round(latitude::numeric, 2)),
  ADD COLUMN longitude           double precision CHECK (longitude BETWEEN -180 AND 180 AND longitude = round(longitude::numeric, 2)),
  ADD COLUMN location_country    char(2) CHECK (location_country ~ '^[A-Z]{2}$'),
  ADD COLUMN location_updated_at timestamptz,
  ADD CONSTRAINT location_pair CHECK ((latitude IS NULL) = (longitude IS NULL));
-- occupation now holds a key from shared/reference/occupations.tsv
ALTER TABLE user_profiles ALTER COLUMN occupation TYPE varchar(60);
CREATE INDEX user_profiles_geo_idx ON user_profiles (location_country, latitude, longitude);

-- Great-circle distance in km (no PostGIS dependency).
CREATE FUNCTION olfa_distance_km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
RETURNS double precision LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN lat1 IS NULL OR lat2 IS NULL THEN NULL ELSE
    2 * 6371 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2)
      + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))) END
$$;

-- ───────────── Enums ─────────────
CREATE TYPE counselor_kind        AS ENUM ('PSYCHOLOGIST','FAMILY_COUNSELOR');
CREATE TYPE counselor_status      AS ENUM ('PENDING','APPROVED','REJECTED','SUSPENDED');
CREATE TYPE consultation_service  AS ENUM ('PREMARITAL','MARITAL','FAMILY','PARENTING','INDIVIDUAL','DIVORCE_RECOVERY');
CREATE TYPE consultation_status   AS ENUM ('AWAITING_PAYMENT','PAID','CONFIRMED','COMPLETED','DECLINED','CANCELLED','REFUNDED','EXPIRED');
CREATE TYPE conversation_kind     AS ENUM ('MATCH','CONSULTATION');

ALTER TYPE notification_type ADD VALUE 'CONSULTATION_REQUEST';
ALTER TYPE notification_type ADD VALUE 'CONSULTATION_CONFIRMED';
ALTER TYPE notification_type ADD VALUE 'CONSULTATION_DECLINED';
ALTER TYPE notification_type ADD VALUE 'CONSULTATION_COMPLETED';
ALTER TYPE notification_type ADD VALUE 'COUNSELOR_APPROVED';
ALTER TYPE notification_type ADD VALUE 'COUNSELOR_REJECTED';
ALTER TYPE moderation_action_type ADD VALUE 'APPROVE_COUNSELOR';
ALTER TYPE moderation_action_type ADD VALUE 'REJECT_COUNSELOR';
ALTER TYPE moderation_action_type ADD VALUE 'SUSPEND_COUNSELOR';

-- ───────────── Counselors ─────────────
-- Any signed-in user may apply; only admin-approved counselors are listed.
CREATE TABLE counselor_profiles (
  user_id            uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  kind               counselor_kind NOT NULL,
  status             counselor_status NOT NULL DEFAULT 'PENDING',
  display_name       varchar(60) NOT NULL,
  headline           varchar(120) NOT NULL,
  bio                varchar(1500) NOT NULL,
  years_experience   smallint NOT NULL CHECK (years_experience BETWEEN 0 AND 60),
  license_number     varchar(80) NOT NULL,
  license_authority  varchar(120) NOT NULL,
  license_country    char(2) NOT NULL CHECK (license_country ~ '^[A-Z]{2}$'),
  credential_keys    text[] NOT NULL CHECK (cardinality(credential_keys) BETWEEN 1 AND 5),  -- private bucket
  languages          char(2)[] NOT NULL CHECK (cardinality(languages) BETWEEN 1 AND 6),       -- ISO 639-1
  services           consultation_service[] NOT NULL CHECK (cardinality(services) >= 1),
  rating_avg         numeric(3,2) NOT NULL DEFAULT 0 CHECK (rating_avg BETWEEN 0 AND 5),
  rating_count       int NOT NULL DEFAULT 0 CHECK (rating_count >= 0),
  reject_reason      varchar(300),
  reviewed_by        uuid REFERENCES admin_users(id),
  reviewed_at        timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'REJECTED' OR reject_reason IS NOT NULL)
);
CREATE INDEX counselor_profiles_listing_idx ON counselor_profiles (status, kind, rating_avg DESC);
CREATE INDEX counselor_profiles_languages_idx ON counselor_profiles USING gin (languages);
CREATE INDEX counselor_profiles_services_idx ON counselor_profiles USING gin (services);

-- What a counselor sells: service × language × duration at a price.
CREATE TABLE counselor_offerings (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  counselor_id     uuid NOT NULL REFERENCES counselor_profiles(user_id) ON DELETE CASCADE,
  service          consultation_service NOT NULL,
  language         char(2) NOT NULL CHECK (language ~ '^[a-z]{2}$'),
  duration_minutes smallint NOT NULL CHECK (duration_minutes IN (30, 45, 60, 90)),
  price_minor      int NOT NULL CHECK (price_minor > 0),
  currency         char(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  active           boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (counselor_id, service, language, duration_minutes)
);

-- ───────────── Consultations (bookings) ─────────────
CREATE TABLE consultations (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  counselor_id     uuid NOT NULL REFERENCES counselor_profiles(user_id),
  offering_id      uuid NOT NULL REFERENCES counselor_offerings(id),
  -- snapshot at booking time: later price edits never change a booking
  service          consultation_service NOT NULL,
  language         char(2) NOT NULL,
  duration_minutes smallint NOT NULL,
  price_minor      int NOT NULL CHECK (price_minor > 0),
  currency         char(3) NOT NULL,
  status           consultation_status NOT NULL DEFAULT 'AWAITING_PAYMENT',
  client_note      varchar(1000),
  preferred_time   timestamptz,
  scheduled_at     timestamptz,
  decline_reason   varchar(300),
  payment_id       uuid UNIQUE,
  expires_at       timestamptz NOT NULL,  -- payment window
  paid_at          timestamptz,
  confirmed_at     timestamptz,
  completed_at     timestamptz,
  cancelled_at     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (client_id <> counselor_id),
  -- payment must exist before the counselor can confirm
  CHECK (status IN ('AWAITING_PAYMENT','CANCELLED','EXPIRED') OR payment_id IS NOT NULL),
  CHECK (status NOT IN ('CONFIRMED','COMPLETED') OR scheduled_at IS NOT NULL)
);
CREATE INDEX consultations_client_idx ON consultations (client_id, created_at DESC);
CREATE INDEX consultations_counselor_idx ON consultations (counselor_id, status, created_at DESC);
-- one open booking per client × counselor (prevents double-paying)
CREATE UNIQUE INDEX consultations_one_open_idx ON consultations (client_id, counselor_id)
  WHERE status IN ('AWAITING_PAYMENT','PAID','CONFIRMED');

ALTER TABLE payments
  ADD COLUMN consultation_id uuid REFERENCES consultations(id),
  ADD CONSTRAINT payment_single_purpose CHECK (subscription_id IS NULL OR consultation_id IS NULL);
ALTER TABLE consultations ADD CONSTRAINT consultations_payment_fk FOREIGN KEY (payment_id) REFERENCES payments(id);

-- Allowed status transitions + "paid in full before confirmation".
CREATE FUNCTION olfa_consultation_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ok boolean; pay payments%ROWTYPE;
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
  ELSIF NEW.status = 'CONFIRMED' THEN NEW.confirmed_at := now();
  ELSIF NEW.status = 'COMPLETED' THEN NEW.completed_at := now();
  ELSIF NEW.status IN ('CANCELLED','DECLINED','EXPIRED') THEN NEW.cancelled_at := now();
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER consultations_guard BEFORE UPDATE ON consultations FOR EACH ROW EXECUTE FUNCTION olfa_consultation_guard();

-- Conversations can now belong to a match OR a consultation.
ALTER TABLE conversations
  ALTER COLUMN match_id DROP NOT NULL,
  ADD COLUMN kind conversation_kind NOT NULL DEFAULT 'MATCH',
  ADD COLUMN consultation_id uuid UNIQUE REFERENCES consultations(id) ON DELETE CASCADE,
  ADD CONSTRAINT conversation_owner CHECK (
    (kind = 'MATCH' AND match_id IS NOT NULL AND consultation_id IS NULL) OR
    (kind = 'CONSULTATION' AND consultation_id IS NOT NULL AND match_id IS NULL));

-- ───────────── Reviews ─────────────
CREATE TABLE consultation_reviews (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id uuid NOT NULL UNIQUE REFERENCES consultations(id) ON DELETE CASCADE,
  client_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  counselor_id    uuid NOT NULL REFERENCES counselor_profiles(user_id) ON DELETE CASCADE,
  rating          smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment         varchar(1000),
  hidden          boolean NOT NULL DEFAULT false,  -- moderation
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX consultation_reviews_counselor_idx ON consultation_reviews (counselor_id, created_at DESC);

-- Only the client of a COMPLETED consultation can review it, once.
CREATE FUNCTION olfa_review_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c consultations%ROWTYPE;
BEGIN
  SELECT * INTO c FROM consultations WHERE id = NEW.consultation_id;
  IF c.status <> 'COMPLETED' OR c.client_id <> NEW.client_id OR c.counselor_id <> NEW.counselor_id THEN
    RAISE EXCEPTION 'only the client of a completed consultation can review it' USING ERRCODE = 'P0003';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER consultation_reviews_guard BEFORE INSERT ON consultation_reviews FOR EACH ROW EXECUTE FUNCTION olfa_review_guard();

CREATE FUNCTION olfa_review_aggregate() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cid uuid := COALESCE(NEW.counselor_id, OLD.counselor_id);
BEGIN
  UPDATE counselor_profiles cp SET
    rating_count = s.n, rating_avg = COALESCE(round(s.avg, 2), 0), updated_at = now()
  FROM (SELECT count(*) AS n, avg(rating)::numeric AS avg FROM consultation_reviews WHERE counselor_id = cid AND NOT hidden) s
  WHERE cp.user_id = cid;
  RETURN NULL;
END $$;
CREATE TRIGGER consultation_reviews_aggregate AFTER INSERT OR UPDATE OR DELETE ON consultation_reviews
  FOR EACH ROW EXECUTE FUNCTION olfa_review_aggregate();

-- Counselor plans: licensed professionals can subscribe to Plus or Premium with
-- their own benefits (they never use Discovery, likes or member search, and they
-- never see ads — ads only run in Discovery):
--   directory_boost  0 / 1 / 2 — placed higher in the counselor directory
--   featured_badge   "Featured counselor" mark on the card and profile
--   profile_insights profile views, unique visitors and requests in the last 30 days
-- A plan is for members or for professionals, never both (FREE is everyone's base).

CREATE TYPE plan_audience AS ENUM ('MEMBER','PROFESSIONAL');
ALTER TABLE subscription_plans ADD COLUMN audience plan_audience NOT NULL DEFAULT 'MEMBER';
ALTER TABLE subscription_plans ADD CONSTRAINT subscription_plans_audience_ck
  CHECK ((code::text LIKE 'PRO\_%') = (audience = 'PROFESSIONAL'));

INSERT INTO subscription_plans (code, name_ar, name_en, sort_order, audience) VALUES
  ('PRO_PLUS', 'بلس للمستشارين', 'Counselor Plus', 10, 'PROFESSIONAL'),
  ('PRO_PREMIUM', 'بريميوم للمستشارين', 'Counselor Premium', 11, 'PROFESSIONAL')
ON CONFLICT (code) DO NOTHING;

-- A subscription's plan must match the account: member plans for members,
-- counselor plans for psychologists and family counselors.
CREATE FUNCTION olfa_subscription_audience() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE aud plan_audience; acct text;
BEGIN
  SELECT audience INTO aud FROM subscription_plans WHERE id = NEW.plan_id;
  SELECT account_type::text INTO acct FROM users WHERE id = NEW.user_id;
  IF acct IS NOT NULL AND (aud = 'PROFESSIONAL') <> (acct IN ('PSYCHOLOGIST','FAMILY_COUNSELOR')) THEN
    RAISE EXCEPTION 'plan % is not for % accounts', aud, acct USING ERRCODE = 'P0076';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER user_subscriptions_audience
  BEFORE INSERT OR UPDATE OF plan_id, user_id ON user_subscriptions
  FOR EACH ROW EXECUTE FUNCTION olfa_subscription_audience();

-- Counselor features live only on FREE (always off) and counselor plans;
-- the boost is a whole number 0–2.
CREATE FUNCTION olfa_pro_feature_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c text; aud plan_audience;
BEGIN
  IF NEW.feature_key NOT IN ('directory_boost','featured_badge','profile_insights') THEN RETURN NEW; END IF;
  SELECT code::text, audience INTO c, aud FROM subscription_plans WHERE id = NEW.plan_id;
  IF aud <> 'PROFESSIONAL' AND c <> 'FREE' THEN
    RAISE EXCEPTION 'counselor features belong to counselor plans' USING ERRCODE = 'P0077';
  END IF;
  IF NEW.feature_key = 'directory_boost' THEN
    IF jsonb_typeof(NEW.value) <> 'number' OR NEW.value::text !~ '^[0-2]$' THEN
      RAISE EXCEPTION 'directory_boost must be 0, 1 or 2' USING ERRCODE = 'P0077';
    END IF;
    IF c = 'FREE' AND NEW.value <> '0'::jsonb THEN
      RAISE EXCEPTION 'the free plan has no boost' USING ERRCODE = 'P0077';
    END IF;
  ELSE
    IF jsonb_typeof(NEW.value) <> 'boolean' THEN
      RAISE EXCEPTION '% must be a boolean', NEW.feature_key USING ERRCODE = 'P0077';
    END IF;
    IF c = 'FREE' AND NEW.value <> 'false'::jsonb THEN
      RAISE EXCEPTION 'the free plan has no % ', NEW.feature_key USING ERRCODE = 'P0077';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER feature_entitlements_pro_guard
  BEFORE INSERT OR UPDATE ON feature_entitlements
  FOR EACH ROW EXECUTE FUNCTION olfa_pro_feature_guard();

-- The effective plan's value for one feature (same rule as EntitlementsService).
CREATE FUNCTION olfa_feature_value(p_user uuid, p_key text) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT fe.value
  FROM feature_entitlements fe
  JOIN subscription_plans sp ON sp.id = fe.plan_id
  WHERE fe.feature_key = p_key
    AND sp.code = COALESCE((
      SELECT p.code FROM user_subscriptions s JOIN subscription_plans p ON p.id = s.plan_id
      WHERE s.user_id = p_user AND s.status IN ('ACTIVE','GRACE_PERIOD','CANCELLED') AND s.expires_at > now()
      ORDER BY s.expires_at DESC LIMIT 1), 'FREE')
$$;
CREATE FUNCTION olfa_counselor_boost(p_user uuid) RETURNS int LANGUAGE sql STABLE AS $$
  SELECT COALESCE((SELECT CASE WHEN jsonb_typeof(v) = 'number' THEN v::text::int END FROM olfa_feature_value(p_user, 'directory_boost') v), 0)
$$;

-- Profile views for insights: one row per viewer per day (no counts to fake,
-- no profile of who looked is ever shown to the counselor). Kept 90 days.
CREATE TABLE counselor_profile_views (
  counselor_id uuid NOT NULL REFERENCES counselor_profiles(user_id) ON DELETE CASCADE,
  viewer_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day          date NOT NULL DEFAULT (now() AT TIME ZONE 'utc')::date,
  PRIMARY KEY (counselor_id, day, viewer_id),
  CHECK (counselor_id <> viewer_id)
);
CREATE INDEX counselor_profile_views_day_idx ON counselor_profile_views (day);

-- existing databases (fresh ones get the same rows from seed.sql)
INSERT INTO feature_entitlements (plan_id, feature_key, value)
SELECT p.id, v.k, v.val::jsonb FROM subscription_plans p
JOIN (VALUES
  ('FREE','directory_boost','0'), ('FREE','featured_badge','false'), ('FREE','profile_insights','false'),
  ('PRO_PLUS','directory_boost','1'), ('PRO_PLUS','featured_badge','false'), ('PRO_PLUS','profile_insights','true'), ('PRO_PLUS','show_ads','false'),
  ('PRO_PREMIUM','directory_boost','2'), ('PRO_PREMIUM','featured_badge','true'), ('PRO_PREMIUM','profile_insights','true'), ('PRO_PREMIUM','show_ads','false')
) v(code, k, val) ON v.code = p.code::text
ON CONFLICT (plan_id, feature_key) DO NOTHING;

INSERT INTO plan_products (plan_id, provider, product_id, duration_days)
SELECT p.id, v.provider::payment_provider, v.product_id, 30
FROM (VALUES ('PRO_PLUS','APPLE','olfa.pro.plus.monthly'), ('PRO_PREMIUM','APPLE','olfa.pro.premium.monthly'),
             ('PRO_PLUS','GOOGLE','olfa_pro_plus'), ('PRO_PREMIUM','GOOGLE','olfa_pro_premium')) v(code, provider, product_id)
JOIN subscription_plans p ON p.code::text = v.code
ON CONFLICT (provider, product_id) DO NOTHING;

-- Native ads in Discovery (Google AdMob), Free plan only.
--  * show_ads: plan feature (admin-editable for FREE). Paid plans can never show ads: enforced here.
--  * ads.discovery: one settings object (kill switch, frequency, ad unit ids). Off until AdMob is set up.

CREATE OR REPLACE FUNCTION olfa_paid_plans_no_ads() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.feature_key = 'show_ads' AND NEW.value <> 'false'::jsonb
     AND (SELECT code FROM subscription_plans WHERE id = NEW.plan_id) <> 'FREE' THEN
    RAISE EXCEPTION 'paid plans never show ads' USING ERRCODE = 'P0060';
  END IF;
  IF NEW.feature_key = 'show_ads' AND jsonb_typeof(NEW.value) <> 'boolean' THEN
    RAISE EXCEPTION 'show_ads must be a boolean' USING ERRCODE = 'P0060';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER feature_entitlements_paid_no_ads
  BEFORE INSERT OR UPDATE ON feature_entitlements
  FOR EACH ROW EXECUTE FUNCTION olfa_paid_plans_no_ads();

-- existing databases (fresh ones get the same rows from seed.sql)
INSERT INTO feature_entitlements (plan_id, feature_key, value)
SELECT p.id, 'show_ads', (p.code = 'FREE')::text::jsonb FROM subscription_plans p
ON CONFLICT (plan_id, feature_key) DO NOTHING;

INSERT INTO system_settings (key, value, description) VALUES
  ('ads.discovery',
   '{"enabled":false,"firstAfter":4,"interval":6,"maxPerSession":8,"preloadAhead":2,"personalized":false,"maxAdContentRating":"PG","units":{"android":"","ios":""}}',
   'Native ads between Discovery cards (Free plan only): kill switch, first ad after N profiles, then every N, max per session, AdMob native ad unit ids')
ON CONFLICT (key) DO NOTHING;

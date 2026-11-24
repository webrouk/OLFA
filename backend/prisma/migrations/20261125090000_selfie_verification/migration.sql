-- Selfie verification at first sign-up (after the profile photos).
-- Criteria and limits: src/domain/selfie.ts and docs/VERIFICATION.md.

-- One-time capture challenge: a random gesture + a private upload slot, valid 10 minutes.
CREATE TABLE selfie_challenges (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  gesture      varchar(20) NOT NULL CHECK (gesture IN ('thumb_up','victory','open_palm','point_up','hand_on_chin')),
  storage_key  varchar(200) NOT NULL UNIQUE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL,
  used_at      timestamptz,
  CHECK (expires_at > created_at)
);
CREATE INDEX selfie_challenges_user_idx ON selfie_challenges (user_id, created_at DESC);

ALTER TABLE verification_requests
  ADD COLUMN challenge_gesture varchar(20),
  -- the person asked that a woman from the team reviews the selfie
  ADD COLUMN prefer_female_reviewer boolean NOT NULL DEFAULT false;

-- A selfie (LIVENESS request) always has its private picture while pending.
ALTER TABLE verification_requests ADD CONSTRAINT verification_liveness_selfie
  CHECK (type <> 'LIVENESS' OR status <> 'PENDING' OR selfie_key IS NOT NULL);
-- One selfie waiting for review per person.
CREATE UNIQUE INDEX verification_one_pending_liveness ON verification_requests (user_id)
  WHERE type = 'LIVENESS' AND status = 'PENDING';

-- Selfies are deleted after the decision (default 30 days) and unused uploads after a day.
CREATE FUNCTION olfa_purge_selfies() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE days int := olfa_setting_int('verification.selfieRetentionDays', 30); n int; m int;
BEGIN
  WITH old AS (
    SELECT id, selfie_key FROM verification_requests
    WHERE type = 'LIVENESS' AND selfie_key IS NOT NULL AND status <> 'PENDING'
      AND reviewed_at IS NOT NULL AND reviewed_at < now() - make_interval(days => days)
    FOR UPDATE
  ), queued AS (
    INSERT INTO storage_garbage (storage_key) SELECT selfie_key FROM old ON CONFLICT DO NOTHING
  )
  UPDATE verification_requests v SET selfie_key = NULL FROM old WHERE v.id = old.id;
  GET DIAGNOSTICS n = ROW_COUNT;
  -- challenges never turned into a selfie (abandoned or failed captures)
  WITH stale AS (
    DELETE FROM selfie_challenges c
    WHERE c.created_at < now() - interval '1 day'
      AND NOT EXISTS (SELECT 1 FROM verification_requests v WHERE v.selfie_key = c.storage_key)
    RETURNING storage_key
  )
  INSERT INTO storage_garbage (storage_key) SELECT storage_key FROM stale ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS m = ROW_COUNT;
  RETURN n + m;
END $$;

INSERT INTO system_settings (key, value, description) VALUES
  ('verification.selfieRequired', '1', 'First sign-up needs a live selfie after the profile photos (1 = on)'),
  ('verification.selfieRetentionDays', '30', 'Days a reviewed selfie is kept before deletion')
ON CONFLICT (key) DO NOTHING;

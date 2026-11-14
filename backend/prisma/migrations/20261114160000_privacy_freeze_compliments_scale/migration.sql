-- Privacy settings enforced by the server, temporary account freeze,
-- compliments (a message sent with a like, monthly quota), and indexes
-- for nearest-first discovery at scale.

-- ───────────── privacy ─────────────
-- show_city lives in user_profiles.show_location (already public-profile aware).
CREATE TABLE user_privacy_settings (
  user_id        uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  discoverable   boolean NOT NULL DEFAULT true,   -- false: hidden from discovery (existing matches keep chatting)
  show_online    boolean NOT NULL DEFAULT true,   -- reciprocal: hiding yours hides others' from you
  read_receipts  boolean NOT NULL DEFAULT true,   -- reciprocal
  incognito      boolean NOT NULL DEFAULT false,  -- Premium: only people you liked can see you
  blur_photos    boolean NOT NULL DEFAULT false,  -- photos blurred until you match
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Plan feature as a boolean, from the effective subscription (same rule as EntitlementsService).
CREATE FUNCTION olfa_has_feature(p_user uuid, p_key text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT COALESCE((
    SELECT fe.value = 'true'::jsonb
    FROM feature_entitlements fe
    JOIN subscription_plans sp ON sp.id = fe.plan_id
    WHERE fe.feature_key = p_key
      AND sp.code = COALESCE((
        SELECT p.code FROM user_subscriptions s JOIN subscription_plans p ON p.id = s.plan_id
        WHERE s.user_id = p_user AND s.status IN ('ACTIVE','GRACE_PERIOD','CANCELLED') AND s.expires_at > now()
        ORDER BY s.expires_at DESC LIMIT 1), 'FREE')
  ), false)
$$;

-- Incognito is a Premium feature: switched off when the plan no longer includes it.
CREATE FUNCTION olfa_reset_lapsed_privacy() RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  UPDATE user_privacy_settings SET incognito = false, updated_at = now()
  WHERE incognito AND NOT olfa_has_feature(user_id, 'incognito');
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

-- ───────────── freeze ─────────────
-- A frozen account is hidden everywhere but keeps its data, matches,
-- conversations and subscription. Signing in and choosing "reactivate" restores it.
ALTER TABLE users ADD COLUMN frozen_at timestamptz, ADD COLUMN freeze_reason varchar(40);
CREATE INDEX users_frozen_idx ON users (frozen_at) WHERE frozen_at IS NOT NULL;

-- ───────────── compliments ─────────────
ALTER TABLE likes ADD COLUMN compliment varchar(300);
ALTER TABLE likes ADD CONSTRAINT likes_compliment_len CHECK (compliment IS NULL OR char_length(btrim(compliment)) BETWEEN 2 AND 300);
CREATE INDEX likes_to_compliment_idx ON likes (to_user_id, created_at DESC) WHERE compliment IS NOT NULL;
ALTER TYPE notification_type ADD VALUE 'NEW_COMPLIMENT';

-- Like: same as before + frozen accounts are not eligible on either side.
CREATE OR REPLACE FUNCTION olfa_like(
  p_from uuid, p_to uuid, p_period_start timestamptz, p_period_end timestamptz, p_limit int
) RETURNS TABLE (like_id uuid, match_id uuid, likes_remaining int) LANGUAGE plpgsql AS $$
DECLARE
  v_like uuid; v_match uuid; v_remaining int;
  v_a uuid := LEAST(p_from, p_to); v_b uuid := GREATEST(p_from, p_to);
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(v_a::text || ':' || v_b::text, 0));

  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p_from AND u.status = 'ACTIVE' AND u.deleted_at IS NULL AND u.deletion_requested_at IS NULL AND u.frozen_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p_to AND u.status = 'ACTIVE' AND u.deleted_at IS NULL AND u.deletion_requested_at IS NULL AND u.frozen_at IS NULL) THEN
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

-- ───────────── scale: nearest-first discovery ─────────────
-- KNN over a GiST index (cube/earthdistance are standard contrib modules,
-- available on RDS, Cloud SQL, Azure and Supabase).
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;
CREATE INDEX user_profiles_knn_idx ON user_profiles USING gist (ll_to_earth(latitude, longitude))
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
-- Nearest-first inside one country (Free plans, "my country" filter).
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE INDEX user_profiles_country_knn_idx ON user_profiles USING gist (country_code, ll_to_earth(latitude, longitude))
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
-- Per-candidate eligibility check (verifications and passes are covered by their keys).
CREATE INDEX user_photos_approved_idx ON user_photos (user_id) WHERE status = 'APPROVED' AND deleted_at IS NULL;
CREATE INDEX users_active_seen_idx ON users (last_active_at DESC) WHERE status = 'ACTIVE' AND deleted_at IS NULL AND frozen_at IS NULL;

-- Per-candidate eligibility for one viewer, as an inlinable SQL function so
-- the discovery query can walk the KNN index and filter row by row.
CREATE FUNCTION olfa_candidate_ok(p_viewer uuid, p_cand uuid, p_min_photos int, p_cooldown_h int) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT
        -- approved profiles with enough reviewed photos, or brand-new accounts
        -- awaiting review (shown as "new · under review", without photos or bio)
        ((EXISTS (SELECT 1 FROM user_verifications v WHERE v.user_id = p_cand AND v.type = 'PROFILE_REVIEW' AND v.revoked_at IS NULL)
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

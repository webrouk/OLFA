-- Discovery candidate pool (coarse, index-friendly filters). The matching
-- engine then applies the full MUTUAL hard filters, scores and ranks.
-- $1 viewer id · $2 viewer gender · $3 min birth date · $4 max birth date
-- $5 viewer birth date · $6 allowed countries (NULL = any) · $7 min approved photos
-- $8 shown-cooldown hours · $9 pool size · $10/$11 viewer latitude/longitude (NULL = unknown)
--
-- Built to stay fast with millions of members: branch A walks the GiST index
-- nearest-first (KNN, user_profiles_knn_idx) and stops at the pool size;
-- branch B covers members without a location (or a viewer without one) by
-- recent activity. Per-row checks live in olfa_candidate_ok() (inlined).
-- New accounts awaiting review are included (flagged by the API, no photos/bio).
WITH a AS (
  SELECT u.id, u.last_active_at,
         earth_distance(ll_to_earth($10::float8, $11::float8), ll_to_earth(p.latitude, p.longitude)) / 1000 AS distance_km
  FROM user_profiles p
  JOIN users u ON u.id = p.user_id
  JOIN user_preferences pr ON pr.user_id = p.user_id
  WHERE $10::float8 IS NOT NULL
    AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL
    AND u.status IN ('ACTIVE','PENDING_VERIFICATION') AND u.deleted_at IS NULL AND u.deletion_requested_at IS NULL AND u.frozen_at IS NULL
    AND u.id <> $1::uuid
    AND p.gender <> $2::gender
    AND p.birth_date BETWEEN $3::date AND $4::date
    AND date_part('year', age(now(), $5::date)) BETWEEN pr.age_min AND pr.age_max
    AND ($6::char(2)[] IS NULL OR p.country_code = ANY ($6::char(2)[]))
    AND olfa_candidate_ok($1::uuid, u.id, $7::int, $8::int)
  ORDER BY ll_to_earth(p.latitude, p.longitude) <-> ll_to_earth($10::float8, $11::float8)
  LIMIT $9::int
), b AS (
  SELECT u.id, u.last_active_at, NULL::float8 AS distance_km
  FROM users u
  JOIN user_profiles p ON p.user_id = u.id
  JOIN user_preferences pr ON pr.user_id = u.id
  WHERE ($10::float8 IS NULL OR p.latitude IS NULL OR p.longitude IS NULL)
    AND u.status IN ('ACTIVE','PENDING_VERIFICATION') AND u.deleted_at IS NULL AND u.deletion_requested_at IS NULL AND u.frozen_at IS NULL
    AND u.id <> $1::uuid
    AND p.gender <> $2::gender
    AND p.birth_date BETWEEN $3::date AND $4::date
    AND date_part('year', age(now(), $5::date)) BETWEEN pr.age_min AND pr.age_max
    AND ($6::char(2)[] IS NULL OR p.country_code = ANY ($6::char(2)[]))
    AND olfa_candidate_ok($1::uuid, u.id, $7::int, $8::int)
  ORDER BY u.last_active_at DESC NULLS LAST, u.id
  LIMIT $9::int
), pool AS (
  SELECT * FROM (SELECT * FROM a UNION ALL SELECT * FROM b) x
  ORDER BY distance_km ASC NULLS LAST, last_active_at DESC NULLS LAST, id
  LIMIT $9::int
)
SELECT
  u.id,
  p.display_name, p.birth_date, p.gender, p.country_code, p.city, p.show_location,
  p.marital_status, p.education, p.occupation, p.marriage_timeline,
  p.has_children, p.wants_children, p.smoking, p.willing_to_relocate, p.bio, p.completeness, p.nationality,
  pool.distance_km, p.height_cm, p.weight_kg,
  pr.age_min, pr.age_max, pr.same_country_only, pr.country_codes, pr.cities,
  pr.marital_statuses, pr.education_levels, pr.occupations, pr.wants_children AS pref_wants_children,
  COALESCE((SELECT array_agg(i.key ORDER BY i.key) FROM user_interests ui JOIN interests i ON i.id = ui.interest_id WHERE ui.user_id = u.id), '{}') AS interests
FROM pool
JOIN users u ON u.id = pool.id
JOIN user_profiles p ON p.user_id = u.id
JOIN user_preferences pr ON pr.user_id = u.id
ORDER BY pool.distance_km ASC NULLS LAST, pool.last_active_at DESC NULLS LAST, u.id

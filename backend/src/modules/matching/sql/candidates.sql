-- Discovery candidate pool (coarse, index-friendly filters). The matching
-- engine then applies the full MUTUAL hard filters, scores and ranks.
-- $1 viewer id · $2 viewer gender · $3 min birth date · $4 max birth date
-- $5 viewer birth date · $6 allowed countries (NULL = any) · $7 min approved photos
-- $8 shown-cooldown hours · $9 pool size
SELECT
  u.id,
  p.display_name, p.birth_date, p.gender, p.country_code, p.city, p.show_location,
  p.marital_status, p.education, p.occupation, p.marriage_timeline,
  p.has_children, p.wants_children, p.smoking, p.willing_to_relocate, p.bio, p.completeness,
  pr.age_min, pr.age_max, pr.same_country_only, pr.country_codes, pr.cities,
  pr.marital_statuses, pr.education_levels, pr.occupations, pr.wants_children AS pref_wants_children,
  COALESCE(array_agg(i.key ORDER BY i.key) FILTER (WHERE i.key IS NOT NULL), '{}') AS interests
FROM users u
JOIN user_profiles p     ON p.user_id = u.id
JOIN user_preferences pr ON pr.user_id = u.id
LEFT JOIN user_interests ui ON ui.user_id = u.id
LEFT JOIN interests i       ON i.id = ui.interest_id
WHERE u.status = 'ACTIVE'
  AND u.deleted_at IS NULL
  AND u.deletion_requested_at IS NULL
  AND u.id <> $1::uuid
  AND p.gender <> $2::gender
  AND p.birth_date BETWEEN $3::date AND $4::date
  AND date_part('year', age(now(), $5::date)) BETWEEN pr.age_min AND pr.age_max
  AND ($6::char(2)[] IS NULL OR p.country_code = ANY ($6::char(2)[]))
  AND EXISTS (SELECT 1 FROM user_verifications v
              WHERE v.user_id = u.id AND v.type = 'PROFILE_REVIEW' AND v.revoked_at IS NULL)
  AND (SELECT count(*) FROM user_photos ph
       WHERE ph.user_id = u.id AND ph.status = 'APPROVED' AND ph.deleted_at IS NULL) >= $7::int
  AND NOT EXISTS (SELECT 1 FROM blocked_users b
                  WHERE (b.blocker_id = $1::uuid AND b.blocked_id = u.id)
                     OR (b.blocker_id = u.id AND b.blocked_id = $1::uuid))
  AND NOT EXISTS (SELECT 1 FROM likes l WHERE l.from_user_id = $1::uuid AND l.to_user_id = u.id)
  AND NOT EXISTS (SELECT 1 FROM passes ps
                  WHERE ps.from_user_id = $1::uuid AND ps.to_user_id = u.id
                    AND (ps.expires_at IS NULL OR ps.expires_at > now()))
  AND NOT EXISTS (SELECT 1 FROM matches m
                  WHERE m.user_a_id = LEAST($1::uuid, u.id) AND m.user_b_id = GREATEST($1::uuid, u.id))
  AND NOT EXISTS (SELECT 1 FROM discovery_history h
                  WHERE h.viewer_id = $1::uuid AND h.candidate_id = u.id AND h.action = 'SHOWN'
                    AND h.created_at > now() - make_interval(hours => $8::int))
GROUP BY u.id, p.user_id, pr.user_id
ORDER BY u.last_active_at DESC NULLS LAST, u.id
LIMIT $9::int

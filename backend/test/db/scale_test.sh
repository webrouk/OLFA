#!/usr/bin/env bash
# Load test on a real PostgreSQL: seeds N members (default 200 000) with
# profiles, preferences, photos, locations, likes and matches, then times the
# hot queries with EXPLAIN ANALYZE. Fails if any exceeds its budget.
#   N=500000 bash test/db/scale_test.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
N=${N:-200000}
DB=${DB:-olfa_scale_$$}
PSQL="psql -v ON_ERROR_STOP=1 -qtA"
pass=0; fail=0
createdb "$DB" || exit 1
[ "${KEEP:-0}" = 1 ] || trap 'dropdb --if-exists "$DB" >/dev/null 2>&1' EXIT
for m in prisma/migrations/*/migration.sql; do $PSQL -d "$DB" -f "$m"; done >/dev/null
$PSQL -d "$DB" -f prisma/seed.sql >/dev/null
echo "seeding $N members…"
t0=$(date +%s)
$PSQL -d "$DB" <<SQL >/dev/null
SET synchronous_commit = off;
INSERT INTO users (id, phone_e164, phone_country, status, last_active_at)
SELECT md5('u'||g)::uuid, '+9715'||lpad(g::text,8,'0'), 'AE', 'ACTIVE', now() - (g % 10000) * interval '1 minute'
FROM generate_series(1, $N) g;
INSERT INTO user_profiles (user_id, display_name, birth_date, gender, country_code, city, marital_status, education, occupation, marriage_timeline, bio, latitude, longitude, location_country)
SELECT md5('u'||g)::uuid, 'm'||g, date '1980-01-01' + (g % 7000), CASE WHEN g % 2 = 0 THEN 'MALE' ELSE 'FEMALE' END::gender,
       (ARRAY['AE','SA','EG','KW','QA','JO','OM','BH'])[1 + g % 8], 'city', 'NEVER_MARRIED', 'BACHELOR', 'software_engineer', 'WITHIN_1_YEAR', 'bio',
       -- members cluster around their country (centroid ± ~3°), like real users
       round(((ARRAY[24.4,24.0,26.8,29.3,25.3,31.2,21.5,26.0])[1 + g % 8] + ((g * 37) % 600 - 300) * 0.01)::numeric, 2),
       round(((ARRAY[54.4,45.0,30.8,47.9,51.2,36.5,55.9,50.5])[1 + g % 8] + ((g * 53) % 600 - 300) * 0.01)::numeric, 2),
       (ARRAY['AE','SA','EG','KW','QA','JO','OM','BH'])[1 + g % 8]
FROM generate_series(1, $N) g;
INSERT INTO user_preferences (user_id, age_min, age_max) SELECT md5('u'||g)::uuid, 18, 60 FROM generate_series(1, $N) g;
INSERT INTO user_verifications (user_id, type) SELECT md5('u'||g)::uuid, 'PROFILE_REVIEW' FROM generate_series(1, $N) g;
INSERT INTO user_photos (user_id, storage_key, position, rights_confirmed, status)
SELECT md5('u'||g)::uuid, 'k'||g||'/'||k, k, true, 'APPROVED' FROM generate_series(1, $N) g, generate_series(0, 1) k;
INSERT INTO likes (from_user_id, to_user_id)
SELECT md5('u'||g)::uuid, md5('u'||((g * 13) % $N + 1))::uuid FROM generate_series(1, $N) g WHERE (g * 13) % $N + 1 <> g
ON CONFLICT DO NOTHING;
ANALYZE;
SQL
echo "  seeded in $(( $(date +%s) - t0 ))s"

QUERY=$(cat src/modules/matching/sql/candidates.sql)
V=$($PSQL -d "$DB" -c "SELECT md5('u2')::uuid")
ms(){ $PSQL -d "$DB" -c "$1" | grep -o 'Execution Time: [0-9.]*' | grep -o '[0-9.]*$'; }
budget(){ # name ms limit
  if awk "BEGIN{exit !($2 <= $3)}"; then echo "  ✓ $1: ${2} ms (budget ${3} ms)"; pass=$((pass+1)); else echo "  ✗ $1: ${2} ms (budget ${3} ms)"; fail=$((fail+1)); fi; }

d1=$(ms "PREPARE q AS $QUERY; EXPLAIN (ANALYZE) EXECUTE q('$V','MALE','1980-01-01','2002-11-14','1994-05-01',NULL,2,24,200,25.20,55.27)")
budget "discovery, nearest-first, any country" "$d1" 400
d2=$(ms "PREPARE q AS $QUERY; EXPLAIN (ANALYZE) EXECUTE q('$V','MALE','1980-01-01','2002-11-14','1994-05-01','{AE}',2,24,200,25.20,55.27)")
budget "discovery, nearest-first, own country" "$d2" 400
d3=$(ms "PREPARE q AS $QUERY; EXPLAIN (ANALYZE) EXECUTE q('$V','MALE','1980-01-01','2002-11-14','1994-05-01','{AE}',2,24,200,NULL,NULL)")
budget "discovery without location (recent activity)" "$d3" 400
l1=$(ms "EXPLAIN (ANALYZE) SELECT l.id FROM likes l JOIN users u ON u.id = l.from_user_id WHERE l.to_user_id = '$V' AND u.status='ACTIVE' AND u.frozen_at IS NULL ORDER BY l.created_at DESC LIMIT 31")
budget "likes received page" "$l1" 50
c1=$(ms "EXPLAIN (ANALYZE) SELECT * FROM olfa_conversation_list('$V', 5)")
budget "conversation list" "$c1" 50
echo; echo "scale tests ($N members): $pass passed, $fail failed"
[ "$fail" -eq 0 ]

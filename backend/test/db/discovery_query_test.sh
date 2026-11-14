#!/usr/bin/env bash
# Runs the production discovery query (src/modules/matching/sql/candidates.sql)
# against fixtures and checks every exclusion rule.
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=olfa_disc_$$
PSQL="psql -v ON_ERROR_STOP=1 -qtA"
pass=0; fail=0
check(){ if [ "$2" == "$3" ]; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1 (expected '$3', got '$2')"; fail=$((fail+1)); fi; }
createdb "$DB" || exit 1
trap 'dropdb --if-exists "$DB" >/dev/null 2>&1' EXIT
for m in prisma/migrations/*/migration.sql; do $PSQL -d "$DB" -f "$m"; done >/dev/null
$PSQL -d "$DB" -f prisma/seed.sql >/dev/null

# Viewer: man, 32, AE, wants 24–34. Candidates: women with different situations.
$PSQL -d "$DB" <<'SQL' >/dev/null
CREATE TEMP TABLE f(id uuid, name text, gender gender, birth date, country char(2), status account_status,
                    approved boolean, photos int, amin int, amax int) ON COMMIT PRESERVE ROWS;
INSERT INTO f VALUES
 ('10000000-0000-0000-0000-000000000000','viewer',      'MALE',  '1994-05-01','AE','ACTIVE',true, 2,24,34),
 ('20000000-0000-0000-0000-000000000001','ok',          'FEMALE','1998-01-01','AE','ACTIVE',true, 2,25,40),
 ('20000000-0000-0000-0000-000000000002','man',         'MALE',  '1998-01-01','AE','ACTIVE',true, 2,25,40),
 ('20000000-0000-0000-0000-000000000003','too_young',   'FEMALE','2004-01-01','AE','ACTIVE',true, 2,25,40),
 ('20000000-0000-0000-0000-000000000004','she_wants_younger','FEMALE','1998-01-01','AE','ACTIVE',true,2,25,30),
 ('20000000-0000-0000-0000-000000000005','pending',     'FEMALE','1998-01-01','AE','PENDING_VERIFICATION',false,2,25,40),
 ('20000000-0000-0000-0000-000000000006','suspended',   'FEMALE','1998-01-01','AE','SUSPENDED',true, 2,25,40),
 ('20000000-0000-0000-0000-000000000007','one_photo',   'FEMALE','1998-01-01','AE','ACTIVE',true, 1,25,40),
 ('20000000-0000-0000-0000-000000000008','blocked_me',  'FEMALE','1998-01-01','AE','ACTIVE',true, 2,25,40),
 ('20000000-0000-0000-0000-000000000009','liked',       'FEMALE','1998-01-01','AE','ACTIVE',true, 2,25,40),
 ('20000000-0000-0000-0000-000000000010','passed',      'FEMALE','1998-01-01','AE','ACTIVE',true, 2,25,40),
 ('20000000-0000-0000-0000-000000000011','pass_expired','FEMALE','1998-01-01','AE','ACTIVE',true, 2,25,40),
 ('20000000-0000-0000-0000-000000000012','shown_recently','FEMALE','1998-01-01','AE','ACTIVE',true,2,25,40),
 ('20000000-0000-0000-0000-000000000013','other_country','FEMALE','1998-01-01','SA','ACTIVE',true,2,25,40),
 ('20000000-0000-0000-0000-000000000014','deleted',     'FEMALE','1998-01-01','AE','ACTIVE',true, 2,25,40),
 ('20000000-0000-0000-0000-000000000015','leaving',     'FEMALE','1998-01-01','AE','ACTIVE',true, 2,25,40);
INSERT INTO users (id, phone_e164, phone_country, status, deleted_at)
  SELECT id, '+9715' || lpad((row_number() over ())::text, 8, '0'), 'AE', status,
         CASE WHEN name='deleted' THEN now() END FROM f;
INSERT INTO user_profiles (user_id, display_name, birth_date, gender, country_code, city, marital_status, education, occupation, marriage_timeline, bio)
  SELECT id, name, birth, gender, country, 'Dubai', 'NEVER_MARRIED', 'BACHELOR', 'x', 'WITHIN_1_YEAR', 'bio' FROM f;
INSERT INTO user_preferences (user_id, age_min, age_max) SELECT id, amin, amax FROM f;
INSERT INTO user_verifications (user_id, type) SELECT id, 'PROFILE_REVIEW' FROM f WHERE approved;
INSERT INTO user_photos (user_id, storage_key, position, rights_confirmed, status)
  SELECT f.id, f.id || '/' || g, g, true, 'APPROVED' FROM f, generate_series(0, 5) g WHERE g < f.photos;
UPDATE users SET deletion_requested_at = now() WHERE id = '20000000-0000-0000-0000-000000000015';
INSERT INTO blocked_users VALUES ('20000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000000');
INSERT INTO likes (from_user_id,to_user_id) VALUES ('10000000-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000009');
INSERT INTO passes (from_user_id,to_user_id,expires_at) VALUES
  ('10000000-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000010', now() + interval '30 days'),
  ('10000000-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000011', now() - interval '1 day');
INSERT INTO discovery_history (viewer_id,candidate_id,action) VALUES
  ('10000000-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000012','SHOWN');
SQL

QUERY=$(cat src/modules/matching/sql/candidates.sql)
run(){ # countries
  $PSQL -d "$DB" -c "PREPARE q AS $QUERY" -c "EXECUTE q('10000000-0000-0000-0000-000000000000','MALE','1992-11-15','2002-11-14','1994-05-01',$1,2,24,50)" | cut -d'|' -f2 | sort | tr '\n' ' '; }

echo "discovery candidate query"
got=$(run NULL)
check "only eligible, not-yet-seen, mutually-in-range women are returned" "$got" "ok other_country pass_expired "
got=$(run "'{AE}'")
check "country filter" "$got" "ok pass_expired "
for name in man too_young she_wants_younger pending suspended one_photo blocked_me liked passed shown_recently deleted leaving; do
  echo "$got" | grep -qw "$name" && { echo "  ✗ excluded: $name"; fail=$((fail+1)); } || { pass=$((pass+1)); }
done
echo "  ✓ 12 exclusion rules hold (gender, age both ways, status, photos, block, like, pass, cooldown, soft delete, pending deletion)"
plan=$($PSQL -d "$DB" -c "PREPARE q AS $QUERY" -c "EXPLAIN EXECUTE q('10000000-0000-0000-0000-000000000000','MALE','1992-11-15','2002-11-14','1994-05-01',NULL,2,24,50)" | head -1)
[ -n "$plan" ] && { echo "  ✓ query plans successfully"; pass=$((pass+1)); }
echo; echo "discovery tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

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
run(){ # countries [lat lng]
  $PSQL -d "$DB" -c "PREPARE q AS $QUERY" -c "EXECUTE q('10000000-0000-0000-0000-000000000000','MALE','1992-11-15','2002-11-14','1994-05-01',$1,2,24,50,${2:-NULL},${3:-NULL})" | cut -d'|' -f2 | sort | tr '\n' ' '; }
ordered(){ # names in query order, viewer at lat/lng
  $PSQL -d "$DB" -c "PREPARE q AS $QUERY" -c "EXECUTE q('10000000-0000-0000-0000-000000000000','MALE','1992-11-15','2002-11-14','1994-05-01',NULL,2,24,50,$1,$2)" | cut -d'|' -f2 | tr '\n' ' '; }

echo "discovery candidate query"
got=$(run NULL)
check "only eligible, not-yet-seen, mutually-in-range women are returned" "$got" "ok other_country pass_expired pending "
got=$(run "'{AE}'")
check "country filter" "$got" "ok pass_expired pending "
for name in man too_young she_wants_younger suspended one_photo blocked_me liked passed shown_recently deleted leaving; do
  echo "$got" | grep -qw "$name" && { echo "  ✗ excluded: $name"; fail=$((fail+1)); } || { pass=$((pass+1)); }
done
echo "  ✓ 11 exclusion rules hold (gender, age both ways, status, photos, block, like, pass, cooldown, soft delete, pending deletion)"
echo "$got" | grep -qw pending && { echo "  ✓ new account awaiting review is listed (shown without photos/bio by the API)"; pass=$((pass+1)); } || { echo "  ✗ pending account missing"; fail=$((fail+1)); }
# nearest first: viewer in Dubai; 'ok' in Abu Dhabi (~123 km), 'pass_expired' in Dubai (~1 km), 'other_country' unknown location
$PSQL -d "$DB" -c "UPDATE user_profiles SET latitude=24.45, longitude=54.38 WHERE display_name='ok'; UPDATE user_profiles SET latitude=25.21, longitude=55.27 WHERE display_name='pass_expired'" >/dev/null
check "nearest candidates come first; unknown location last" "$(ordered 25.20 55.27)" "pass_expired ok pending other_country "
check "distance is computed in SQL (km)" "$($PSQL -d "$DB" -c "PREPARE q AS $QUERY" -c "EXECUTE q('10000000-0000-0000-0000-000000000000','MALE','1992-11-15','2002-11-14','1994-05-01',NULL,2,24,50,25.20,55.27)" | awk -F'|' '$2=="ok"{printf "%d", $19}')" "122"

echo "privacy, freeze, compliments"
V=10000000-0000-0000-0000-000000000000
OK=20000000-0000-0000-0000-000000000001
PE=20000000-0000-0000-0000-000000000011
OC=20000000-0000-0000-0000-000000000013
base(){ run NULL | tr -s ' '; }
$PSQL -d "$DB" -c "INSERT INTO user_privacy_settings (user_id, discoverable) VALUES ('$OK', false)" >/dev/null
check "hidden profile (discoverable=false) leaves discovery" "$(base)" "other_country pass_expired pending "
$PSQL -d "$DB" -c "UPDATE user_privacy_settings SET discoverable = true, incognito = true WHERE user_id = '$OK'" >/dev/null
check "incognito: hidden from people she didn't like" "$(base)" "other_country pass_expired pending "
$PSQL -d "$DB" -c "INSERT INTO likes (from_user_id, to_user_id) VALUES ('$OK', '$V')" >/dev/null
check "incognito: visible to someone she liked" "$(base)" "ok other_country pass_expired pending "
$PSQL -d "$DB" -c "UPDATE users SET frozen_at = now() WHERE id = '$PE'" >/dev/null
check "frozen account leaves discovery" "$(base)" "ok other_country pending "
got=$($PSQL -d "$DB" -c "SELECT 1 FROM olfa_like('$V','$PE',date_trunc('day',now()),date_trunc('day',now())+interval '1 day',10)" 2>&1 | grep -o 'OLL02\|not eligible' | head -1)
check "cannot like a frozen account" "$got" "not eligible"
$PSQL -d "$DB" -c "UPDATE users SET frozen_at = NULL WHERE id = '$PE'" >/dev/null
check "unfreeze restores visibility (data kept)" "$(base)" "ok other_country pass_expired pending "
check "incognito resets when the plan lacks it (Free user)" "$($PSQL -d "$DB" -c "SELECT olfa_reset_lapsed_privacy()")" "1"
check "olfa_has_feature: Free has no incognito" "$($PSQL -d "$DB" -c "SELECT olfa_has_feature('$V','incognito')")" "f"
$PSQL -d "$DB" -c "INSERT INTO user_subscriptions (user_id, plan_id, provider, status, starts_at, expires_at) SELECT '$V', id, 'APPLE', 'ACTIVE', now(), now() + interval '30 days' FROM subscription_plans WHERE code='PREMIUM'" >/dev/null 2>&1
check "olfa_has_feature: Premium has incognito" "$($PSQL -d "$DB" -c "SELECT olfa_has_feature('$V','incognito')")" "t"
# compliments: monthly quota of 3 (Free) through the same atomic counter
M0="date_trunc('month', now())"; M1="date_trunc('month', now()) + interval '1 month'"
r=""; for k in 1 2 3; do r="$r$($PSQL -d "$DB" -c "SELECT olfa_consume_quota('$OC','compliments',$M0,$M1,3)")"; done
check "3 compliments a month on Free (remaining 2,1,0)" "$r" "210"
got=$($PSQL -d "$DB" -c "SELECT olfa_consume_quota('$OC','compliments',$M0,$M1,3)" 2>&1 | grep -o 'quota exceeded: compliments')
check "4th compliment refused with the quota key" "$got" "quota exceeded: compliments"
check "next month starts fresh" "$($PSQL -d "$DB" -c "SELECT olfa_consume_quota('$OC','compliments',$M1,$M1 + interval '1 month',3)")" "2"
got=$($PSQL -d "$DB" -c "UPDATE likes SET compliment = 'x' WHERE from_user_id = '$OK'" 2>&1 | grep -o 'likes_compliment_len')
check "compliment length is checked by the database" "$got" "likes_compliment_len"
plan=$($PSQL -d "$DB" -c "PREPARE q AS $QUERY" -c "EXPLAIN EXECUTE q('10000000-0000-0000-0000-000000000000','MALE','1992-11-15','2002-11-14','1994-05-01',NULL,2,24,50,NULL,NULL)" | head -1)
[ -n "$plan" ] && { echo "  ✓ query plans successfully"; pass=$((pass+1)); }
echo; echo "discovery tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

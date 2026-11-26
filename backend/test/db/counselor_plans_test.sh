#!/usr/bin/env bash
# Counselor plans: audience guard, counselor feature guard, effective boost,
# profile views.   PGHOST=/tmp PGUSER=postgres bash test/db/counselor_plans_test.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=olfa_cp_$$
PSQL="psql -v ON_ERROR_STOP=1 -qtA"
pass=0; fail=0
ok()  { echo "  ✓ $1"; pass=$((pass+1)); }
bad() { echo "  ✗ $1"; fail=$((fail+1)); }
check(){ if [ "$2" == "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }
expect_error(){ out=$($PSQL -d "$DB" -c "\\set VERBOSITY verbose" -c "$3" 2>&1); if echo "$out" | grep -q "$2"; then ok "$1"; else bad "$1 (expected $2, got: ${out:0:180})"; fi; }
q(){ $PSQL -d "$DB" -c "$1" 2>&1; }
createdb "$DB" || exit 1
trap 'dropdb --if-exists "$DB" >/dev/null 2>&1' EXIT
for m in prisma/migrations/*/migration.sql; do $PSQL -d "$DB" -f "$m" >/dev/null || { echo "migration $m failed"; exit 1; }; done
$PSQL -d "$DB" -f prisma/seed.sql >/dev/null

K=00000000-0000-0000-0000-0000000000a1; K2=00000000-0000-0000-0000-0000000000a2; M=00000000-0000-0000-0000-0000000000d1
$PSQL -d "$DB" <<SQL >/dev/null
INSERT INTO users (id, phone_e164, phone_country, status, account_type) VALUES
 ('$K','+971500000201','AE','ACTIVE','FAMILY_COUNSELOR'), ('$K2','+971500000202','AE','ACTIVE','PSYCHOLOGIST'), ('$M','+971500000203','AE','ACTIVE','MEMBER');
INSERT INTO counselor_profiles (user_id, kind, status, display_name, headline, bio, years_experience, license_number, license_authority, license_country, credential_keys, languages, services) VALUES
 ('$K','FAMILY_COUNSELOR','APPROVED','Dr. Huda','h','b',8,'L1','A','AE','{c}','{ar}','{MARITAL}'),
 ('$K2','PSYCHOLOGIST','APPROVED','Dr. Omar','h','b',5,'L2','A','AE','{c}','{ar}','{MARITAL}');
SQL
plan(){ q "SELECT id FROM subscription_plans WHERE code='$1'"; }

echo "plans"
check "two counselor plans, professional audience" "$(q "SELECT string_agg(code::text||':'||audience, ',' ORDER BY sort_order) FROM subscription_plans WHERE code::text LIKE 'PRO%'")" "PRO_PLUS:PROFESSIONAL,PRO_PREMIUM:PROFESSIONAL"
check "member plans stay member" "$(q "SELECT count(*) FROM subscription_plans WHERE audience='MEMBER'")" "3"
expect_error "a PRO_ code can't be a member plan" "subscription_plans_audience_ck" "UPDATE subscription_plans SET audience='MEMBER' WHERE code='PRO_PLUS'"
check "store products for counselor plans" "$(q "SELECT count(*) FROM plan_products pp JOIN subscription_plans p ON p.id=pp.plan_id WHERE p.code::text LIKE 'PRO%'")" "4"
check "counselor plans never show ads" "$(q "SELECT string_agg(value::text, ',') FROM feature_entitlements fe JOIN subscription_plans p ON p.id=fe.plan_id WHERE p.code::text LIKE 'PRO%' AND feature_key='show_ads'")" "false,false"
check "boost values" "$(q "SELECT string_agg(p.code::text||'='||value::text, ',' ORDER BY p.sort_order) FROM feature_entitlements fe JOIN subscription_plans p ON p.id=fe.plan_id WHERE feature_key='directory_boost'")" "FREE=0,PRO_PLUS=1,PRO_PREMIUM=2"

echo "audience guard"
expect_error "a member can't hold a counselor plan" "P0076" "INSERT INTO user_subscriptions (user_id, plan_id, provider, status, starts_at, expires_at) VALUES ('$M','$(plan PRO_PLUS)','APPLE','ACTIVE',now(),now()+interval '30 days')"
expect_error "a counselor can't hold a member plan" "P0076" "INSERT INTO user_subscriptions (user_id, plan_id, provider, status, starts_at, expires_at) VALUES ('$K','$(plan PLUS)','APPLE','ACTIVE',now(),now()+interval '30 days')"
q "INSERT INTO user_subscriptions (user_id, plan_id, provider, status, starts_at, expires_at, original_transaction_id) VALUES ('$K','$(plan PRO_PREMIUM)','APPLE','ACTIVE',now(),now()+interval '30 days','t1')" >/dev/null && ok "a counselor can hold a counselor plan" || bad "counselor plan insert"
expect_error "switching it to a member plan is refused" "P0076" "UPDATE user_subscriptions SET plan_id='$(plan PREMIUM)' WHERE original_transaction_id='t1'"

echo "feature guard"
expect_error "no boost on the free plan" "P0077" "UPDATE feature_entitlements SET value='1' WHERE feature_key='directory_boost' AND plan_id='$(plan FREE)'"
expect_error "no counselor features on member plans" "P0077" "INSERT INTO feature_entitlements (plan_id, feature_key, value) VALUES ('$(plan PLUS)','featured_badge','true')"
expect_error "boost is 0-2" "P0077" "UPDATE feature_entitlements SET value='3' WHERE feature_key='directory_boost' AND plan_id='$(plan PRO_PLUS)'"
expect_error "badge is a boolean" "P0077" "UPDATE feature_entitlements SET value='1' WHERE feature_key='featured_badge' AND plan_id='$(plan PRO_PLUS)'"
expect_error "still no ads on a counselor plan" "P0060" "UPDATE feature_entitlements SET value='true' WHERE feature_key='show_ads' AND plan_id='$(plan PRO_PLUS)'"
q "UPDATE feature_entitlements SET value='true' WHERE feature_key='featured_badge' AND plan_id='$(plan PRO_PLUS)'" >/dev/null && ok "admins can tune counselor plans" || bad "admin edit"
q "UPDATE feature_entitlements SET value='false' WHERE feature_key='featured_badge' AND plan_id='$(plan PRO_PLUS)'" >/dev/null

echo "effective boost"
check "premium counselor: boost 2" "$(q "SELECT olfa_counselor_boost('$K')")" "2"
check "free counselor: boost 0" "$(q "SELECT olfa_counselor_boost('$K2')")" "0"
check "featured only with the badge" "$(q "SELECT olfa_has_feature('$K','featured_badge')::text || ',' || olfa_has_feature('$K2','featured_badge')::text")" "true,false"
q "UPDATE user_subscriptions SET starts_at = now() - interval '31 days', expires_at = now() - interval '1 minute' WHERE original_transaction_id='t1'" >/dev/null
check "lapsed plan: boost back to 0" "$(q "SELECT olfa_counselor_boost('$K')")" "0"

echo "profile views"
q "INSERT INTO counselor_profile_views (counselor_id, viewer_id) VALUES ('$K','$M') ON CONFLICT DO NOTHING; INSERT INTO counselor_profile_views (counselor_id, viewer_id) VALUES ('$K','$M') ON CONFLICT DO NOTHING" >/dev/null
check "one view per viewer per day" "$(q "SELECT count(*) FROM counselor_profile_views WHERE counselor_id='$K'")" "1"
expect_error "a counselor's own visits don't count" "counselor_profile_views_check" "INSERT INTO counselor_profile_views (counselor_id, viewer_id) VALUES ('$K','$K')"
q "DELETE FROM users WHERE id='$M'" >/dev/null
check "views go with the viewer's account" "$(q "SELECT count(*) FROM counselor_profile_views")" "0"

echo; echo "$pass passed, $fail failed"; [ $fail -eq 0 ]

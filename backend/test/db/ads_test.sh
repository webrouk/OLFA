#!/usr/bin/env bash
# Discovery native ads: Free plan only (seed + trigger), settings row.
#   PGHOST=/tmp PGUSER=postgres bash test/db/ads_test.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=olfa_ads_$$
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
SA="SELECT fe.value FROM feature_entitlements fe JOIN subscription_plans p ON p.id = fe.plan_id WHERE fe.feature_key = 'show_ads' AND p.code ="
PLAN="(SELECT id FROM subscription_plans WHERE code ="

echo "show_ads per plan"
check "Free shows ads" "$(q "$SA 'FREE'")" "true"
check "Plus never" "$(q "$SA 'PLUS'")" "false"
check "Premium never" "$(q "$SA 'PREMIUM'")" "false"
expect_error "paid plan cannot be switched on" "P0060" "UPDATE feature_entitlements SET value = 'true' WHERE feature_key = 'show_ads' AND plan_id = $PLAN 'PLUS')"
expect_error "paid plan cannot be inserted on" "P0060" "DELETE FROM feature_entitlements WHERE feature_key = 'show_ads' AND plan_id = $PLAN 'PREMIUM'); INSERT INTO feature_entitlements (plan_id, feature_key, value) VALUES ($PLAN 'PREMIUM'), 'show_ads', 'true')"
expect_error "value must be boolean" "P0060" "UPDATE feature_entitlements SET value = '1' WHERE feature_key = 'show_ads' AND plan_id = $PLAN 'FREE')"
q "UPDATE feature_entitlements SET value = 'false' WHERE feature_key = 'show_ads' AND plan_id = $PLAN 'FREE')" >/dev/null
check "Free can be switched off by the admin" "$(q "$SA 'FREE'")" "false"
check "other features untouched by the trigger" "$(q "UPDATE feature_entitlements SET value = '15' WHERE feature_key = 'daily_likes' AND plan_id = $PLAN 'PLUS') RETURNING value")" "15"

echo "settings"
check "ads are off until AdMob is configured" "$(q "SELECT value->>'enabled' FROM system_settings WHERE key = 'ads.discovery'")" "false"
check "no unit ids shipped" "$(q "SELECT value->'units'->>'android' || '|' || (value->'units'->>'ios') FROM system_settings WHERE key = 'ads.discovery'")" "|"

echo; echo "ads: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

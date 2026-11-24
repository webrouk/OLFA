#!/usr/bin/env bash
# Database tests against a real PostgreSQL: constraints, soft delete, quota and
# like/match atomicity under concurrency.
#   PGHOST=localhost PGPORT=5432 PGUSER=postgres bash test/db/run_db_tests.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=olfa_dbtest_$$
PSQL="psql -v ON_ERROR_STOP=1 -qtA"
pass=0; fail=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
check(){ if [ "$2" == "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }
expect_error(){ # name sqlstate sql
  out=$($PSQL -d "$DB" -c "\\set VERBOSITY verbose" -c "$3" 2>&1)
  if echo "$out" | grep -q "$2"; then ok "$1"; else bad "$1 (expected $2, got: ${out:0:160})"; fi; }

createdb "$DB" || exit 1
trap 'dropdb --if-exists "$DB" >/dev/null 2>&1' EXIT
for m in prisma/migrations/*/migration.sql; do $PSQL -d "$DB" -f "$m"; done >/dev/null || { echo "migration failed"; exit 1; }
echo "migration applied: $($PSQL -d "$DB" -c "select count(*) from information_schema.tables where table_schema='public'") tables"

# ── fixtures ──
$PSQL -d "$DB" <<'SQL' >/dev/null
INSERT INTO users (id, phone_e164, phone_country, status) VALUES
 ('00000000-0000-0000-0000-00000000000a', '+971500000001', 'AE', 'ACTIVE'),
 ('00000000-0000-0000-0000-00000000000b', '+971500000002', 'AE', 'ACTIVE'),
 ('00000000-0000-0000-0000-00000000000c', '+971500000003', 'AE', 'PENDING_VERIFICATION'),
 ('00000000-0000-0000-0000-00000000000d', '+971500000004', 'AE', 'ACTIVE');
-- 40 active users for pair races
INSERT INTO users (phone_e164, phone_country, status)
SELECT '+97155' || lpad(g::text, 7, '0'), 'AE', 'ACTIVE' FROM generate_series(1, 40) g;
-- marriage members (account type chosen at sign-up)
UPDATE users SET account_type = 'MEMBER';
SQL

echo "constraints"
expect_error "phone must be E.164"            23514 "INSERT INTO users (phone_e164, phone_country) VALUES ('0501234567','AE')"
expect_error "one live account per phone"     23505 "INSERT INTO users (phone_e164, phone_country) VALUES ('+971500000001','AE')"
$PSQL -d "$DB" -c "UPDATE users SET deleted_at = now(), status='DELETED' WHERE id='00000000-0000-0000-0000-00000000000d'" >/dev/null
r=$($PSQL -d "$DB" -c "INSERT INTO users (phone_e164, phone_country) VALUES ('+971500000004','AE') RETURNING 'ok'" 2>&1)
check "soft-deleted account frees the phone number" "$r" "ok"
expect_error "cannot like yourself"           23514 "INSERT INTO likes (from_user_id,to_user_id) VALUES ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000a')"
expect_error "match pair must be ordered"     23514 "INSERT INTO matches (user_a_id,user_b_id) VALUES ('00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a')"
expect_error "photo rights must be confirmed" 23514 "INSERT INTO user_photos (user_id,storage_key,position,rights_confirmed) VALUES ('00000000-0000-0000-0000-00000000000a','k1',0,false)"
expect_error "photo max 10 MB"                23514 "INSERT INTO user_photos (user_id,storage_key,position,rights_confirmed,bytes) VALUES ('00000000-0000-0000-0000-00000000000a','k2',0,true,20000000)"
expect_error "preferences age_min >= 18"      23514 "INSERT INTO user_preferences (user_id,age_min,age_max) VALUES ('00000000-0000-0000-0000-00000000000a',17,30)"
$PSQL -d "$DB" -c "INSERT INTO verification_requests (user_id,type) VALUES ('00000000-0000-0000-0000-00000000000a','PROFILE_REVIEW')" >/dev/null
expect_error "one open verification request per type" 23505 "INSERT INTO verification_requests (user_id,type) VALUES ('00000000-0000-0000-0000-00000000000a','PROFILE_REVIEW')"
$PSQL -d "$DB" -c "WITH m AS (INSERT INTO matches(user_a_id,user_b_id) VALUES ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b') RETURNING *) INSERT INTO conversations (match_id,started_by) SELECT id, user_a_id FROM m" >/dev/null
expect_error "empty message body rejected"    23514 "INSERT INTO messages (conversation_id,sender_id,client_message_id,body) SELECT id, started_by, gen_random_uuid(), '   ' FROM conversations LIMIT 1"
CID=$($PSQL -d "$DB" -c "SELECT id FROM conversations LIMIT 1"); CM=$($PSQL -d "$DB" -c "SELECT gen_random_uuid()")
$PSQL -d "$DB" -c "INSERT INTO messages (conversation_id,sender_id,client_message_id,body) VALUES ('$CID','00000000-0000-0000-0000-00000000000a','$CM','hi')" >/dev/null
expect_error "same client_message_id cannot be stored twice" 23505 "INSERT INTO messages (conversation_id,sender_id,client_message_id,body) VALUES ('$CID','00000000-0000-0000-0000-00000000000a','$CM','hi')"
$PSQL -d "$DB" -c "DELETE FROM matches; DELETE FROM conversations;" >/dev/null 2>&1

echo "olfa_like rules"
P="now() - interval '1 hour', now() + interval '23 hours'"
expect_error "pending account cannot like"    OLL02 "SELECT * FROM olfa_like('00000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-00000000000a',$P,10)"
$PSQL -d "$DB" -c "INSERT INTO blocked_users VALUES ('00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a')" >/dev/null
expect_error "blocked pair cannot like"       OLL03 "SELECT * FROM olfa_like('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b',$P,10)"
$PSQL -d "$DB" -c "DELETE FROM blocked_users" >/dev/null
r=$($PSQL -d "$DB" -c "SELECT (match_id IS NULL)::text || ',' || likes_remaining FROM olfa_like('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b',$P,10)")
check "first like: no match, 9 likes left" "$r" "true,9"
expect_error "duplicate like rejected"        OLL01 "SELECT * FROM olfa_like('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b',$P,10)"
r=$($PSQL -d "$DB" -c "SELECT used FROM usage_counters WHERE user_id='00000000-0000-0000-0000-00000000000a'")
check "duplicate like does not consume quota" "$r" "1"
r=$($PSQL -d "$DB" -c "SELECT (match_id IS NOT NULL)::text FROM olfa_like('00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a',$P,10)")
check "reverse like creates the match" "$r" "true"
r=$($PSQL -d "$DB" -c "SELECT count(*) FROM usage_events WHERE counter_key='likes'")
check "consumption ledger records each like" "$r" "2"
expect_error "zero limit refuses immediately" OLQ01 "SELECT olfa_consume_quota('00000000-0000-0000-0000-00000000000a','messages',now(),now()+interval '1 day',0)"

echo "concurrency"
# 1) 30 parallel consumes against a limit of 10 → exactly 10 succeed.
U=$($PSQL -d "$DB" -c "SELECT id FROM users WHERE phone_e164='+971550000001'")
PS="'2026-11-14T00:00:00Z','2026-11-15T00:00:00Z'"
for i in $(seq 1 30); do
  ($PSQL -d "$DB" -c "SELECT olfa_consume_quota('$U','likes',$PS,10)" >/dev/null 2>&1 && echo ok) &
done > /tmp/olfa_q_$$ ; wait
check "30 concurrent consumes, limit 10 → 10 succeed" "$(grep -c ok /tmp/olfa_q_$$)" "10"
check "counter never exceeds the limit" "$($PSQL -d "$DB" -c "SELECT used FROM usage_counters WHERE user_id='$U' AND counter_key='likes'")" "10"

# 2) 10 parallel identical likes → one like, one quota unit.
A=$($PSQL -d "$DB" -c "SELECT id FROM users WHERE phone_e164='+971550000002'")
B=$($PSQL -d "$DB" -c "SELECT id FROM users WHERE phone_e164='+971550000003'")
for i in $(seq 1 10); do ($PSQL -d "$DB" -c "SELECT * FROM olfa_like('$A','$B',$PS,100)" >/dev/null 2>&1 && echo ok) & done > /tmp/olfa_d_$$; wait
check "10 concurrent duplicate likes → 1 succeeds" "$(grep -c ok /tmp/olfa_d_$$)" "1"
check "…and only 1 quota unit consumed" "$($PSQL -d "$DB" -c "SELECT used FROM usage_counters WHERE user_id='$A'")" "1"

# 3) 15 pairs like each other at the same instant → exactly one match per pair.
mapfile -t IDS < <($PSQL -d "$DB" -c "SELECT id FROM users WHERE phone_e164 > '+971550000010' ORDER BY phone_e164 LIMIT 30")
for k in $(seq 0 2 28); do
  X=${IDS[$k]}; Y=${IDS[$((k+1))]}
  $PSQL -d "$DB" -c "SELECT * FROM olfa_like('$X','$Y',$PS,100)" >/dev/null 2>&1 &
  $PSQL -d "$DB" -c "SELECT * FROM olfa_like('$Y','$X',$PS,100)" >/dev/null 2>&1 &
done; wait
check "15 simultaneous mutual pairs → 15 matches" "$($PSQL -d "$DB" -c "SELECT count(*) FROM matches m JOIN users u ON u.id=m.user_a_id WHERE u.phone_e164 > '+971550000010'")" "15"
check "no duplicate matches"   "$($PSQL -d "$DB" -c "SELECT count(*) FROM (SELECT user_a_id,user_b_id FROM matches GROUP BY 1,2 HAVING count(*)>1) d")" "0"

rm -f /tmp/olfa_*_$$
echo; echo "db tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

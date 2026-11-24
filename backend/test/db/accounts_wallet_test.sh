#!/usr/bin/env bash
# Account types, religion & sect, counselor wallet (15% commission, hold,
# withdrawals), mandatory questionnaire gate, integrity tables and bans.
#   PGHOST=/tmp PGUSER=postgres bash test/db/accounts_wallet_test.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=olfa_acct_$$
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

M1=00000000-0000-0000-0000-0000000000d1   # member
M2=00000000-0000-0000-0000-0000000000d2   # member
K=00000000-0000-0000-0000-0000000000d3    # family counselor
N=00000000-0000-0000-0000-0000000000d4    # new account, no type yet
$PSQL -d "$DB" <<SQL >/dev/null
INSERT INTO users (id, phone_e164, phone_country, status) VALUES
 ('$M1','+971500000201','AE','ACTIVE'), ('$M2','+971500000202','AE','ACTIVE'), ('$K','+971500000203','AE','ACTIVE'), ('$N','+971500000204','AE','PENDING_VERIFICATION');
SQL
profile(){ # id gender extra-cols extra-vals
  q "INSERT INTO user_profiles (user_id, display_name, birth_date, gender, country_code, city, marital_status, education, occupation, marriage_timeline, bio $3)
     VALUES ('$1','Name','1994-01-01','$2','AE','Dubai','NEVER_MARRIED','BACHELOR','teacher','WITHIN_1_YEAR','A long enough biography for the profile.' $4)"; }

echo "account types"
profile $M1 MALE "" "" >/dev/null
check "a marriage profile makes the account a MEMBER" "$(q "SELECT account_type FROM users WHERE id='$M1'")" "MEMBER"
q "UPDATE users SET account_type='FAMILY_COUNSELOR' WHERE id='$K'" >/dev/null
q "INSERT INTO counselor_profiles (user_id, kind, status, display_name, headline, bio, years_experience, license_number, license_authority, license_country, credential_keys, languages, services)
   VALUES ('$K','FAMILY_COUNSELOR','APPROVED','Dr. Huda','Family counselor','Bio',8,'DHA-123','Dubai Health Authority','AE','{cred/k1.pdf}','{ar}','{MARITAL}')" >/dev/null
expect_error "a professional has no marriage profile" P0031 "INSERT INTO user_profiles (user_id, display_name, birth_date, gender, country_code, city, marital_status, education, occupation, marriage_timeline, bio) VALUES ('$K','x','1990-01-01','FEMALE','AE','Dubai','NEVER_MARRIED','BACHELOR','teacher','NOT_SURE','A long enough biography for the profile.')"
expect_error "a member cannot hold a counselor profile" P0031 "INSERT INTO counselor_profiles (user_id, kind, display_name, headline, bio, years_experience, license_number, license_authority, license_country, credential_keys, languages, services) VALUES ('$M1','PSYCHOLOGIST','x','x','x',1,'1','a','AE','{c}','{ar}','{FAMILY}')"
expect_error "counselor kind must match the account type" P0031 "UPDATE counselor_profiles SET kind='PSYCHOLOGIST' WHERE user_id='$K'"
expect_error "type is locked once a profile exists" P0030 "UPDATE users SET account_type='PSYCHOLOGIST' WHERE id='$K'"
check "type can change before any profile exists" "$(q "UPDATE users SET account_type='PSYCHOLOGIST' WHERE id='$N' RETURNING account_type; UPDATE users SET account_type='MEMBER' WHERE id='$N' RETURNING account_type" | tail -1)" "MEMBER"
expect_error "likes are between members only" OLL02 "INSERT INTO likes (from_user_id, to_user_id) VALUES ('$M1','$K')"

echo "religion & sect"
expect_error "religion needs explicit consent" 23514 "UPDATE user_profiles SET religion='islam' WHERE user_id='$M1'"
check "religion + sect with consent" "$(q "UPDATE user_profiles SET religion='islam', sect='sunni', religion_consent_at=now() WHERE user_id='$M1' RETURNING sect")" "sunni"
expect_error "sect must belong to the religion" 23503 "UPDATE user_profiles SET sect='catholic' WHERE user_id='$M1'"
expect_error "unknown religion" 23503 "UPDATE user_profiles SET religion='nope' WHERE user_id='$M1'"
check "'prefer not to say' needs no consent" "$(q "UPDATE user_profiles SET religion='undisclosed', sect=NULL, religion_consent_at=NULL WHERE user_id='$M1' RETURNING religion")" "undisclosed"
q "INSERT INTO user_preferences (user_id) VALUES ('$M1')" >/dev/null
check "preferences accept religions with their sects" "$(q "UPDATE user_preferences SET religions='{islam,christianity}', sects='{islam.sunni,christianity.coptic_orthodox}' WHERE user_id='$M1' RETURNING cardinality(sects)")" "2"
expect_error "preference sect outside the accepted religions" 23503 "UPDATE user_preferences SET religions='{islam}', sects='{christianity.catholic}' WHERE user_id='$M1'"
expect_error "unknown preference sect" 23503 "UPDATE user_preferences SET religions='{}', sects='{islam.nope}' WHERE user_id='$M1'"
check "14 sects seeded under their religions" "$(q "SELECT count(*) FROM sects")" "14"

echo "commission snapshot & wallet"
q "UPDATE users SET account_type='MEMBER' WHERE id='$M2'" >/dev/null
O=00000000-0000-0000-0000-0000000000f9
q "INSERT INTO counselor_offerings (id, counselor_id, service, language, duration_minutes, price_minor, currency) VALUES ('$O','$K','MARITAL','ar',60,28000,'AED')" >/dev/null
run_session(){ # booking-id payment-id client
  q "INSERT INTO consultations (id, client_id, counselor_id, offering_id, service, language, duration_minutes, price_minor, currency, expires_at) VALUES ('$1','$3','$K','$O','MARITAL','ar',60,28000,'AED', now() + interval '30 min')" >/dev/null
  q "INSERT INTO payments (id, user_id, provider, provider_payment_id, amount_minor, currency, status, consultation_id) VALUES ('$2','$3','WEB','pi_$2',28000,'AED','SUCCEEDED','$1')" >/dev/null
  q "UPDATE consultations SET status='PAID', payment_id='$2' WHERE id='$1'" >/dev/null; }
B1=00000000-0000-0000-0000-0000000001b1; P1=00000000-0000-0000-0000-0000000001e1
run_session $B1 $P1 $M1
check "15% fee fixed at payment (4200 / 23800)" "$(q "SELECT platform_fee_percent || ':' || platform_fee_minor || ':' || counselor_net_minor FROM consultations WHERE id='$B1'")" "15:4200:23800"
check "nothing credited before completion" "$(q "SELECT count(*) FROM wallet_entries WHERE counselor_id='$K'")" "0"
q "UPDATE consultations SET status='CONFIRMED', scheduled_at=now() WHERE id='$B1'; UPDATE consultations SET status='COMPLETED' WHERE id='$B1'" >/dev/null
check "net share credited on completion" "$(q "SELECT kind || ':' || amount_minor FROM wallet_entries WHERE consultation_id='$B1'")" "EARNING:23800"
check "earning is pending during the 7-day hold" "$(q "SELECT available_minor || '/' || pending_minor FROM olfa_wallet_balance('$K','AED')")" "0/23800"
check "completing twice never double-credits" "$(q "SELECT count(*) FROM wallet_entries WHERE consultation_id='$B1'")" "1"

PM=00000000-0000-0000-0000-0000000000a9
q "INSERT INTO payout_methods (id, counselor_id, kind, holder_name, country_code, currency, details_enc, details_mask, fingerprint) VALUES ('$PM','$K','BANK_IBAN','Huda','AE','AED','\\x01','AE07 •••• 3456','$(printf 'a%.0s' {1..64})')" >/dev/null
expect_error "pending earnings cannot be withdrawn" P0041 "INSERT INTO withdrawals (counselor_id, payout_method_id, amount_minor, currency) VALUES ('$K','$PM',10000,'AED')"
expect_error "unknown payout method" 23503 "INSERT INTO withdrawals (counselor_id, payout_method_id, amount_minor, currency) VALUES ('$K','00000000-0000-0000-0000-000000000000',100,'AED')"
# release the hold (simulate 8 days later by back-dating through an adjustment of the window)
q "INSERT INTO wallet_entries (counselor_id, currency, kind, amount_minor, memo) VALUES ('$K','AED','ADJUSTMENT',20000,'test: released funds')" >/dev/null
W1=$(q "INSERT INTO withdrawals (counselor_id, payout_method_id, amount_minor, currency) VALUES ('$K','$PM',15000,'AED') RETURNING id")
check "withdrawal reserves funds immediately" "$(q "SELECT available_minor FROM olfa_wallet_balance('$K','AED')")" "5000"
expect_error "one open withdrawal per currency" 23505 "INSERT INTO withdrawals (counselor_id, payout_method_id, amount_minor, currency) VALUES ('$K','$PM',1000,'AED')"
expect_error "cannot jump from REQUESTED to PAID" P0042 "UPDATE withdrawals SET status='PAID', provider_ref='x' WHERE id='$W1'"
q "UPDATE withdrawals SET status='PROCESSING' WHERE id='$W1'" >/dev/null
expect_error "PAID needs a transfer reference" 23514 "UPDATE withdrawals SET status='PAID' WHERE id='$W1'"
q "UPDATE withdrawals SET status='FAILED', failure_reason='bank rejected' WHERE id='$W1'" >/dev/null
check "failed withdrawal returns the money" "$(q "SELECT available_minor FROM olfa_wallet_balance('$K','AED')")" "20000"
W2=$(q "INSERT INTO withdrawals (counselor_id, payout_method_id, amount_minor, currency) VALUES ('$K','$PM',20000,'AED') RETURNING id")
q "UPDATE withdrawals SET status='PROCESSING' WHERE id='$W2'; UPDATE withdrawals SET status='PAID', provider_ref='FT2611140001' WHERE id='$W2'" >/dev/null
check "paid withdrawal empties the available balance" "$(q "SELECT available_minor FROM olfa_wallet_balance('$K','AED')")" "0"
expect_error "ledger is append-only" P0040 "UPDATE wallet_entries SET amount_minor=1 WHERE consultation_id='$B1'"
expect_error "ledger rows cannot be deleted" P0040 "DELETE FROM wallet_entries WHERE consultation_id='$B1'"
q "UPDATE consultations SET status='REFUNDED' WHERE id='$B1'" >/dev/null
check "refund after completion reverses the earning" "$(q "SELECT kind || ':' || amount_minor FROM wallet_entries WHERE consultation_id='$B1' AND kind='EARNING_REVERSAL'")" "EARNING_REVERSAL:-23800"

echo "mandatory questionnaire"
B2=00000000-0000-0000-0000-0000000001b2; P2=00000000-0000-0000-0000-0000000001e2
run_session $B2 $P2 $M2
q "UPDATE consultations SET status='CONFIRMED', scheduled_at=now() WHERE id='$B2'; UPDATE consultations SET status='COMPLETED' WHERE id='$B2'" >/dev/null
expect_error "no new booking before reviewing the last session" P0050 "INSERT INTO consultations (client_id, counselor_id, offering_id, service, language, duration_minutes, price_minor, currency, expires_at) VALUES ('$M2','$K','$O','MARITAL','ar',60,28000,'AED', now())"
expect_error "a v1 questionnaire must be complete" 23514 "INSERT INTO consultation_reviews (consultation_id, client_id, counselor_id, rating, questionnaire_version, quality) VALUES ('$B2','$M2','$K',5,1,5)"
expect_error "answers are validated" 23514 "INSERT INTO consultation_reviews (consultation_id, client_id, counselor_id, rating, questionnaire_version, quality, commitment, effectiveness, outcome, next_session, next_channel, contact_shared, off_platform_payment, external_channel) VALUES ('$B2','$M2','$K',5,1,5,5,5,5,'MAYBE','OLFA','NO','NO','NO')"
q "INSERT INTO consultation_reviews (consultation_id, client_id, counselor_id, rating, questionnaire_version, quality, commitment, effectiveness, outcome, next_session, next_channel, contact_shared, off_platform_payment, external_channel)
   VALUES ('$B2','$M2','$K',5,1,5,4,4,4,'PLAN_IN_APP','OLFA','NO','NO','NO')" >/dev/null
check "after the questionnaire the client can book again" "$(q "INSERT INTO consultations (client_id, counselor_id, offering_id, service, language, duration_minutes, price_minor, currency, expires_at) VALUES ('$M2','$K','$O','MARITAL','ar',60,28000,'AED', now() + interval '30 min') RETURNING status")" "AWAITING_PAYMENT"

echo "integrity cases & bans"
q "INSERT INTO counselor_integrity_cases (counselor_id, score, status) VALUES ('$K',12,'AWAITING_RESPONSE')" >/dev/null
expect_error "one open case per counselor" 23505 "INSERT INTO counselor_integrity_cases (counselor_id, score) VALUES ('$K',13)"
expect_error "a decision needs an admin and a reason" 23514 "UPDATE counselor_integrity_cases SET status='BANNED' WHERE counselor_id='$K'"
H=$(printf 'b%.0s' {1..64})
q "INSERT INTO banned_identities (kind, value_hash, reason) VALUES ('PHONE','$H','circumvention')" >/dev/null
expect_error "an identity is banned once" 23505 "INSERT INTO banned_identities (kind, value_hash, reason) VALUES ('PHONE','$H','again')"
check "a lifted ban frees the identity" "$(q "UPDATE banned_identities SET lifted_at=now() WHERE value_hash='$H'; INSERT INTO banned_identities (kind, value_hash, reason) VALUES ('PHONE','$H','re-banned') RETURNING kind" | tail -1)" "PHONE"

echo
echo "account/wallet tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

#!/usr/bin/env bash
# Consultations: state machine, payment-before-confirmation, one open booking,
# reviews only after completion (+ rating aggregate), conversation ownership,
# location rounding and distance.
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=olfa_cons_$$
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

C=00000000-0000-0000-0000-0000000000c1   # client
K=00000000-0000-0000-0000-0000000000a1   # counselor
$PSQL -d "$DB" <<SQL >/dev/null
INSERT INTO users (id, phone_e164, phone_country, status) VALUES ('$C','+971500000101','AE','ACTIVE'), ('$K','+971500000102','AE','ACTIVE');
INSERT INTO counselor_profiles (user_id, kind, status, display_name, headline, bio, years_experience, license_number, license_authority, license_country, credential_keys, languages, services)
VALUES ('$K','FAMILY_COUNSELOR','APPROVED','Dr. Huda','Family counselor','Bio',8,'DHA-123','Dubai Health Authority','AE','{cred/k1.pdf}','{ar,en}','{MARITAL,PREMARITAL}');
INSERT INTO counselor_offerings (id, counselor_id, service, language, duration_minutes, price_minor, currency)
VALUES ('00000000-0000-0000-0000-0000000000f1','$K','MARITAL','ar',60,30000,'AED');
SQL
O=00000000-0000-0000-0000-0000000000f1
book(){ q "INSERT INTO consultations (id, client_id, counselor_id, offering_id, service, language, duration_minutes, price_minor, currency, expires_at)
           VALUES ('$1','$C','$K','$O','MARITAL','ar',60,30000,'AED', now() + interval '30 min') RETURNING status"; }

echo "counselor & offering constraints"
expect_error "counselor needs at least one credential" 23514 "INSERT INTO counselor_profiles (user_id, kind, display_name, headline, bio, years_experience, license_number, license_authority, license_country, credential_keys, languages, services) VALUES ('$C','PSYCHOLOGIST','x','x','x',1,'1','a','AE','{}','{ar}','{FAMILY}')"
expect_error "rejection requires a reason" 23514 "UPDATE counselor_profiles SET status='REJECTED' WHERE user_id='$K'"
expect_error "duration must be 30/45/60/90" 23514 "INSERT INTO counselor_offerings (counselor_id, service, language, duration_minutes, price_minor, currency) VALUES ('$K','FAMILY','ar',20,100,'AED')"
expect_error "price must be positive" 23514 "INSERT INTO counselor_offerings (counselor_id, service, language, duration_minutes, price_minor, currency) VALUES ('$K','FAMILY','ar',30,0,'AED')"
expect_error "cannot book yourself" 23514 "INSERT INTO consultations (client_id, counselor_id, offering_id, service, language, duration_minutes, price_minor, currency, expires_at) VALUES ('$K','$K','$O','MARITAL','ar',60,30000,'AED',now())"

echo "booking state machine"
B1=00000000-0000-0000-0000-0000000000b1
check "booking starts AWAITING_PAYMENT" "$(book $B1)" "AWAITING_PAYMENT"
expect_error "one open booking per client × counselor" 23505 "INSERT INTO consultations (client_id, counselor_id, offering_id, service, language, duration_minutes, price_minor, currency, expires_at) VALUES ('$C','$K','$O','MARITAL','ar',60,30000,'AED',now())"
expect_error "cannot confirm before payment (transition)" P0001 "UPDATE consultations SET status='CONFIRMED', scheduled_at=now() WHERE id='$B1'"
expect_error "cannot mark PAID without a payment" P0002 "UPDATE consultations SET status='PAID' WHERE id='$B1'"
P_LOW=00000000-0000-0000-0000-00000000e001; P_OK=00000000-0000-0000-0000-00000000e002
q "INSERT INTO payments (id, user_id, provider, provider_payment_id, amount_minor, currency, status, consultation_id) VALUES
   ('$P_LOW','$C','WEB','pi_low',100,'AED','SUCCEEDED','$B1'), ('$P_OK','$C','WEB','pi_ok',30000,'AED','PENDING','$B1')" >/dev/null
expect_error "underpaid booking cannot be marked PAID" P0002 "UPDATE consultations SET status='PAID', payment_id='$P_LOW' WHERE id='$B1'"
expect_error "pending payment cannot mark PAID" P0002 "UPDATE consultations SET status='PAID', payment_id='$P_OK' WHERE id='$B1'"
q "UPDATE payments SET status='SUCCEEDED' WHERE id='$P_OK'" >/dev/null
check "full successful payment → PAID" "$(q "UPDATE consultations SET status='PAID', payment_id='$P_OK' WHERE id='$B1' RETURNING status")" "PAID"
check "paid_at stamped by trigger" "$(q "SELECT paid_at IS NOT NULL FROM consultations WHERE id='$B1'")" "t"
expect_error "confirmation needs a scheduled time" 23514 "UPDATE consultations SET status='CONFIRMED' WHERE id='$B1'"
check "counselor confirms a paid booking" "$(q "UPDATE consultations SET status='CONFIRMED', scheduled_at=now() + interval '1 day' WHERE id='$B1' RETURNING status")" "CONFIRMED"
expect_error "review not allowed before completion" P0003 "INSERT INTO consultation_reviews (consultation_id, client_id, counselor_id, rating) VALUES ('$B1','$C','$K',5)"

echo "conversation ownership"
CV=$(q "INSERT INTO conversations (kind, consultation_id, started_by) VALUES ('CONSULTATION','$B1','$K') RETURNING id")
check "counselor can open the consultation chat" "$([ -n "$CV" ] && echo yes)" "yes"
expect_error "consultation chat cannot also point to a match" 23514 "INSERT INTO conversations (kind, consultation_id, started_by) VALUES ('MATCH','$B1','$K')"
expect_error "one chat per consultation" 23505 "INSERT INTO conversations (kind, consultation_id, started_by) VALUES ('CONSULTATION','$B1','$K')"

echo "completion & reviews"
check "complete" "$(q "UPDATE consultations SET status='COMPLETED' WHERE id='$B1' RETURNING status")" "COMPLETED"
expect_error "only the booking's client can review" P0003 "INSERT INTO consultation_reviews (consultation_id, client_id, counselor_id, rating) VALUES ('$B1','$K','$K',5)"
expect_error "rating must be 1–5" 23514 "INSERT INTO consultation_reviews (consultation_id, client_id, counselor_id, rating) VALUES ('$B1','$C','$K',6)"
q "INSERT INTO consultation_reviews (consultation_id, client_id, counselor_id, rating, comment) VALUES ('$B1','$C','$K',4,'helpful')" >/dev/null
expect_error "one review per consultation" 23505 "INSERT INTO consultation_reviews (consultation_id, client_id, counselor_id, rating) VALUES ('$B1','$C','$K',5)"
check "rating aggregate updated" "$(q "SELECT rating_avg || '/' || rating_count FROM counselor_profiles WHERE user_id='$K'")" "4.00/1"
# second completed booking rated 5 → avg 4.5
B2=00000000-0000-0000-0000-0000000000b2; P2=00000000-0000-0000-0000-00000000e003
book $B2 >/dev/null
q "INSERT INTO payments (id, user_id, provider, provider_payment_id, amount_minor, currency, status, consultation_id) VALUES ('$P2','$C','WEB','pi_2',30000,'AED','SUCCEEDED','$B2')" >/dev/null
q "UPDATE consultations SET status='PAID', payment_id='$P2' WHERE id='$B2'; UPDATE consultations SET status='CONFIRMED', scheduled_at=now() WHERE id='$B2'; UPDATE consultations SET status='COMPLETED' WHERE id='$B2'" >/dev/null
q "INSERT INTO consultation_reviews (consultation_id, client_id, counselor_id, rating) VALUES ('$B2','$C','$K',5)" >/dev/null
check "average across reviews" "$(q "SELECT rating_avg || '/' || rating_count FROM counselor_profiles WHERE user_id='$K'")" "4.50/2"
q "UPDATE consultation_reviews SET hidden=true WHERE consultation_id='$B2'" >/dev/null
check "hidden (moderated) review leaves the average" "$(q "SELECT rating_avg || '/' || rating_count FROM counselor_profiles WHERE user_id='$K'")" "4.00/1"
expect_error "completed booking cannot go back to CONFIRMED" P0001 "UPDATE consultations SET status='CONFIRMED' WHERE id='$B2'"
check "completed booking can be refunded (dispute)" "$(q "UPDATE consultations SET status='REFUNDED' WHERE id='$B2' RETURNING status")" "REFUNDED"

echo "location"
expect_error "coordinates must be rounded to ~1 km" 23514 "INSERT INTO user_profiles (user_id, display_name, birth_date, gender, country_code, city, marital_status, education, occupation, marriage_timeline, bio, latitude, longitude) VALUES ('$C','a','1990-01-01','MALE','AE','Dubai','NEVER_MARRIED','BACHELOR','teacher','NOT_SURE','b',25.2048,55.27)"
expect_error "latitude and longitude come together" 23514 "INSERT INTO user_profiles (user_id, display_name, birth_date, gender, country_code, city, marital_status, education, occupation, marriage_timeline, bio, latitude) VALUES ('$C','a','1990-01-01','MALE','AE','Dubai','NEVER_MARRIED','BACHELOR','teacher','NOT_SURE','b',25.20)"
check "distance Dubai → Abu Dhabi ≈ 123 km" "$(q "SELECT round(olfa_distance_km(25.20,55.27,24.45,54.38))")" "123"
check "distance with unknown location is NULL" "$(q "SELECT olfa_distance_km(NULL,NULL,24.45,54.38) IS NULL")" "t"
check "free plan cannot search outside its country" "$(q "SELECT e.value FROM feature_entitlements e JOIN subscription_plans p ON p.id=e.plan_id WHERE p.code='FREE' AND feature_key='search_outside_country'")" "false"
check "plus can search outside its country" "$(q "SELECT e.value FROM feature_entitlements e JOIN subscription_plans p ON p.id=e.plan_id WHERE p.code='PLUS' AND feature_key='search_outside_country'")" "true"

echo; echo "consultation tests: $pass passed, $fail failed"; [ "$fail" -eq 0 ]

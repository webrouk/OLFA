#!/usr/bin/env bash
# Consultation chat retention (30 days after the end / last message, then
# deleted for both), managed accounts, in-chat compatibility questions.
#   PGHOST=/tmp PGUSER=postgres bash test/db/chat_compat_managed_test.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=olfa_ccm_$$
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

C=00000000-0000-0000-0000-0000000000c1; K=00000000-0000-0000-0000-0000000000a1; O=00000000-0000-0000-0000-0000000000f1
M=00000000-0000-0000-0000-0000000000d1; F=00000000-0000-0000-0000-0000000000d2; X=00000000-0000-0000-0000-0000000000d3
$PSQL -d "$DB" <<SQL >/dev/null
INSERT INTO users (id, phone_e164, phone_country, status) VALUES
 ('$C','+971500000101','AE','ACTIVE'), ('$K','+971500000102','AE','ACTIVE'),
 ('$M','+971500000103','AE','ACTIVE'), ('$F','+971500000104','AE','ACTIVE'), ('$X','+971500000105','AE','ACTIVE');
INSERT INTO counselor_profiles (user_id, kind, status, display_name, headline, bio, years_experience, license_number, license_authority, license_country, credential_keys, languages, services)
VALUES ('$K','FAMILY_COUNSELOR','APPROVED','Dr. Huda','Family counselor','Bio',8,'DHA-123','Dubai Health Authority','AE','{cred/k1.pdf}','{ar,en}','{MARITAL,PREMARITAL}');
INSERT INTO counselor_offerings (id, counselor_id, service, language, duration_minutes, price_minor, currency) VALUES ('$O','$K','MARITAL','ar',60,30000,'AED');
INSERT INTO user_profiles (user_id, display_name, birth_date, gender, country_code, city, marital_status, education, occupation, marriage_timeline, bio) VALUES
 ('$M','أحمد','1990-01-01','MALE','AE','دبي','NEVER_MARRIED','BACHELOR','doctor','WITHIN_1_YEAR','b'),
 ('$F','سارة','1994-01-01','FEMALE','AE','دبي','NEVER_MARRIED','BACHELOR','engineer','WITHIN_1_YEAR','b'),
 ('$X','ليلى','1995-01-01','FEMALE','AE','دبي','NEVER_MARRIED','BACHELOR','engineer','WITHIN_1_YEAR','b');
SQL

# a completed consultation with its chat
consult(){ # id payment
  q "INSERT INTO consultations (id, client_id, counselor_id, offering_id, service, language, duration_minutes, price_minor, currency, expires_at) VALUES ('$1','$C','$K','$O','MARITAL','ar',60,30000,'AED', now() + interval '30 min')" >/dev/null
  q "INSERT INTO payments (id, user_id, provider, provider_payment_id, amount_minor, currency, status, consultation_id) VALUES ('$2','$C','WEB','pi_$2',30000,'AED','SUCCEEDED','$1')" >/dev/null
  q "UPDATE consultations SET status='PAID', payment_id='$2' WHERE id='$1'; UPDATE consultations SET status='CONFIRMED', scheduled_at=now() WHERE id='$1'" >/dev/null
}
B1=00000000-0000-0000-0000-0000000000b1; consult $B1 00000000-0000-0000-0000-00000000e001
CV=$(q "INSERT INTO conversations (kind, consultation_id, started_by) VALUES ('CONSULTATION','$B1','$K') RETURNING id")
q "INSERT INTO conversation_members (conversation_id, user_id) VALUES ('$CV','$C'), ('$CV','$K')" >/dev/null
msg(){ q "INSERT INTO messages (conversation_id, sender_id, client_message_id, body, created_at) VALUES ('$1','$2',gen_random_uuid(),'hi', $3) RETURNING 'sent'"; }
row(){ q "SELECT folder || ':' || consult_ended || ':' || (expires_at IS NOT NULL) FROM olfa_conversation_list('$K', -1, $1) WHERE conversation_id='$CV'"; }

echo "consultation chat retention"
check "running consultation: no countdown" "$(row "now()")" "INBOX:false:false"
check "message while running" "$(msg $CV $K "now()")" "sent"
q "UPDATE consultations SET status='COMPLETED' WHERE id='$B1'" >/dev/null
q "UPDATE consultations SET completed_at = now() - interval '20 days' WHERE id='$B1'; UPDATE conversations SET last_message_at = now() - interval '20 days' WHERE id='$CV'" >/dev/null
check "ended: countdown shown" "$(row "now()")" "INBOX:true:true"
check "deletion date = 30 days after the end" "$(q "SELECT round(extract(epoch FROM olfa_consult_chat_expires_at('$CV') - now())/86400)")" "10"
check "a message after the end is allowed" "$(msg $CV $C "now()")" "sent"
check "and restarts the 30 days" "$(q "SELECT round(extract(epoch FROM olfa_consult_chat_expires_at('$CV') - now())/86400)")" "30"
check "warning flag 2 days before" "$(q "SELECT warn FROM olfa_conversation_list('$K', -1, now() + interval '28 days') WHERE conversation_id='$CV'")" "t"
check "not shown once its date passed (before the sweep)" "$(q "SELECT count(*) FROM olfa_conversation_list('$C', -1, now() + interval '31 days') WHERE conversation_id='$CV'")" "0"
expect_error "no messages after the date" P0010 "INSERT INTO messages (conversation_id, sender_id, client_message_id, body, created_at) VALUES ('$CV','$C',gen_random_uuid(),'late', now() + interval '31 days')"
check "warning sent once to both, 2 days before" "$(q "SELECT count(*) FROM olfa_run_retention(now() + interval '28 days') WHERE action='warned' AND conversation_id='$CV'")" "2"
check "sweep before the date keeps it" "$(q "SELECT count(*) FROM olfa_run_retention(now() + interval '29 days') WHERE action='deleted_consultation'")" "0"
check "sweep after the date deletes it" "$(q "SELECT count(*) FROM olfa_run_retention(now() + interval '31 days') WHERE action='deleted_consultation' AND conversation_id='$CV'")" "1"
check "conversation, members and messages gone for both" "$(q "SELECT (SELECT count(*) FROM conversations WHERE id='$CV') + (SELECT count(*) FROM conversation_members WHERE conversation_id='$CV') + (SELECT count(*) FROM messages WHERE conversation_id='$CV')")" "0"
check "the consultation record itself stays (payments, reviews)" "$(q "SELECT status FROM consultations WHERE id='$B1'")" "COMPLETED"
check "match chats untouched by the consultation rule" "$(q "SELECT count(*) FROM olfa_run_retention(now() + interval '31 days') WHERE action='deleted_consultation'")" "0"

echo "managed accounts"
check "member account can be managed" "$(q "INSERT INTO account_managers (user_id, manager_name, relation, owner_consent_at) VALUES ('$F','أبو سارة','FATHER', now()) RETURNING relation")" "FATHER"
expect_error "owner consent is required" 23502 "INSERT INTO account_managers (user_id, manager_name, relation) VALUES ('$X','x y','MOTHER')"
expect_error "manager name required" 23514 "INSERT INTO account_managers (user_id, manager_name, relation, owner_consent_at) VALUES ('$X',' ','MOTHER', now())"
q "UPDATE users SET account_type='FAMILY_COUNSELOR' WHERE id='$K'" >/dev/null 2>&1
expect_error "counselor accounts cannot be managed" P0072 "INSERT INTO account_managers (user_id, manager_name, relation, owner_consent_at) VALUES ('$K','x y','FRIEND', now())"
expect_error "revocation records who revoked" 23514 "UPDATE account_managers SET revoked_at = now() WHERE user_id='$F'"
check "revoke" "$(q "UPDATE account_managers SET revoked_at = now(), revoked_by='ACCOUNT' WHERE user_id='$F' RETURNING revoked_by")" "ACCOUNT"

echo "compatibility questions"
MT=00000000-0000-0000-0000-0000000000e9
q "INSERT INTO matches (id, user_a_id, user_b_id) VALUES ('$MT','$M','$F')" >/dev/null
CM=$(q "INSERT INTO conversations (match_id, started_by) VALUES ('$MT','$M') RETURNING id")
q "INSERT INTO conversation_members (conversation_id, user_id) VALUES ('$CM','$M'), ('$CM','$F')" >/dev/null
check "question bank seeded (15 topics, 17 questions)" "$(q "SELECT count(DISTINCT topic) || '/' || count(*) FROM compat_questions WHERE active")" "15/17"
expect_error "a topic cannot be both shared and gender-specific" P0073 "INSERT INTO compat_questions (topic, domain, audience, prompt, options) SELECT 'fut_work','FUTURE','ALL', prompt, options FROM compat_questions WHERE topic='fut_work' AND audience='MALE'"
expect_error "option values 0..10" P0073 "INSERT INTO compat_questions (topic, domain, prompt, options) VALUES ('new_q','LIFESTYLE','{\"ar\":\"a\",\"en\":\"a\",\"fr\":\"a\"}','[{\"key\":\"a\",\"value\":11,\"label\":{\"ar\":\"x\",\"en\":\"x\",\"fr\":\"x\"}},{\"key\":\"b\",\"value\":1,\"label\":{\"ar\":\"x\",\"en\":\"x\",\"fr\":\"x\"}}]')"
expect_error "option keys unique" P0073 "INSERT INTO compat_questions (topic, domain, prompt, options) VALUES ('new_q','LIFESTYLE','{\"ar\":\"a\",\"en\":\"a\",\"fr\":\"a\"}','[{\"key\":\"a\",\"value\":0,\"label\":{\"ar\":\"x\",\"en\":\"x\",\"fr\":\"x\"}},{\"key\":\"a\",\"value\":1,\"label\":{\"ar\":\"x\",\"en\":\"x\",\"fr\":\"x\"}}]')"
q "INSERT INTO compat_sessions (conversation_id, started_by, male_questions, female_questions)
   SELECT '$CM','$M', array_agg(id ORDER BY sort_order) FILTER (WHERE audience <> 'FEMALE'), array_agg(id ORDER BY sort_order) FILTER (WHERE audience <> 'MALE') FROM compat_questions WHERE active" >/dev/null
check "each side gets 15 questions" "$(q "SELECT string_agg(total::text, ',') FROM olfa_compat_progress('$CM')")" "15,15"
WM=$(q "SELECT id FROM compat_questions WHERE topic='fut_work' AND audience='MALE'"); WF=$(q "SELECT id FROM compat_questions WHERE topic='fut_work' AND audience='FEMALE'")
expect_error "a woman cannot answer the men's version" P0074 "INSERT INTO compat_answers (conversation_id, user_id, question_id, option_key) VALUES ('$CM','$F','$WM','o1')"
expect_error "outsiders cannot answer" P0074 "INSERT INTO compat_answers (conversation_id, user_id, question_id, option_key) VALUES ('$CM','$X','$WF','o1')"
expect_error "unknown option" P0074 "INSERT INTO compat_answers (conversation_id, user_id, question_id, option_key) VALUES ('$CM','$F','$WF','zz')"
q "INSERT INTO compat_answers (conversation_id, user_id, question_id, option_key) SELECT '$CM','$M', unnest(male_questions), 'o0' FROM compat_sessions WHERE conversation_id='$CM'" >/dev/null
check "one side finished, the other has not started" "$(q "SELECT string_agg(answered || '/' || total, ',' ORDER BY answered DESC) FROM olfa_compat_progress('$CM')")" "15/15,0/15"
expect_error "no result while one side is unfinished" P0075 "INSERT INTO compat_results (conversation_id, score, breakdown) VALUES ('$CM', 80, '{}')"
q "INSERT INTO compat_answers (conversation_id, user_id, question_id, option_key) SELECT '$CM','$F', unnest(female_questions), 'o0' FROM compat_sessions WHERE conversation_id='$CM'" >/dev/null
check "result once both finished" "$(q "INSERT INTO compat_results (conversation_id, score, breakdown) VALUES ('$CM', 100, '{}') RETURNING score")" "100"
expect_error "answers are final once the result is out" P0074 "UPDATE compat_answers SET option_key='o1' WHERE conversation_id='$CM' AND user_id='$F' AND question_id='$WF'"
expect_error "answered questions keep their options" P0073 "UPDATE compat_questions SET options = options || '[{\"key\":\"o9\",\"value\":9,\"label\":{\"ar\":\"x\",\"en\":\"x\",\"fr\":\"x\"}}]'::jsonb WHERE id='$WF'"
check "but can be switched off" "$(q "UPDATE compat_questions SET active=false WHERE id='$WF' RETURNING active")" "f"
check "the result card is a COMPAT message" "$(q "INSERT INTO messages (conversation_id, sender_id, client_message_id, type) VALUES ('$CM','$M',gen_random_uuid(),'COMPAT') RETURNING type")" "COMPAT"
check "deleting the chat removes the questionnaire" "$(q "DELETE FROM conversations WHERE id='$CM'; SELECT (SELECT count(*) FROM compat_sessions) + (SELECT count(*) FROM compat_answers) + (SELECT count(*) FROM compat_results)")" "0"

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]

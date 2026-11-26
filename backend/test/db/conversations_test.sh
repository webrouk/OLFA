#!/usr/bin/env bash
# Conversation lifecycle: unmatch → closed chat → ONE re-match request,
# archive, 15/30-day retention with early warnings, unmatched auto-delete,
# and plan visibility (Free 5 · Plus 10 · Premium unlimited; archive counts).
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=olfa_conv_$$
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

ME=00000000-0000-0000-0000-000000000001
# me + 14 peers, each with a match and a conversation; conversation k has last activity k hours ago
$PSQL -d "$DB" <<SQL >/dev/null
INSERT INTO users (id, phone_e164, phone_country, status) VALUES ('$ME','+971500000001','AE','ACTIVE');
INSERT INTO users (id, phone_e164, phone_country, status)
SELECT ('00000000-0000-0000-0000-1000000000' || lpad(g::text,2,'0'))::uuid, '+97150100' || lpad(g::text,4,'0'), 'AE', 'ACTIVE' FROM generate_series(1,14) g;
INSERT INTO matches (id, user_a_id, user_b_id)
SELECT ('00000000-0000-0000-0000-2000000000' || lpad(g::text,2,'0'))::uuid, '$ME', ('00000000-0000-0000-0000-1000000000' || lpad(g::text,2,'0'))::uuid FROM generate_series(1,14) g;
INSERT INTO conversations (id, match_id, started_by, last_message_at)
SELECT ('00000000-0000-0000-0000-3000000000' || lpad(g::text,2,'0'))::uuid, ('00000000-0000-0000-0000-2000000000' || lpad(g::text,2,'0'))::uuid, '$ME', now() - make_interval(hours => g) FROM generate_series(1,14) g;
INSERT INTO conversation_members (conversation_id, user_id)
SELECT ('00000000-0000-0000-0000-3000000000' || lpad(g::text,2,'0'))::uuid, '$ME' FROM generate_series(1,14) g
UNION ALL
SELECT ('00000000-0000-0000-0000-3000000000' || lpad(g::text,2,'0'))::uuid, ('00000000-0000-0000-0000-1000000000' || lpad(g::text,2,'0'))::uuid FROM generate_series(1,14) g;
SQL
C1=00000000-0000-0000-0000-300000000001; P1=00000000-0000-0000-0000-100000000001
C2=00000000-0000-0000-0000-300000000002; P2=00000000-0000-0000-0000-100000000002
msg(){ q "INSERT INTO messages (conversation_id, sender_id, client_message_id, body) VALUES ('$1','$2',gen_random_uuid(),'hi') RETURNING 'sent'"; }
list(){ q "SELECT string_agg(section || ':' || COALESCE(list_position::text,'-') || ':' || locked, ',' ORDER BY section, list_position) FROM olfa_conversation_list('$ME', $1)"; }
count_visible(){ q "SELECT count(*) FILTER (WHERE NOT locked) || '/' || count(*) FILTER (WHERE locked) FROM olfa_conversation_list('$ME', $1) WHERE section IN ('INBOX','ARCHIVE')"; }

echo "plan visibility (inbox + archive share the limit)"
check "Free: 5 visible, 9 locked"    "$(count_visible 5)"  "5/9"
check "Plus: 10 visible, 4 locked"   "$(count_visible 10)" "10/4"
check "Premium: all visible"         "$(count_visible -1)" "14/0"
check "the most recent conversations are the visible ones" "$(q "SELECT bool_and(NOT locked) FROM olfa_conversation_list('$ME',5) WHERE list_position <= 5")" "t"
q "UPDATE conversation_members SET folder='ARCHIVE', archived_at=now() WHERE user_id='$ME' AND conversation_id IN ('$C1','$C2')" >/dev/null
check "archiving does not free a slot" "$(count_visible 5)" "5/9"
check "archived chats stay in their section" "$(q "SELECT string_agg(section, ',' ORDER BY list_position) FROM olfa_conversation_list('$ME',5) WHERE conversation_id IN ('$C1','$C2')")" "ARCHIVE,ARCHIVE"
q "UPDATE conversation_members SET folder='INBOX', archived_at=NULL WHERE user_id='$ME'" >/dev/null
expect_error "archive flag and timestamp go together" 23514 "UPDATE conversation_members SET folder='ARCHIVE' WHERE user_id='$ME' AND conversation_id='$C1'"

# a paid consultation chat is neither counted nor locked
K=00000000-0000-0000-0000-0000000000a1
$PSQL -d "$DB" <<SQL >/dev/null
INSERT INTO users (id, phone_e164, phone_country, status) VALUES ('$K','+971500000099','AE','ACTIVE');
INSERT INTO counselor_profiles (user_id, kind, status, display_name, headline, bio, years_experience, license_number, license_authority, license_country, credential_keys, languages, services)
VALUES ('$K','FAMILY_COUNSELOR','APPROVED','Dr','h','b',5,'L','A','AE','{k}','{ar}','{MARITAL}');
INSERT INTO counselor_offerings (id, counselor_id, service, language, duration_minutes, price_minor, currency) VALUES ('00000000-0000-0000-0000-0000000000f1','$K','MARITAL','ar',60,100,'AED');
INSERT INTO consultations (id, client_id, counselor_id, offering_id, service, language, duration_minutes, price_minor, currency, expires_at)
VALUES ('00000000-0000-0000-0000-0000000000b1','$ME','$K','00000000-0000-0000-0000-0000000000f1','MARITAL','ar',60,100,'AED',now());
INSERT INTO conversations (id, kind, consultation_id, started_by, last_message_at) VALUES ('00000000-0000-0000-0000-3000000000ff','CONSULTATION','00000000-0000-0000-0000-0000000000b1','$K', now());
INSERT INTO conversation_members (conversation_id, user_id) VALUES ('00000000-0000-0000-0000-3000000000ff','$ME'), ('00000000-0000-0000-0000-3000000000ff','$K');
SQL
check "consultation chat: own section, never locked" "$(q "SELECT section || ':' || locked FROM olfa_conversation_list('$ME',5) WHERE conversation_id='00000000-0000-0000-0000-3000000000ff'")" "CONSULTATION:false"
check "…and does not take a free slot" "$(count_visible 5)" "5/9"

echo "unmatch & re-match"
check "message allowed while matched" "$(msg $C1 $ME)" "sent"
q "SELECT olfa_unmatch('$C1','$P1')" >/dev/null
check "unmatch moves the chat to Unmatched for both" "$(q "SELECT section FROM olfa_conversation_list('$ME',5) WHERE conversation_id='$C1'")" "UNMATCHED"
check "unmatched chats are never locked or counted" "$(count_visible 5)" "5/8"
expect_error "no messages after unmatch (either side)" P0010 "INSERT INTO messages (conversation_id, sender_id, client_message_id, body) VALUES ('$C1','$ME',gen_random_uuid(),'hello?')"
expect_error "…not even from the one who unmatched" P0010 "INSERT INTO messages (conversation_id, sender_id, client_message_id, body) VALUES ('$C1','$P1',gen_random_uuid(),'x')"
expect_error "cannot unmatch twice" P0012 "SELECT olfa_unmatch('$C1','$ME')"
expect_error "outsider cannot unmatch" P0011 "SELECT olfa_unmatch('$C2','$P1')"
expect_error "re-match only for unmatched chats" P0013 "SELECT olfa_request_rematch('$C2','$ME')"
check "re-match request notifies the other person" "$(q "SELECT olfa_request_rematch('$C1','$ME') = '$P1'")" "t"
expect_error "only ONE re-match request per conversation" 23505 "SELECT olfa_request_rematch('$C1','$P1')"
expect_error "requester cannot accept their own request" P0015 "SELECT olfa_respond_rematch('$C1','$ME',true)"
check "the other person accepts" "$(q "SELECT olfa_respond_rematch('$C1','$P1',true)")" "ACCEPTED"
check "chat is back in Messages" "$(q "SELECT section FROM olfa_conversation_list('$ME',5) WHERE conversation_id='$C1'")" "INBOX"
check "messages allowed again" "$(msg $C1 $P1)" "sent"
q "SELECT olfa_unmatch('$C1','$P1')" >/dev/null
expect_error "after a used request, no second request is possible" 23505 "SELECT olfa_request_rematch('$C1','$ME')"
q "SELECT olfa_unmatch('$C2','$ME')" >/dev/null; q "SELECT olfa_request_rematch('$C2','$P2')" >/dev/null
check "declined request keeps the chat closed" "$(q "SELECT olfa_respond_rematch('$C2','$ME',false) || '/' || (SELECT status FROM matches WHERE id='00000000-0000-0000-0000-200000000002')")" "DECLINED/UNMATCHED"

echo "retention & warnings"
C5=00000000-0000-0000-0000-300000000005; C6=00000000-0000-0000-0000-300000000006
q "UPDATE conversation_members SET retention_anchor_at = now() - interval '11 days' WHERE conversation_id='$C5'" >/dev/null
q "UPDATE conversation_members SET folder='ARCHIVE', archived_at=now() - interval '24 days', retention_anchor_at = now() - interval '24 days' WHERE conversation_id='$C6' AND user_id='$ME'" >/dev/null
check "inbox chat shows the warning flag after 10 days" "$(q "SELECT warn FROM olfa_conversation_list('$ME',-1) WHERE conversation_id='$C5'")" "t"
check "archived chat warns 7 days before 30" "$(q "SELECT warn FROM olfa_conversation_list('$ME',-1) WHERE conversation_id='$C6'")" "t"
q "SELECT * FROM olfa_run_retention(now())" >/dev/null
check "one 'expiring soon' notification per member (inbox ×2 + archive ×1)" "$(q "SELECT count(*) FROM notifications WHERE type='CONVERSATION_EXPIRING'")" "3"
check "inbox notice says 4 days left" "$(q "SELECT DISTINCT params->>'daysLeft' FROM notifications WHERE type='CONVERSATION_EXPIRING' AND data->>'conversationId'='$C5'")" "4"
q "SELECT * FROM olfa_run_retention(now())" >/dev/null
check "warnings are not repeated" "$(q "SELECT count(*) FROM notifications WHERE type='CONVERSATION_EXPIRING'")" "3"
msg $C5 $ME >/dev/null
check "a new message keeps the chat (timer + warning reset)" "$(q "SELECT bool_and(expiry_warned_at IS NULL AND retention_anchor_at > now() - interval '1 minute') FROM conversation_members WHERE conversation_id='$C5'")" "t"
r=$(q "SELECT string_agg(action, ',' ORDER BY action) FROM olfa_run_retention(now() + interval '16 days')")
check "inbox chats expire after 15 idle days" "$(q "SELECT count(*) FROM conversation_members cm JOIN conversations c ON c.id=cm.conversation_id JOIN matches m ON m.id=c.match_id WHERE m.status='ACTIVE'")" "0"
check "consultation chats are not touched by retention" "$(q "SELECT count(*) FROM conversation_members WHERE conversation_id='00000000-0000-0000-0000-3000000000ff'")" "2"
check "…and empty conversations are removed" "$(echo "$r" | grep -c deleted_empty)" "1"
check "unmatched chats survive until their own month" "$(q "SELECT count(*) FROM conversations c JOIN matches m ON m.id=c.match_id WHERE m.status='UNMATCHED'")" "2"
q "SELECT * FROM olfa_run_retention(now() + interval '31 days')" >/dev/null
check "unmatched for a month → deleted" "$(q "SELECT count(*) FROM conversations WHERE kind='MATCH'")" "0"

echo; 
echo "chat media, phone flag, search, height/weight"
C3=00000000-0000-0000-0000-3000000000e1; PE=00000000-0000-0000-0000-1000000000e1
$PSQL -d "$DB" <<SQL >/dev/null
INSERT INTO users (id, phone_e164, phone_country, status) VALUES ('$PE','+971509998877','AE','ACTIVE');
INSERT INTO matches (id, user_a_id, user_b_id) VALUES ('00000000-0000-0000-0000-2000000000e1', '$ME', '$PE');
INSERT INTO conversations (id, match_id, started_by) VALUES ('$C3','00000000-0000-0000-0000-2000000000e1','$ME');
INSERT INTO conversation_members (conversation_id, user_id) VALUES ('$C3','$ME'), ('$C3','$PE');
SQL
M=$(q "INSERT INTO messages (conversation_id, sender_id, client_message_id, body, type) VALUES ('$C3','$ME',gen_random_uuid(),'','IMAGE') RETURNING id")
check "a photo message may have no caption" "$([ -n "$M" ] && echo yes)" "yes"
expect_error "a text message still needs text" 23514 "INSERT INTO messages (conversation_id, sender_id, client_message_id, body) VALUES ('$C3','$ME',gen_random_uuid(),'  ')"
att(){ q "INSERT INTO message_attachments (message_id, uploader_id, conversation_id, kind, storage_key, mime, bytes, duration_ms) VALUES ($1,'$ME','$C3','$2','chat/$C3/'||gen_random_uuid(),'$3',1000,$4) RETURNING 'ok'"; }
for k in 1 2 3; do att "'$M'" IMAGE image/jpeg NULL >/dev/null; done
check "three photos fit in one message" "$(q "SELECT count(*) FROM message_attachments WHERE message_id='$M'")" "3"
expect_error "a fourth photo is refused" P0020 "INSERT INTO message_attachments (message_id, uploader_id, conversation_id, kind, storage_key, mime, bytes) VALUES ('$M','$ME','$C3','IMAGE','x4','image/jpeg',10)"
expect_error "photos and voice don't mix in one message" P0020 "INSERT INTO message_attachments (message_id, uploader_id, conversation_id, kind, storage_key, mime, bytes, duration_ms) VALUES ('$M','$ME','$C3','VOICE','v1','audio/mp4',10,5000)"
expect_error "voice notes are at most 60 seconds" 23514 "INSERT INTO message_attachments (uploader_id, conversation_id, kind, storage_key, mime, bytes, duration_ms) VALUES ('$ME','$C3','VOICE','v2','audio/mp4',10,61000)"
expect_error "a voice note needs a duration" 23514 "INSERT INTO message_attachments (uploader_id, conversation_id, kind, storage_key, mime, bytes) VALUES ('$ME','$C3','VOICE','v3','audio/mp4',10)"
q "DELETE FROM messages WHERE id='$M'" >/dev/null
check "deleted media is queued for storage clean-up" "$(q "SELECT count(*) FROM storage_garbage WHERE storage_key LIKE 'chat/$C3/%'")" "3"
q "INSERT INTO messages (conversation_id, sender_id, client_message_id, body) VALUES ('$C3','$ME',gen_random_uuid(),'نلتقي في المكتبة العامة')" >/dev/null
q "INSERT INTO messages (conversation_id, sender_id, client_message_id, body, type) VALUES ('$C3','$PE',gen_random_uuid(),'صورة من رحلة الإسكندرية','IMAGE')" >/dev/null
check "message search has a folded trigram index" "$(q "SELECT count(*) FROM pg_indexes WHERE indexname='messages_body_fold_trgm_idx' AND indexdef LIKE '%olfa_fold%gin_trgm_ops%'")" "1"
check "message search finds Arabic text" "$(q "SELECT count(*) FROM messages WHERE deleted_at IS NULL AND type IN ('TEXT','IMAGE') AND body <> '' AND olfa_fold(body) LIKE '%المكتبه%'")" "1"
check "…whatever the hamza / taa marbuta spelling (العامه, الاسكندريه)" "$(q "SELECT count(*) FROM messages WHERE deleted_at IS NULL AND type IN ('TEXT','IMAGE') AND body <> '' AND olfa_fold(body) LIKE ANY(ARRAY['%العامه%','%الاسكندريه%'])")" "2"
check "…including photo captions" "$(q "SELECT count(*) FROM messages WHERE deleted_at IS NULL AND type IN ('TEXT','IMAGE') AND body <> '' AND olfa_fold(body) LIKE '%رحله%'")" "1"
q "INSERT INTO user_profiles (user_id, display_name, birth_date, gender, country_code, city, marital_status, education, occupation, marriage_timeline, bio) VALUES ('$PE','أحمد','1990-01-01','MALE','AE','دبي','NEVER_MARRIED','BACHELOR','doctor','WITHIN_1_YEAR','b')" >/dev/null
check "names match without hamza (احمد → أحمد)" "$(q "SELECT count(*) FROM user_profiles WHERE olfa_fold(display_name) LIKE '%احمد%'")" "1"
# unread = the other person's messages after my last read (one grouped query for the list)
UNREAD="SELECT coalesce((SELECT n FROM (SELECT m.conversation_id, count(*)::int n FROM messages m JOIN conversation_members cm ON cm.conversation_id=m.conversation_id AND cm.user_id='$ME' WHERE m.conversation_id='$C3' AND m.deleted_at IS NULL AND m.sender_id<>'$ME' AND (cm.last_read_at IS NULL OR m.created_at>cm.last_read_at) GROUP BY 1) x),0)"
check "unread counts only the other person's messages" "$(q "$UNREAD")" "1"
q "UPDATE conversation_members SET last_read_at=now() WHERE conversation_id='$C3' AND user_id='$ME'" >/dev/null
check "…and clears after reading" "$(q "$UNREAD")" "0"
expect_error "height must be realistic" 23514 "INSERT INTO user_profiles (user_id, display_name, birth_date, gender, country_code, city, marital_status, education, occupation, marriage_timeline, bio, height_cm) VALUES ('$ME','n','1990-01-01','MALE','AE','c','NEVER_MARRIED','BACHELOR','doctor','WITHIN_1_YEAR','b',300)"
check "voice-note plans: Free 10 · Plus 30 · Premium unlimited" "$(q "SELECT string_agg(p.code || '=' || fe.value, ',' ORDER BY CASE p.code::text WHEN 'FREE' THEN 0 WHEN 'PLUS' THEN 1 ELSE 2 END) FROM feature_entitlements fe JOIN subscription_plans p ON p.id=fe.plan_id WHERE fe.feature_key='voice_notes_per_conversation'")" "FREE=10,PLUS=30,PREMIUM=-1"
echo "message ordering"
CS=00000000-0000-0000-0000-3000000000f1; PS=00000000-0000-0000-0000-1000000000f1; MS=00000000-0000-0000-0000-2000000000f1
$PSQL -d "$DB" <<SQL >/dev/null
INSERT INTO users (id, phone_e164, phone_country, status) VALUES ('$PS','+971507770042','AE','ACTIVE');
INSERT INTO matches (id, user_a_id, user_b_id) VALUES ('$MS','$ME','$PS');
INSERT INTO conversations (id, match_id, started_by) VALUES ('$CS','$MS','$ME');
INSERT INTO conversation_members (conversation_id, user_id) VALUES ('$CS','$ME'), ('$CS','$PS');
SQL
BASE=$(q "SELECT last_seq FROM conversations WHERE id='$CS'")
# two people sending at the same time, 40 messages each, in parallel sessions
for who in $ME $PS; do
  ( for i in $(seq 1 40); do $PSQL -d "$DB" -c "INSERT INTO messages (conversation_id, sender_id, client_message_id, body) VALUES ('$CS','$who',gen_random_uuid(),'m$i')" >/dev/null; done ) &
done; wait
check "concurrent sends get unique, gap-free positions" "$(q "SELECT count(*) || ':' || count(DISTINCT seq) || ':' || (max(seq)-min(seq)+1) FROM messages WHERE conversation_id='$CS' AND seq > $BASE")" "80:80:80"
check "each sender's messages keep their own order" "$(q "SELECT bool_and(ok) FROM (SELECT (substring(body from 2)::int) = row_number() OVER (PARTITION BY sender_id ORDER BY seq) AS ok FROM messages WHERE conversation_id='$CS' AND seq > $BASE) x")" "t"
check "time follows the order (no two messages share a time)" "$(q "SELECT bool_and(ok) FROM (SELECT created_at > lag(created_at) OVER (ORDER BY seq) OR lag(created_at) OVER (ORDER BY seq) IS NULL AS ok FROM messages WHERE conversation_id='$CS') x")" "t"
check "the conversation points at its latest message" "$(q "SELECT (c.last_seq = max(m.seq) AND c.last_message_at = max(m.created_at))::text FROM conversations c JOIN messages m ON m.conversation_id = c.id WHERE c.id='$CS' GROUP BY c.last_seq, c.last_message_at")" "true"
check "latest activity first: this conversation is now at the top" "$(q "SELECT id FROM conversations ORDER BY last_message_at DESC NULLS LAST LIMIT 1")" "$CS"
expect_error "a message's position never changes" P0040 "UPDATE messages SET seq = seq + 1000 WHERE conversation_id='$CS' AND seq = $BASE + 1"
q "UPDATE conversation_members SET last_read_seq = 50 WHERE conversation_id='$CS' AND user_id='$ME'" >/dev/null
q "UPDATE conversation_members SET last_read_seq = 10 WHERE conversation_id='$CS' AND user_id='$ME'" >/dev/null
check "read position only moves forward (and implies delivered)" "$(q "SELECT last_read_seq || ':' || last_delivered_seq FROM conversation_members WHERE conversation_id='$CS' AND user_id='$ME'")" "50:50"
echo "conversation tests: $pass passed, $fail failed"; [ "$fail" -eq 0 ]

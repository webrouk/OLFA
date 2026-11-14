-- OLFA — conversation lifecycle: unmatch + one re-match request per chat,
-- per-member archive, retention with early warning, plan-based visibility.

CREATE TYPE conversation_folder AS ENUM ('INBOX','ARCHIVE');
CREATE TYPE rematch_status      AS ENUM ('PENDING','ACCEPTED','DECLINED');
ALTER TYPE notification_type ADD VALUE 'CONVERSATION_EXPIRING';
ALTER TYPE notification_type ADD VALUE 'REMATCH_REQUEST';
ALTER TYPE notification_type ADD VALUE 'REMATCH_ACCEPTED';

-- Folder and retention clock are per member: archiving is personal.
ALTER TABLE conversation_members
  ADD COLUMN folder              conversation_folder NOT NULL DEFAULT 'INBOX',
  ADD COLUMN archived_at         timestamptz,
  ADD COLUMN retention_anchor_at timestamptz NOT NULL DEFAULT now(),  -- last message / archive / restore
  ADD COLUMN expiry_warned_at    timestamptz,
  ADD CONSTRAINT archive_stamp CHECK ((folder = 'ARCHIVE') = (archived_at IS NOT NULL));
CREATE INDEX conversation_members_retention_idx ON conversation_members (folder, retention_anchor_at);

-- At most ONE re-match request per conversation, ever (the PK enforces it).
CREATE TABLE rematch_requests (
  conversation_id uuid PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
  requested_by    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status          rematch_status NOT NULL DEFAULT 'PENDING',
  created_at      timestamptz NOT NULL DEFAULT now(),
  responded_at    timestamptz,
  CHECK ((status = 'PENDING') = (responded_at IS NULL))
);

CREATE FUNCTION olfa_setting_int(p_key text, p_default int) RETURNS int LANGUAGE sql STABLE AS $$
  SELECT COALESCE((SELECT (value #>> '{}')::int FROM system_settings WHERE key = p_key), p_default)
$$;

-- No messages in a conversation whose match is not ACTIVE (unmatched/blocked):
-- enforced in the database, not only in the API.
CREATE FUNCTION olfa_message_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st match_status; k conversation_kind;
BEGIN
  SELECT c.kind, m.status INTO k, st FROM conversations c LEFT JOIN matches m ON m.id = c.match_id WHERE c.id = NEW.conversation_id;
  IF k = 'MATCH' AND st IS DISTINCT FROM 'ACTIVE' THEN
    RAISE EXCEPTION 'conversation is closed until the match is restored' USING ERRCODE = 'P0010';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER messages_guard BEFORE INSERT ON messages FOR EACH ROW EXECUTE FUNCTION olfa_message_guard();

-- Any message keeps the conversation alive for everyone in it.
CREATE FUNCTION olfa_message_touch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE conversation_members SET retention_anchor_at = NEW.created_at, expiry_warned_at = NULL
  WHERE conversation_id = NEW.conversation_id;
  RETURN NULL;
END $$;
CREATE TRIGGER messages_touch AFTER INSERT ON messages FOR EACH ROW EXECUTE FUNCTION olfa_message_touch();

-- Unmatch: the conversation moves to "Unmatched" for both, immediately.
CREATE FUNCTION olfa_unmatch(p_conversation uuid, p_by uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_match uuid;
BEGIN
  SELECT c.match_id INTO v_match FROM conversations c
  JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = p_by
  WHERE c.id = p_conversation AND c.kind = 'MATCH' FOR UPDATE OF c;
  IF v_match IS NULL THEN RAISE EXCEPTION 'not a member of this match conversation' USING ERRCODE = 'P0011'; END IF;
  UPDATE matches SET status = 'UNMATCHED', ended_at = now(), ended_by = p_by WHERE id = v_match AND status = 'ACTIVE';
  IF NOT FOUND THEN RAISE EXCEPTION 'match is not active' USING ERRCODE = 'P0012'; END IF;
END $$;

-- One request per conversation; the PK turns a second attempt into 23505.
CREATE FUNCTION olfa_request_rematch(p_conversation uuid, p_by uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_status match_status; v_peer uuid;
BEGIN
  SELECT m.status INTO v_status FROM conversations c JOIN matches m ON m.id = c.match_id
  JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = p_by
  WHERE c.id = p_conversation;
  IF v_status IS NULL THEN RAISE EXCEPTION 'not a member of this match conversation' USING ERRCODE = 'P0011'; END IF;
  IF v_status <> 'UNMATCHED' THEN RAISE EXCEPTION 'only unmatched conversations can be re-matched' USING ERRCODE = 'P0013'; END IF;
  INSERT INTO rematch_requests (conversation_id, requested_by) VALUES (p_conversation, p_by);
  SELECT user_id INTO v_peer FROM conversation_members WHERE conversation_id = p_conversation AND user_id <> p_by;
  INSERT INTO notifications (user_id, type, title_key, body_key, data)
  VALUES (v_peer, 'REMATCH_REQUEST', 'push.rematch_request.title', 'push.rematch_request.body', jsonb_build_object('conversationId', p_conversation));
  RETURN v_peer;
END $$;

-- Only the OTHER person can answer. Accept restores the match and the chat.
CREATE FUNCTION olfa_respond_rematch(p_conversation uuid, p_by uuid, p_accept boolean) RETURNS rematch_status LANGUAGE plpgsql AS $$
DECLARE r rematch_requests%ROWTYPE; v_match uuid;
BEGIN
  SELECT * INTO r FROM rematch_requests WHERE conversation_id = p_conversation FOR UPDATE;
  IF r.conversation_id IS NULL OR r.status <> 'PENDING' THEN RAISE EXCEPTION 'no pending re-match request' USING ERRCODE = 'P0014'; END IF;
  IF r.requested_by = p_by OR NOT EXISTS (SELECT 1 FROM conversation_members WHERE conversation_id = p_conversation AND user_id = p_by) THEN
    RAISE EXCEPTION 'only the other member can answer' USING ERRCODE = 'P0015';
  END IF;
  UPDATE rematch_requests SET status = CASE WHEN p_accept THEN 'ACCEPTED'::rematch_status ELSE 'DECLINED' END, responded_at = now()
  WHERE conversation_id = p_conversation;
  IF p_accept THEN
    SELECT match_id INTO v_match FROM conversations WHERE id = p_conversation;
    UPDATE matches SET status = 'ACTIVE', ended_at = NULL, ended_by = NULL WHERE id = v_match AND status = 'UNMATCHED';
    UPDATE conversation_members SET folder = 'INBOX', archived_at = NULL, retention_anchor_at = now(), expiry_warned_at = NULL
    WHERE conversation_id = p_conversation;
    INSERT INTO notifications (user_id, type, title_key, body_key, data)
    VALUES (r.requested_by, 'REMATCH_ACCEPTED', 'push.rematch_accepted.title', 'push.rematch_accepted.body', jsonb_build_object('conversationId', p_conversation));
  END IF;
  RETURN CASE WHEN p_accept THEN 'ACCEPTED'::rematch_status ELSE 'DECLINED' END;
END $$;

-- The user's conversations with section, plan visibility and expiry.
-- p_limit: visible conversations for the plan (-1 = unlimited). Inbox AND
-- archive share the limit; unmatched and consultation chats are never limited.
CREATE FUNCTION olfa_conversation_list(p_user uuid, p_limit int, p_now timestamptz DEFAULT now())
RETURNS TABLE (conversation_id uuid, section text, list_position int, locked boolean, expires_at timestamptz, warn boolean)
LANGUAGE sql STABLE AS $$
  WITH mine AS (
    SELECT c.id, c.kind, cm.folder, cm.retention_anchor_at, m.status AS match_status, m.ended_at,
           COALESCE(c.last_message_at, c.created_at) AS activity
    FROM conversation_members cm
    JOIN conversations c ON c.id = cm.conversation_id
    LEFT JOIN matches m ON m.id = c.match_id
    WHERE cm.user_id = p_user AND (c.kind = 'CONSULTATION' OR m.status IN ('ACTIVE','UNMATCHED'))
  ), placed AS (
    SELECT id, CASE WHEN kind = 'CONSULTATION' THEN 'CONSULTATION' WHEN match_status = 'UNMATCHED' THEN 'UNMATCHED' ELSE folder::text END AS section,
      CASE WHEN kind = 'CONSULTATION' THEN NULL
           WHEN match_status = 'UNMATCHED' THEN ended_at + make_interval(days => olfa_setting_int('chat.unmatchedRetentionDays', 30))
           WHEN folder = 'ARCHIVE'       THEN retention_anchor_at + make_interval(days => olfa_setting_int('chat.archiveRetentionDays', 30))
           ELSE                               retention_anchor_at + make_interval(days => olfa_setting_int('chat.inboxRetentionDays', 15)) END AS expires_at,
      CASE WHEN kind = 'CONSULTATION' OR match_status = 'UNMATCHED' THEN NULL
           ELSE row_number() OVER (PARTITION BY (kind = 'CONSULTATION' OR match_status = 'UNMATCHED') ORDER BY activity DESC, id) END AS pos,
      folder
    FROM mine
  )
  SELECT id, section, pos::int,
         (section IN ('INBOX','ARCHIVE') AND p_limit >= 0 AND pos > p_limit) AS locked,
         expires_at,
         CASE WHEN section IN ('UNMATCHED','CONSULTATION') THEN false
              WHEN folder = 'ARCHIVE' THEN p_now >= expires_at - make_interval(days => olfa_setting_int('chat.archiveWarnBeforeDays', 7))
              ELSE p_now >= expires_at - make_interval(days => olfa_setting_int('chat.inboxRetentionDays', 15) - olfa_setting_int('chat.inboxWarnAfterDays', 10)) END
  FROM placed
  ORDER BY section, pos NULLS LAST, expires_at
$$;

-- Daily job: warn once, then expire. Returns what it did (for logs/tests).
CREATE FUNCTION olfa_run_retention(p_now timestamptz DEFAULT now())
RETURNS TABLE (action text, conversation_id uuid, user_id uuid) LANGUAGE plpgsql AS $$
DECLARE
  inbox_days int := olfa_setting_int('chat.inboxRetentionDays', 15);
  inbox_warn int := olfa_setting_int('chat.inboxWarnAfterDays', 10);
  arch_days  int := olfa_setting_int('chat.archiveRetentionDays', 30);
  arch_warn  int := olfa_setting_int('chat.archiveWarnBeforeDays', 7);
  unm_days   int := olfa_setting_int('chat.unmatchedRetentionDays', 30);
BEGIN
  -- 1. warnings (once per retention cycle; a new message resets the cycle)
  RETURN QUERY
  WITH due AS (
    UPDATE conversation_members cm SET expiry_warned_at = p_now
    FROM conversations c JOIN matches m ON m.id = c.match_id
    WHERE c.id = cm.conversation_id AND m.status = 'ACTIVE' AND cm.expiry_warned_at IS NULL
      AND ((cm.folder = 'INBOX'   AND p_now >= cm.retention_anchor_at + make_interval(days => inbox_warn))
        OR (cm.folder = 'ARCHIVE' AND p_now >= cm.retention_anchor_at + make_interval(days => arch_days - arch_warn)))
    RETURNING cm.conversation_id, cm.user_id, cm.folder, cm.retention_anchor_at
  ), notified AS (
    INSERT INTO notifications (user_id, type, title_key, body_key, params, data)
    SELECT d.user_id, 'CONVERSATION_EXPIRING', 'push.chat_expiring.title', 'push.chat_expiring.body',
           jsonb_build_object('daysLeft', GREATEST(1, ceil(extract(epoch FROM (d.retention_anchor_at
             + make_interval(days => CASE WHEN d.folder = 'ARCHIVE' THEN arch_days ELSE inbox_days END) - p_now)) / 86400)::int)),
           jsonb_build_object('conversationId', d.conversation_id)
    FROM due d RETURNING 1
  )
  SELECT 'warned', d.conversation_id, d.user_id FROM due d;

  -- 2. expiry of active conversations, per member
  RETURN QUERY
  DELETE FROM conversation_members cm USING conversations c, matches m
  WHERE c.id = cm.conversation_id AND m.id = c.match_id AND m.status = 'ACTIVE'
    AND p_now >= cm.retention_anchor_at + make_interval(days => CASE WHEN cm.folder = 'ARCHIVE' THEN arch_days ELSE inbox_days END)
  RETURNING 'expired', cm.conversation_id, cm.user_id;

  -- 3. unmatched for a month without a re-match → deleted for both
  RETURN QUERY
  DELETE FROM conversations c USING matches m
  WHERE m.id = c.match_id AND m.status = 'UNMATCHED' AND p_now >= m.ended_at + make_interval(days => unm_days)
  RETURNING 'deleted_unmatched', c.id, NULL::uuid;

  -- 4. conversations nobody can see any more
  RETURN QUERY
  DELETE FROM conversations c WHERE c.kind = 'MATCH' AND NOT EXISTS (SELECT 1 FROM conversation_members cm WHERE cm.conversation_id = c.id)
  RETURNING 'deleted_empty', c.id, NULL::uuid;
END $$;

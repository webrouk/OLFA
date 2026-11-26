-- Chat ordering & sync.
--  * Every message gets a per-conversation sequence number (1, 2, 3 …) assigned by the
--    database while it holds the conversation row lock, so concurrent sends are
--    serialised: seq order = commit order = the order everyone sees. No gaps, no ties.
--  * conversations.last_seq / last_message_at move forward in the same statement
--    (conversation list sorting = latest message first).
--  * Read and delivery positions per member as sequence numbers ("read up to N").

ALTER TABLE conversations ADD COLUMN last_seq bigint NOT NULL DEFAULT 0;
ALTER TABLE messages ADD COLUMN seq bigint;

-- existing messages: by time, then id
WITH n AS (
  SELECT id, row_number() OVER (PARTITION BY conversation_id ORDER BY created_at, id) AS s FROM messages
)
UPDATE messages m SET seq = n.s FROM n WHERE n.id = m.id;
UPDATE conversations c SET last_seq = COALESCE((SELECT max(seq) FROM messages m WHERE m.conversation_id = c.id), 0);

ALTER TABLE messages ALTER COLUMN seq SET NOT NULL;
ALTER TABLE messages ADD CONSTRAINT messages_conversation_seq_key UNIQUE (conversation_id, seq);
ALTER TABLE messages ADD CONSTRAINT messages_seq_positive CHECK (seq > 0);

ALTER TABLE conversation_members
  ADD COLUMN last_read_seq bigint NOT NULL DEFAULT 0,
  ADD COLUMN last_delivered_seq bigint NOT NULL DEFAULT 0;
UPDATE conversation_members cm SET
  last_read_seq = COALESCE((SELECT max(m.seq) FROM messages m WHERE m.conversation_id = cm.conversation_id AND cm.last_read_at IS NOT NULL AND m.created_at <= cm.last_read_at), 0);
UPDATE conversation_members SET last_delivered_seq = last_read_seq;

-- Runs after messages_guard (triggers fire in name order). The UPDATE takes the
-- conversation row lock until commit: a second sender waits, then gets seq + 1.
CREATE FUNCTION olfa_message_sequence() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE prev timestamptz;
BEGIN
  SELECT last_message_at INTO prev FROM conversations WHERE id = NEW.conversation_id FOR UPDATE;
  -- the time follows the order too (never earlier than the previous message)
  NEW.created_at := GREATEST(clock_timestamp(), COALESCE(prev, '-infinity'::timestamptz) + interval '1 microsecond');
  UPDATE conversations SET last_seq = last_seq + 1, last_message_at = NEW.created_at
  WHERE id = NEW.conversation_id
  RETURNING last_seq INTO NEW.seq;
  IF NEW.seq IS NULL THEN
    RAISE EXCEPTION 'conversation % does not exist', NEW.conversation_id USING ERRCODE = '23503';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER messages_sequence BEFORE INSERT ON messages FOR EACH ROW EXECUTE FUNCTION olfa_message_sequence();

-- A message's position can never change.
CREATE FUNCTION olfa_message_seq_frozen() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.seq <> OLD.seq OR NEW.conversation_id <> OLD.conversation_id THEN
    RAISE EXCEPTION 'message order is immutable' USING ERRCODE = 'P0040';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER messages_seq_frozen BEFORE UPDATE OF seq, conversation_id ON messages FOR EACH ROW EXECUTE FUNCTION olfa_message_seq_frozen();

-- Read / delivered positions only move forward.
CREATE FUNCTION olfa_member_positions() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.last_read_seq := GREATEST(NEW.last_read_seq, OLD.last_read_seq);
  NEW.last_delivered_seq := GREATEST(NEW.last_delivered_seq, OLD.last_delivered_seq, NEW.last_read_seq);
  RETURN NEW;
END $$;
CREATE TRIGGER conversation_members_positions BEFORE UPDATE OF last_read_seq, last_delivered_seq ON conversation_members
  FOR EACH ROW EXECUTE FUNCTION olfa_member_positions();

-- Pages and catch-up read by position.
CREATE INDEX messages_conv_seq_idx ON messages (conversation_id, seq DESC) WHERE deleted_at IS NULL;
-- Conversation list: latest message first.
CREATE INDEX conversations_last_seq_idx ON conversations (last_message_at DESC NULLS LAST, id);

-- Chat photos (up to 3 per message) and voice notes (≤ 60 s, per-conversation
-- plan quota), phone-number detection flag, message search at scale, and
-- height / weight on profiles and in discovery filters.

ALTER TYPE message_type ADD VALUE 'IMAGE';
ALTER TYPE message_type ADD VALUE 'VOICE';

-- A media message may have no caption.
ALTER TABLE messages DROP CONSTRAINT messages_body_check;
ALTER TABLE messages ALTER COLUMN body SET DEFAULT '';
ALTER TABLE messages ADD CONSTRAINT messages_body_check CHECK (type::text <> 'TEXT' OR length(btrim(body)) > 0);
-- Set by the server when the text looks like a phone number: both people see a safety note.
ALTER TABLE messages ADD COLUMN contains_phone boolean NOT NULL DEFAULT false;

CREATE TYPE attachment_kind AS ENUM ('IMAGE','VOICE');
CREATE TABLE message_attachments (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id   uuid REFERENCES messages(id) ON DELETE CASCADE,   -- NULL until sent
  uploader_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  kind         attachment_kind NOT NULL,
  storage_key  varchar(200) NOT NULL UNIQUE,                     -- private bucket only
  mime         varchar(40) NOT NULL,
  bytes        int NOT NULL CHECK (bytes > 0 AND bytes <= 8388608),
  width        smallint,
  height       smallint,
  duration_ms  int CHECK (duration_ms IS NULL OR (duration_ms > 0 AND duration_ms <= 60000)),
  waveform     smallint[],                                        -- 48 peaks 0–100 for the voice bubble
  position     smallint NOT NULL DEFAULT 0 CHECK (position BETWEEN 0 AND 2),
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind = 'VOICE') = (duration_ms IS NOT NULL))
);
CREATE INDEX message_attachments_message_idx ON message_attachments (message_id);
CREATE INDEX message_attachments_pending_idx ON message_attachments (uploader_id, created_at) WHERE message_id IS NULL;

-- At most 3 photos, or exactly one voice note, per message.
CREATE FUNCTION olfa_attachment_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n int; k attachment_kind;
BEGIN
  IF NEW.message_id IS NULL THEN RETURN NEW; END IF;
  SELECT count(*), min(kind::text)::attachment_kind INTO n, k FROM message_attachments WHERE message_id = NEW.message_id AND id <> NEW.id;
  IF n > 0 AND k <> NEW.kind THEN RAISE EXCEPTION 'mixed attachments' USING ERRCODE = 'P0020'; END IF;
  IF NEW.kind = 'IMAGE' AND n >= 3 THEN RAISE EXCEPTION 'max 3 photos per message' USING ERRCODE = 'P0020'; END IF;
  IF NEW.kind = 'VOICE' AND n >= 1 THEN RAISE EXCEPTION 'one voice note per message' USING ERRCODE = 'P0020'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER message_attachments_guard BEFORE INSERT OR UPDATE OF message_id ON message_attachments
  FOR EACH ROW EXECUTE FUNCTION olfa_attachment_guard();

-- ───────────── message search ─────────────
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX messages_body_trgm_idx ON messages USING gin (body gin_trgm_ops) WHERE deleted_at IS NULL AND type = 'TEXT';
CREATE INDEX user_profiles_name_trgm_idx ON user_profiles USING gin (display_name gin_trgm_ops);

-- ───────────── height & weight ─────────────
ALTER TABLE user_profiles
  ADD COLUMN height_cm smallint CHECK (height_cm IS NULL OR height_cm BETWEEN 120 AND 230),
  ADD COLUMN weight_kg smallint CHECK (weight_kg IS NULL OR weight_kg BETWEEN 35 AND 250);

-- ───────────── storage clean-up ─────────────
-- When a chat attachment row disappears (conversation retention, account
-- deletion, unsent uploads), its private object is queued for deletion.
CREATE TABLE storage_garbage (
  storage_key varchar(200) PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION olfa_attachment_gc() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO storage_garbage (storage_key) VALUES (OLD.storage_key) ON CONFLICT DO NOTHING;
  RETURN OLD;
END $$;
CREATE TRIGGER message_attachments_gc AFTER DELETE ON message_attachments
  FOR EACH ROW EXECUTE FUNCTION olfa_attachment_gc();

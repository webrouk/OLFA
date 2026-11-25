-- Compatibility result card inside a chat (its own message type so it keeps its
-- place in the message order). Kept in its own migration: a new enum value
-- cannot be used in the same transaction that adds it.
ALTER TYPE message_type ADD VALUE IF NOT EXISTS 'COMPAT';

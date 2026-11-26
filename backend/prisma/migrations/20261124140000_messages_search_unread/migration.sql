-- Messages page: search that treats Arabic spelling variants as equal, covers
-- photo captions, and an index for the per-conversation unread counts.

-- ═════════════ 1. Arabic-aware folding ═════════════
-- Must stay identical to foldForSearch() in src/domain/text-fold.ts (unit-tested):
--   lower case; أ إ آ ٱ → ا ; ة → ه ; ى → ي ; ؤ → و ; ئ → ي ;
--   tatweel (ـ) and harakat (U+064B–U+0652, U+0670) removed;
--   Arabic-Indic and Eastern Arabic-Indic digits → 0-9.
-- plpgsql (not sql) on purpose: an inlined SQL function would no longer
-- match the expression indexes below.
CREATE FUNCTION olfa_fold(t text) RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE STRICT AS $$
BEGIN
  RETURN translate(
           regexp_replace(lower(t), '[ـًٌٍَُِّْٰ]', '', 'g'),
           'أإآٱةىؤئ٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
           'ااااهيوي01234567890123456789');
END
$$;

-- Old indexes searched the raw text only (and only TEXT messages).
DROP INDEX IF EXISTS messages_body_trgm_idx;
DROP INDEX IF EXISTS user_profiles_name_trgm_idx;
CREATE INDEX messages_body_fold_trgm_idx ON messages USING gin (olfa_fold(body) gin_trgm_ops)
  WHERE deleted_at IS NULL AND type IN ('TEXT', 'IMAGE') AND body <> '';
CREATE INDEX user_profiles_name_fold_trgm_idx ON user_profiles USING gin (olfa_fold(display_name) gin_trgm_ops);
CREATE INDEX counselor_profiles_name_fold_trgm_idx ON counselor_profiles USING gin (olfa_fold(display_name) gin_trgm_ops);

-- ═════════════ 2. Unread counts in one query ═════════════
-- "messages from the other person after my last read" per conversation.
CREATE INDEX messages_unread_idx ON messages (conversation_id, created_at) INCLUDE (sender_id) WHERE deleted_at IS NULL;

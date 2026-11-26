/**
 * Folds text for search so common Arabic spelling variants match each other:
 * "احمد" finds "أحمد", "رساله" finds "رسالة", "مصطفي" finds "مصطفى", and
 * "٠٥٠" finds "050". Harakat and tatweel are ignored.
 *
 * Must stay identical to the SQL function `olfa_fold()` (migration
 * 20261124140000_messages_search_unread) — both are covered by tests.
 */
const MAP: Record<string, string> = {
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ة': 'ه', 'ى': 'ي', 'ؤ': 'و', 'ئ': 'ي',
};
const DROP = /[ـً-ْٰ]/g;

export function foldForSearch(s: string): string {
  return s
    .toLowerCase()
    .replace(DROP, '')
    .replace(/[أإآٱةىؤئ]/g, (c) => MAP[c])
    .replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (c) => String(c.charCodeAt(0) - 0x06f0));
}

/** `%term%` for LIKE against `olfa_fold(column)`, with LIKE wildcards escaped. */
export function foldedLikePattern(term: string): string {
  return `%${foldForSearch(term.trim()).replace(/[\\%_]/g, (c) => '\\' + c)}%`;
}

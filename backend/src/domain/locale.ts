/** The app's languages. Anything else falls back to English (same rule as the app). */
export const APP_LOCALES = ['ar', 'en', 'fr'] as const;
export type AppLocaleCode = (typeof APP_LOCALES)[number];
export const FALLBACK_LOCALE: AppLocaleCode = 'en';

/**
 * Picks the language from an Accept-Language header, honouring the order and
 * q-values the device sends: "fr-CA,fr;q=0.9,en;q=0.8" → fr,
 * "es-ES,es;q=0.9" → en, "ar-EG" → ar.
 */
export function pickLocale(header: string | string[] | undefined | null): AppLocaleCode {
  const raw = Array.isArray(header) ? header.join(',') : header ?? '';
  const ranked = raw
    .split(',')
    .map((part, i) => {
      const [tag, ...params] = part.trim().split(';');
      const q = params.map((p) => p.trim()).find((p) => p.startsWith('q='));
      const weight = q ? Number(q.slice(2)) : 1;
      return { lang: tag.trim().toLowerCase().split('-')[0], weight: Number.isFinite(weight) ? weight : 0, i };
    })
    .filter((x) => x.lang && x.weight > 0)
    .sort((a, b) => b.weight - a.weight || a.i - b.i);
  for (const r of ranked) if ((APP_LOCALES as readonly string[]).includes(r.lang)) return r.lang as AppLocaleCode;
  return FALLBACK_LOCALE;
}

export function asLocale(v: string | null | undefined): AppLocaleCode {
  return (APP_LOCALES as readonly string[]).includes(v ?? '') ? (v as AppLocaleCode) : FALLBACK_LOCALE;
}

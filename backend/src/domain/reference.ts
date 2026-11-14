/** Reference data generated from shared/reference/*.tsv (single source with the app). */
import ref from '../reference/reference.json';

const countries = new Set<string>(ref.countries);
const nationalities = new Set<string>(ref.nationalities);
const occupations = new Set<string>(ref.occupations);
const countryNationality = ref.countryNationality as Record<string, string>;

export const isCountry = (iso: string) => countries.has(iso);
export const isNationality = (iso: string) => nationalities.has(iso);
export const isOccupation = (key: string) => occupations.has(key);
/** Residents of a territory default to the sovereign nationality (PR → US). */
export const defaultNationality = (countryIso: string) => countryNationality[countryIso] ?? null;
export const referenceCounts = () => ({ countries: countries.size, nationalities: nationalities.size, occupations: occupations.size });

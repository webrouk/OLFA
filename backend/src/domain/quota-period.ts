/**
 * Daily quota windows. Stored and compared in UTC; the window boundaries are
 * the user's LOCAL midnights, so "10 likes per day" resets when the user's
 * day resets — including across DST changes.
 */

export function isValidTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** Offset (ms) of `tz` from UTC at instant `t` (positive east of Greenwich). */
export function tzOffsetMs(t: number, tz: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(new Date(t));
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return asUtc - Math.floor(t / 1000) * 1000;
}

/** Local calendar date (Y, M, D) in `tz` at instant `t`. */
export function localDate(t: number, tz: string): { y: number; m: number; d: number } {
  const off = tzOffsetMs(t, tz);
  const d = new Date(t + off);
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate() };
}

/** UTC instant of local midnight for the given local date. Handles DST. */
export function zonedMidnightUtc(y: number, m: number, d: number, tz: string): number {
  const guess = Date.UTC(y, m - 1, d);
  let t = guess - tzOffsetMs(guess, tz);
  t = guess - tzOffsetMs(t, tz); // second pass settles DST transitions
  return t;
}

export interface DayWindow {
  start: Date; // inclusive, UTC
  end: Date; // exclusive, UTC
  dayKey: string; // local date "YYYY-MM-DD"
}

export function dayWindow(now: Date, timeZone: string): DayWindow {
  const tz = isValidTimeZone(timeZone) ? timeZone : 'UTC';
  const { y, m, d } = localDate(now.getTime(), tz);
  const start = zonedMidnightUtc(y, m, d, tz);
  const next = new Date(Date.UTC(y, m - 1, d + 1));
  const end = zonedMidnightUtc(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate(), tz);
  const dayKey = `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
  return { start: new Date(start), end: new Date(end), dayKey };
}

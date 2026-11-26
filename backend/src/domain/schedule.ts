/**
 * Bookable consultation times from a counselor's weekly availability, in the
 * counselor's own time zone (DST-safe), minus time off, existing bookings
 * (+ buffer on both sides), the minimum notice and the booking horizon.
 * Pure and deterministic: `now` is passed in.
 */
export interface WeeklyWindow {
  /** ISO weekday: 1 = Monday … 7 = Sunday. */
  weekday: number;
  startMinute: number;
  endMinute: number;
}
export interface Range {
  start: Date;
  end: Date;
}
export interface SlotInput {
  timezone: string;
  windows: WeeklyWindow[];
  timeOff: Range[];
  busy: Range[];
  durationMinutes: number;
  bufferMinutes: number;
  minNoticeHours: number;
  maxDaysAhead: number;
  now: Date;
  stepMinutes?: number;
}

const MIN = 60_000;

/** Minutes the zone is ahead of UTC at `at` (e.g. Dubai +240, Paris +60 / +120). */
export function tzOffsetMinutes(timezone: string, at: Date): number {
  const f = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
  const p = Object.fromEntries(f.formatToParts(at).map((x) => [x.type, x.value]));
  const asUtc = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
  return Math.round((asUtc - Math.floor(at.getTime() / 1000) * 1000) / MIN);
}

/** Wall-clock time in `timezone` → the UTC instant. */
export function zonedToUtc(y: number, month: number, day: number, minuteOfDay: number, timezone: string): Date {
  const guess = Date.UTC(y, month - 1, day, 0, minuteOfDay);
  const off1 = tzOffsetMinutes(timezone, new Date(guess));
  let t = guess - off1 * MIN;
  const off2 = tzOffsetMinutes(timezone, new Date(t));
  if (off2 !== off1) t = guess - off2 * MIN;
  return new Date(t);
}

/** Today's date in `timezone`. */
function localDate(timezone: string, at: Date) {
  const f = new Intl.DateTimeFormat('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' });
  const [y, m, d] = f.format(at).split('-').map(Number);
  return { y, m, d };
}

const overlaps = (a0: number, a1: number, b0: number, b1: number) => a0 < b1 && b0 < a1;

export function isValidTimeZoneName(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

export function computeSlots(i: SlotInput): Date[] {
  const step = i.stepMinutes ?? 30;
  const earliest = i.now.getTime() + i.minNoticeHours * 60 * MIN;
  const horizon = i.now.getTime() + i.maxDaysAhead * 24 * 60 * MIN;
  const buf = i.bufferMinutes * MIN;
  const today = localDate(i.timezone, i.now);
  const out: Date[] = [];
  for (let k = 0; k <= i.maxDaysAhead; k++) {
    const day = new Date(Date.UTC(today.y, today.m - 1, today.d + k));
    const y = day.getUTCFullYear(), m = day.getUTCMonth() + 1, d = day.getUTCDate();
    const weekday = ((day.getUTCDay() + 6) % 7) + 1;
    for (const w of i.windows.filter((x) => x.weekday === weekday).sort((a, b) => a.startMinute - b.startMinute)) {
      for (let s = w.startMinute; s + i.durationMinutes <= w.endMinute; s += step) {
        const start = zonedToUtc(y, m, d, s, i.timezone).getTime();
        const end = start + i.durationMinutes * MIN;
        if (start < earliest || start > horizon) continue;
        if (i.timeOff.some((r) => overlaps(start, end, r.start.getTime(), r.end.getTime()))) continue;
        if (i.busy.some((r) => overlaps(start - buf, end + buf, r.start.getTime(), r.end.getTime()))) continue;
        out.push(new Date(start));
      }
    }
  }
  return out.sort((a, b) => a.getTime() - b.getTime());
}

/** Whether `at` is one of the bookable times (server-side check on booking/reschedule). */
export function isBookable(i: SlotInput, at: Date): boolean {
  return computeSlots(i).some((s) => s.getTime() === at.getTime());
}

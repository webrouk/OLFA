import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/features/consultations/domain/schedule.dart';

void main() {
  // Sunday 29 Nov 2026, 12:00 local
  final now = DateTime(2026, 11, 29, 12);
  const mon = [WeeklyWindow(weekday: 1, startMinute: 9 * 60, endMinute: 12 * 60)];
  const s = ScheduleSettings(bufferMinutes: 0, minNoticeHours: 1, maxDaysAhead: 7);

  test('weekly window gives half-hourly starts on Monday', () {
    final r = computeLocalSlots(windows: mon, busy: const [], timeOff: const [], durationMinutes: 60, settings: s, now: now);
    expect(r.map((d) => '${d.hour}:${d.minute}'), ['9:0', '9:30', '10:0', '10:30', '11:0']);
  });

  test('bookings with buffer, time off and paused bookings remove times', () {
    final busy = [(DateTime(2026, 11, 30, 10), DateTime(2026, 11, 30, 11))];
    expect(computeLocalSlots(windows: mon, busy: busy, timeOff: const [], durationMinutes: 60, settings: s, now: now).map((d) => d.hour), [9, 11]);
    expect(computeLocalSlots(windows: mon, busy: busy, timeOff: const [], durationMinutes: 60, settings: s.copyWith(bufferMinutes: 15), now: now), isEmpty);
    final off = [(DateTime(2026, 11, 30), DateTime(2026, 12, 1))];
    expect(computeLocalSlots(windows: mon, busy: const [], timeOff: off, durationMinutes: 60, settings: s, now: now), isEmpty);
    expect(computeLocalSlots(windows: mon, busy: const [], timeOff: const [], durationMinutes: 60, settings: s.copyWith(accepting: false), now: now), isEmpty);
  });

  test('overlapping periods are detected', () {
    expect(const WeeklyWindow(weekday: 2, startMinute: 600, endMinute: 720).overlaps(const WeeklyWindow(weekday: 2, startMinute: 700, endMinute: 800)), isTrue);
    expect(const WeeklyWindow(weekday: 2, startMinute: 600, endMinute: 720).overlaps(const WeeklyWindow(weekday: 3, startMinute: 600, endMinute: 720)), isFalse);
  });
}

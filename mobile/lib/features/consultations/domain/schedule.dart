/// Counselor schedule (controlled from the counselor's own account) and the
/// bookable times offered to clients. The server computes the real slots in the
/// counselor's time zone (backend/src/domain/schedule.ts); [computeLocalSlots]
/// mirrors it for the offline preview.
class WeeklyWindow {
  const WeeklyWindow({required this.weekday, required this.startMinute, required this.endMinute});

  /// ISO weekday: 1 = Monday … 7 = Sunday.
  final int weekday;
  final int startMinute;
  final int endMinute;

  bool overlaps(WeeklyWindow o) => o.weekday == weekday && startMinute < o.endMinute && o.startMinute < endMinute;
  Map<String, Object> toJson() => {'weekday': weekday, 'startMinute': startMinute, 'endMinute': endMinute};
  static WeeklyWindow fromJson(Map<String, dynamic> j) =>
      WeeklyWindow(weekday: (j['weekday'] as num).toInt(), startMinute: (j['startMinute'] as num).toInt(), endMinute: (j['endMinute'] as num).toInt());
}

class TimeOff {
  const TimeOff({required this.id, required this.startsAt, required this.endsAt, this.note});
  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? note;
}

class ScheduleSettings {
  const ScheduleSettings({this.timezone = 'Asia/Dubai', this.bufferMinutes = 10, this.minNoticeHours = 12, this.maxDaysAhead = 30, this.accepting = true});
  final String timezone;
  final int bufferMinutes;
  final int minNoticeHours;
  final int maxDaysAhead;
  final bool accepting;

  ScheduleSettings copyWith({String? timezone, int? bufferMinutes, int? minNoticeHours, int? maxDaysAhead, bool? accepting}) => ScheduleSettings(
        timezone: timezone ?? this.timezone,
        bufferMinutes: bufferMinutes ?? this.bufferMinutes,
        minNoticeHours: minNoticeHours ?? this.minNoticeHours,
        maxDaysAhead: maxDaysAhead ?? this.maxDaysAhead,
        accepting: accepting ?? this.accepting,
      );
  Map<String, Object> toJson() => {'timezone': timezone, 'bufferMinutes': bufferMinutes, 'minNoticeHours': minNoticeHours, 'maxDaysAhead': maxDaysAhead, 'accepting': accepting};
}

class CounselorSchedule {
  const CounselorSchedule({required this.settings, required this.windows, required this.timeOff});
  final ScheduleSettings settings;
  final List<WeeklyWindow> windows;
  final List<TimeOff> timeOff;
  bool get published => windows.isNotEmpty;
}

/// Times a client can book (absolute instants; shown in the client's time zone).
class SlotList {
  const SlotList({required this.scheduled, this.timezone, this.slots = const []});

  /// false: the counselor has no published hours — the client proposes a time instead.
  final bool scheduled;
  final String? timezone;
  final List<DateTime> slots;
}

class RatingBreakdown {
  const RatingBreakdown({required this.count, this.average, this.quality, this.commitment, this.effectiveness, this.outcome, this.distribution = const {}});
  final int count;
  final double? average, quality, commitment, effectiveness, outcome;
  final Map<int, int> distribution; // stars → count
  static RatingBreakdown fromJson(Map<String, dynamic> j) {
    double? d(Object? v) => v is num ? v.toDouble() : null;
    return RatingBreakdown(
      count: (j['count'] as num?)?.toInt() ?? 0,
      average: d(j['average']),
      quality: d(j['quality']),
      commitment: d(j['commitment']),
      effectiveness: d(j['effectiveness']),
      outcome: d(j['outcome']),
      distribution: {for (final x in (j['distribution'] as List? ?? const [])) (x['stars'] as num).toInt(): (x['count'] as num).toInt()},
    );
  }
}

class CounselorReview {
  const CounselorReview({required this.consultationId, required this.rating, this.comment, required this.createdAt, this.by, this.reply, this.repliedAt});
  final String consultationId;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String? by;
  final String? reply;
  final DateTime? repliedAt;
}

class MyReviews {
  const MyReviews({required this.ratings, required this.reviews});
  final RatingBreakdown ratings;
  final List<CounselorReview> reviews;
}

/// Weekly hours → start times, for a counselor working in the phone's own time
/// zone (preview only; the server is authoritative and handles any zone).
List<DateTime> computeLocalSlots({
  required List<WeeklyWindow> windows,
  required List<(DateTime, DateTime)> busy,
  required List<(DateTime, DateTime)> timeOff,
  required int durationMinutes,
  required ScheduleSettings settings,
  required DateTime now,
  int stepMinutes = 30,
}) {
  if (!settings.accepting) return const [];
  final earliest = now.add(Duration(hours: settings.minNoticeHours));
  final horizon = now.add(Duration(days: settings.maxDaysAhead));
  final buf = Duration(minutes: settings.bufferMinutes);
  bool overlap(DateTime a0, DateTime a1, DateTime b0, DateTime b1) => a0.isBefore(b1) && b0.isBefore(a1);
  final out = <DateTime>[];
  for (var k = 0; k <= settings.maxDaysAhead; k++) {
    final day = DateTime(now.year, now.month, now.day + k);
    for (final w in windows.where((w) => w.weekday == day.weekday)) {
      for (var m = w.startMinute; m + durationMinutes <= w.endMinute; m += stepMinutes) {
        final s = DateTime(day.year, day.month, day.day, 0, m);
        final e = s.add(Duration(minutes: durationMinutes));
        if (s.isBefore(earliest) || s.isAfter(horizon)) continue;
        if (timeOff.any((r) => overlap(s, e, r.$1, r.$2))) continue;
        if (busy.any((r) => overlap(s.subtract(buf), e.add(buf), r.$1, r.$2))) continue;
        out.add(s);
      }
    }
  }
  return out..sort();
}

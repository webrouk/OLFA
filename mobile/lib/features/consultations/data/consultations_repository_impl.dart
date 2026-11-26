import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/consultations_repository.dart';

/// Stripe publishable key (public by design) — pass with --dart-define.
const stripePublishableKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

class ApiConsultationsRepository implements ConsultationsRepository {
  ApiConsultationsRepository(this._api);
  final ApiClient _api;
  Dio get _dio => _api.dio;

  @override
  Future<List<Counselor>> counselors(CounselorQuery q) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/counselors', queryParameters: {
          if (q.kind != null) 'kind': toApiEnum(q.kind!),
          if (q.service != null) 'service': toApiEnum(q.service!),
          if (q.language != null) 'language': q.language,
          if (q.durationMinutes != null) 'durationMinutes': q.durationMinutes,
        });
        return (r.data!['items'] as List).map((j) => ApiMappers.counselor(Map<String, dynamic>.from(j as Map))).toList();
      });

  @override
  Future<Counselor> counselor(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/counselors/$id');
        return ApiMappers.counselor(r.data!);
      });

  @override
  Future<BookingIntent> book({required String offeringId, String? note, DateTime? preferredTime, DateTime? slot}) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/consultations', data: {
          'offeringId': offeringId,
          if (slot != null) 'slot': slot.toUtc().toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          if (preferredTime != null) 'preferredTime': preferredTime.toUtc().toIso8601String(),
        });
        final j = r.data!;
        final pay = Map<String, dynamic>.from(j['payment'] as Map);
        return BookingIntent(
          consultationId: j['id'] as String,
          amountMinor: (j['amountMinor'] as num).toInt(),
          currency: j['currency'] as String,
          expiresAt: DateTime.parse(j['expiresAt'] as String).toLocal(),
          provider: pay['provider'] as String,
          clientSecret: pay['clientSecret'] as String?,
        );
      });

  @override
  Future<void> pay(BookingIntent intent) async {
    if (intent.provider == 'test') {
      // Staging only: the server refuses this route in production.
      await guard(() => _dio.post<void>('/consultations/${intent.consultationId}/test-pay'));
      return;
    }
    if (stripePublishableKey.isEmpty || intent.clientSecret == null) throw const ServerFailure('payments_not_configured');
    Stripe.publishableKey = stripePublishableKey;
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(paymentIntentClientSecret: intent.clientSecret, merchantDisplayName: 'OLFA'),
      );
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (e) {
      throw ServerFailure(e.error.code == FailureCode.Canceled ? 'payment_cancelled' : 'payment_failed');
    }
    // The booking becomes PAID when the signed webhook arrives; the list refresh shows it.
  }

  @override
  Future<BookingIntent> retryPayment(String consultationId) => guard(() async {
        final j = (await _dio.post<Map<String, dynamic>>('/consultations/$consultationId/payment')).data!;
        final pay = Map<String, dynamic>.from(j['payment'] as Map);
        return BookingIntent(
          consultationId: j['id'] as String,
          amountMinor: (j['amountMinor'] as num).toInt(),
          currency: j['currency'] as String,
          expiresAt: DateTime.parse(j['expiresAt'] as String).toLocal(),
          provider: pay['provider'] as String,
          clientSecret: pay['clientSecret'] as String?,
        );
      });

  @override
  Future<List<Consultation>> mine() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/consultations');
        return r.data!.map((j) => ApiMappers.consultation(Map<String, dynamic>.from(j as Map))).toList();
      });

  @override
  Future<void> cancel(String id) => guard(() => _dio.post<void>('/consultations/$id/cancel'));

  @override
  Future<void> review(String id, ReviewAnswers a) => guard(() => _dio.post<void>('/consultations/$id/review', data: {...a.toJson(), 'sessionHappened': true}));
  @override
  Future<void> reportNotHappened(String id, String reason) => guard(() => _dio.post<void>('/consultations/$id/review', data: {'sessionHappened': false, 'disputeReason': reason}));

  @override
  Future<List<PendingReview>> pendingReviews() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/consultations/pending-review');
        return [
          for (final j in r.data!)
            PendingReview(
              consultationId: (j as Map)['id'] as String,
              counselorName: (j['counselor'] as Map?)?['displayName'] as String? ?? '',
              service: fromApiEnum(ConsultationService.values, j['service'], ConsultationService.marital),
              durationMinutes: (j['durationMinutes'] as num).toInt(),
              completedAt: j['completedAt'] == null ? null : DateTime.parse(j['completedAt'] as String).toLocal(),
            ),
        ];
      });

  static IntegrityCase? _case(Map<String, dynamic>? j) => j == null || j.isEmpty
      ? null
      : IntegrityCase(
          id: j['id'] as String,
          status: fromApiEnum(IntegrityCaseStatus.values, j['status'], IntegrityCaseStatus.underReview),
          openedAt: DateTime.parse(j['openedAt'] as String).toLocal(),
          responseDueAt: j['responseDueAt'] == null ? null : DateTime.parse(j['responseDueAt'] as String).toLocal(),
          response: j['counselorResponse'] as String?,
          decisionReason: j['decisionReason'] as String?,
        );

  @override
  Future<IntegrityCase?> integrityCase() => guard(() async => _case((await _dio.get<Map<String, dynamic>?>('/counselors/me/integrity')).data));

  @override
  Future<IntegrityCase?> respondIntegrity(String id, String response) =>
      guard(() async => _case((await _dio.post<Map<String, dynamic>>('/counselors/me/integrity/$id/respond', data: {'response': response.trim()})).data));

  @override
  Future<Counselor?> myCounselorProfile() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>?>('/counselors/me');
        return r.data == null || r.data!.isEmpty ? null : ApiMappers.counselor(r.data!);
      });

  @override
  Future<ProInsights> myInsights() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/counselors/me/insights');
        return ApiMappers.proInsights(r.data!);
      });

  @override
  Future<String> uploadCredential(List<int> bytes, String mime) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/counselors/me/credentials/upload-url', data: {'mime': mime});
        final key = r.data!['key'] as String;
        final up = Map<String, dynamic>.from(r.data!['upload'] as Map);
        final form = FormData.fromMap({
          ...Map<String, dynamic>.from(up['fields'] as Map),
          'file': MultipartFile.fromBytes(bytes, filename: 'credential', contentType: DioMediaType.parse(mime)),
        });
        await Dio().post<void>(up['url'] as String, data: form); // presigned POST straight to private storage
        return key;
      });

  @override
  Future<Counselor> apply(CounselorApplication a) => guard(() async {
        final r = await _dio.put<Map<String, dynamic>>('/counselors/me', data: {
          'kind': toApiEnum(a.kind),
          'displayName': a.displayName.trim(),
          'headline': a.headline.trim(),
          'bio': a.bio.trim(),
          'yearsExperience': a.yearsExperience,
          'licenseNumber': a.licenseNumber.trim(),
          'licenseAuthority': a.licenseAuthority.trim(),
          'licenseCountry': a.licenseCountry,
          'credentialKeys': a.credentialKeys,
          'languages': a.languages,
          'services': a.services.map(toApiEnum).toList(),
          if (a.gender != null) 'gender': toApiEnum(a.gender!),
          if (a.countryIso != null) 'countryCode': a.countryIso,
          if (a.city != null && a.city!.trim().length >= 2) 'city': a.city!.trim(),
          'acceptPolicy': true,
          'policyVersion': a.policyVersion,
        });
        return ApiMappers.counselor(r.data!);
      });

  @override
  Future<void> saveOffering({required ConsultationService service, required String language, required int durationMinutes, required int priceMinor, required String currency, bool active = true}) =>
      guard(() => _dio.put<void>('/counselors/me/offerings', data: {
            'service': toApiEnum(service),
            'language': language,
            'durationMinutes': durationMinutes,
            'priceMinor': priceMinor,
            'currency': currency,
            'active': active,
          }));

  @override
  Future<List<Consultation>> desk() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/counselors/me/bookings');
        return r.data!.map((j) => ApiMappers.consultation(Map<String, dynamic>.from(j as Map))).toList();
      });

  @override
  Future<String> confirm(String id, DateTime scheduledAt) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/consultations/$id/confirm', data: {'scheduledAt': scheduledAt.toUtc().toIso8601String()});
        return r.data!['conversationId'] as String;
      });

  @override
  Future<void> decline(String id, {String? reason}) => guard(() => _dio.post<void>('/consultations/$id/decline', data: {if (reason != null) 'reason': reason}));

  @override
  Future<void> complete(String id) => guard(() => _dio.post<void>('/consultations/$id/complete'));

  @override
  Future<SlotList> slots(String counselorId, String offeringId) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/counselors/$counselorId/slots', queryParameters: {'offeringId': offeringId});
        final j = r.data!;
        return SlotList(
          scheduled: j['scheduled'] == true,
          timezone: j['timezone'] as String?,
          slots: [for (final x in (j['slots'] as List? ?? const [])) DateTime.parse(x as String).toLocal()],
        );
      });

  CounselorSchedule _schedule(Map<String, dynamic> j) {
    final s = Map<String, dynamic>.from(j['schedule'] as Map);
    return CounselorSchedule(
      settings: ScheduleSettings(
        timezone: s['timezone'] as String? ?? 'Asia/Dubai',
        bufferMinutes: (s['bufferMinutes'] as num?)?.toInt() ?? 10,
        minNoticeHours: (s['minNoticeHours'] as num?)?.toInt() ?? 12,
        maxDaysAhead: (s['maxDaysAhead'] as num?)?.toInt() ?? 30,
        accepting: s['accepting'] != false,
      ),
      windows: [for (final w in (j['windows'] as List? ?? const [])) WeeklyWindow.fromJson(Map<String, dynamic>.from(w as Map))],
      timeOff: [
        for (final t in (j['timeOff'] as List? ?? const []))
          TimeOff(id: t['id'] as String, startsAt: DateTime.parse(t['startsAt'] as String).toLocal(), endsAt: DateTime.parse(t['endsAt'] as String).toLocal(), note: t['note'] as String?),
      ],
    );
  }

  @override
  Future<CounselorSchedule> mySchedule() => guard(() async => _schedule((await _dio.get<Map<String, dynamic>>('/counselors/me/schedule')).data!));
  @override
  Future<CounselorSchedule> saveSchedule(ScheduleSettings s) => guard(() async => _schedule((await _dio.put<Map<String, dynamic>>('/counselors/me/schedule', data: s.toJson())).data!));
  @override
  Future<CounselorSchedule> saveAvailability(List<WeeklyWindow> w) =>
      guard(() async => _schedule((await _dio.put<Map<String, dynamic>>('/counselors/me/availability', data: {'windows': [for (final x in w) x.toJson()]})).data!));
  @override
  Future<void> addTimeOff(DateTime startsAt, DateTime endsAt, {String? note}) => guard(() => _dio.post<void>('/counselors/me/time-off', data: {
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }));
  @override
  Future<void> removeTimeOff(String id) => guard(() => _dio.delete<void>('/counselors/me/time-off/$id'));
  @override
  Future<MyReviews> myReviews() => guard(() async {
        final j = (await _dio.get<Map<String, dynamic>>('/counselors/me/reviews')).data!;
        return MyReviews(
          ratings: RatingBreakdown.fromJson(Map<String, dynamic>.from(j['ratings'] as Map)),
          reviews: [
            for (final r in (j['reviews'] as List? ?? const []))
              CounselorReview(
                consultationId: r['consultationId'] as String,
                rating: (r['rating'] as num).toInt(),
                comment: r['comment'] as String?,
                createdAt: DateTime.parse(r['createdAt'] as String).toLocal(),
                by: r['by'] as String?,
                reply: r['reply'] as String?,
                repliedAt: r['repliedAt'] == null ? null : DateTime.parse(r['repliedAt'] as String).toLocal(),
              ),
          ],
        );
      });
  @override
  Future<void> replyToReview(String id, String reply) => guard(() => _dio.put<void>('/counselors/me/reviews/$id/reply', data: {'reply': reply}));
}

class DemoConsultationsRepository implements ConsultationsRepository {
  DemoConsultationsRepository(this._b);
  final DemoBackend _b;
  @override
  Future<List<Counselor>> counselors(CounselorQuery q) => _b.counselors(q.kind, q.service, q.language, q.durationMinutes);
  @override
  Future<Counselor> counselor(String id) => _b.counselor(id);
  @override
  Future<BookingIntent> book({required String offeringId, String? note, DateTime? preferredTime, DateTime? slot}) => _b.book(offeringId, note);
  @override
  Future<void> pay(BookingIntent intent) => _b.payBooking(intent.consultationId);
  @override
  Future<BookingIntent> retryPayment(String consultationId) => _b.retryPayment(consultationId);
  @override
  Future<List<Consultation>> mine() => _b.myConsultations();
  @override
  Future<void> cancel(String id) => _b.cancelConsultation(id);
  @override
  Future<void> review(String id, ReviewAnswers a) => _b.submitReview(id, a);
  @override
  Future<void> reportNotHappened(String id, String reason) => _b.reportNotHappened(id, reason);
  @override
  Future<List<PendingReview>> pendingReviews() => _b.pendingReviews();
  @override
  Future<IntegrityCase?> integrityCase() => _b.myIntegrityCase();
  @override
  Future<IntegrityCase?> respondIntegrity(String id, String response) => _b.respondIntegrity(id, response);
  @override
  Future<Counselor?> myCounselorProfile() => _b.myCounselor();
  @override
  Future<ProInsights> myInsights() => _b.proInsights();
  @override
  Future<String> uploadCredential(List<int> bytes, String mime) async => 'credentials/demo/${DateTime.now().microsecondsSinceEpoch}';
  @override
  Future<Counselor> apply(CounselorApplication a) => _b.applyCounselor(a.kind, a.displayName, a.headline, a.bio, a.yearsExperience, a.licenseAuthority, a.licenseCountry, a.languages, a.services);
  @override
  Future<void> saveOffering({required ConsultationService service, required String language, required int durationMinutes, required int priceMinor, required String currency, bool active = true}) =>
      _b.saveOffering(service, language, durationMinutes, priceMinor, currency);
  @override
  Future<List<Consultation>> desk() => _b.desk();
  @override
  Future<String> confirm(String id, DateTime scheduledAt) => _b.confirmBooking(id, scheduledAt);
  @override
  Future<void> decline(String id, {String? reason}) => _b.declineBooking(id);
  @override
  Future<void> complete(String id) => _b.completeBooking(id);

  // ── preview schedule (in memory) ──
  CounselorSchedule _sched = const CounselorSchedule(
    settings: ScheduleSettings(),
    windows: [
      WeeklyWindow(weekday: 1, startMinute: 17 * 60, endMinute: 21 * 60),
      WeeklyWindow(weekday: 3, startMinute: 17 * 60, endMinute: 21 * 60),
      WeeklyWindow(weekday: 6, startMinute: 10 * 60, endMinute: 14 * 60),
    ],
    timeOff: [],
  );
  final _replies = <String, (String, DateTime)>{};

  Future<T> _wait<T>(T Function() f) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return f();
  }

  @override
  Future<SlotList> slots(String counselorId, String offeringId) async {
    final c = await _b.counselor(counselorId);
    final o = c.offerings.firstWhere((x) => x.id == offeringId, orElse: () => c.offerings.first);
    return _wait(() => SlotList(
          scheduled: true,
          timezone: _sched.settings.timezone,
          slots: computeLocalSlots(
            windows: _sched.windows,
            busy: const [],
            timeOff: [for (final t in _sched.timeOff) (t.startsAt, t.endsAt)],
            durationMinutes: o.durationMinutes,
            settings: _sched.settings,
            now: DateTime.now(),
          ),
        ));
  }

  @override
  Future<CounselorSchedule> mySchedule() => _wait(() => _sched);
  @override
  Future<CounselorSchedule> saveSchedule(ScheduleSettings s) => _wait(() => _sched = CounselorSchedule(settings: s, windows: _sched.windows, timeOff: _sched.timeOff));
  @override
  Future<CounselorSchedule> saveAvailability(List<WeeklyWindow> w) => _wait(() {
        for (var i = 0; i < w.length; i++) {
          for (var j = i + 1; j < w.length; j++) {
            if (w[i].overlaps(w[j])) throw const ValidationFailure('windows');
          }
        }
        return _sched = CounselorSchedule(settings: _sched.settings, windows: List.of(w), timeOff: _sched.timeOff);
      });
  @override
  Future<void> addTimeOff(DateTime startsAt, DateTime endsAt, {String? note}) => _wait(() {
        if (!endsAt.isAfter(startsAt)) throw const ValidationFailure('endsAt');
        _sched = CounselorSchedule(settings: _sched.settings, windows: _sched.windows, timeOff: [..._sched.timeOff, TimeOff(id: 'to${DateTime.now().microsecondsSinceEpoch}', startsAt: startsAt, endsAt: endsAt, note: note)]);
      });
  @override
  Future<void> removeTimeOff(String id) => _wait(() {
        _sched = CounselorSchedule(settings: _sched.settings, windows: _sched.windows, timeOff: _sched.timeOff.where((t) => t.id != id).toList());
      });
  @override
  Future<MyReviews> myReviews() => _wait(() {
        final now = DateTime.now();
        final ar = _b.lang == 'ar';
        final list = [
          (5, ar ? 'استشارة مفيدة جداً وتنظيم ممتاز للوقت.' : 'Very helpful session, well organised.', 'Sara', 3),
          (4, ar ? 'أسلوب هادئ ومحترم.' : 'Calm and respectful.', 'Omar', 9),
          (5, null, 'Lina', 15),
        ];
        return MyReviews(
          ratings: const RatingBreakdown(count: 3, average: 4.67, quality: 4.7, commitment: 4.3, effectiveness: 4.7, outcome: 4.3, distribution: {5: 2, 4: 1, 3: 0, 2: 0, 1: 0}),
          reviews: [
            for (final (i, r) in list.indexed)
              CounselorReview(consultationId: 'rv$i', rating: r.$1, comment: r.$2, by: r.$3, createdAt: now.subtract(Duration(days: r.$4)), reply: _replies['rv$i']?.$1, repliedAt: _replies['rv$i']?.$2),
          ],
        );
      });
  @override
  Future<void> replyToReview(String id, String reply) => _wait(() => _replies[id] = (reply, DateTime.now()));
}

final consultationsRepositoryProvider = Provider<ConsultationsRepository>(
  (ref) => useApi ? ApiConsultationsRepository(ref.watch(apiClientProvider)) : DemoConsultationsRepository(ref.watch(demoBackendProvider)),
);

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
  Future<BookingIntent> book({required String offeringId, String? note, DateTime? preferredTime}) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/consultations', data: {
          'offeringId': offeringId,
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
  Future<List<Consultation>> mine() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/consultations');
        return r.data!.map((j) => ApiMappers.consultation(Map<String, dynamic>.from(j as Map))).toList();
      });

  @override
  Future<void> cancel(String id) => guard(() => _dio.post<void>('/consultations/$id/cancel'));

  @override
  Future<void> review(String id, ReviewAnswers a) => guard(() => _dio.post<void>('/consultations/$id/review', data: a.toJson()));

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
}

class DemoConsultationsRepository implements ConsultationsRepository {
  DemoConsultationsRepository(this._b);
  final DemoBackend _b;
  @override
  Future<List<Counselor>> counselors(CounselorQuery q) => _b.counselors(q.kind, q.service, q.language, q.durationMinutes);
  @override
  Future<Counselor> counselor(String id) => _b.counselor(id);
  @override
  Future<BookingIntent> book({required String offeringId, String? note, DateTime? preferredTime}) => _b.book(offeringId, note);
  @override
  Future<void> pay(BookingIntent intent) => _b.payBooking(intent.consultationId);
  @override
  Future<List<Consultation>> mine() => _b.myConsultations();
  @override
  Future<void> cancel(String id) => _b.cancelConsultation(id);
  @override
  Future<void> review(String id, ReviewAnswers a) => _b.submitReview(id, a);
  @override
  Future<List<PendingReview>> pendingReviews() => _b.pendingReviews();
  @override
  Future<IntegrityCase?> integrityCase() => _b.myIntegrityCase();
  @override
  Future<IntegrityCase?> respondIntegrity(String id, String response) => _b.respondIntegrity(id, response);
  @override
  Future<Counselor?> myCounselorProfile() => _b.myCounselor();
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
}

final consultationsRepositoryProvider = Provider<ConsultationsRepository>(
  (ref) => useApi ? ApiConsultationsRepository(ref.watch(apiClientProvider)) : DemoConsultationsRepository(ref.watch(demoBackendProvider)),
);

import '../../../shared/models/models.dart';
import 'schedule.dart';

export 'schedule.dart';

/// Filters for the counselor directory (all optional).
class CounselorQuery {
  const CounselorQuery({this.kind, this.service, this.language, this.durationMinutes});
  final CounselorKind? kind;
  final ConsultationService? service;
  final String? language;
  final int? durationMinutes;

  CounselorQuery copyWith({CounselorKind? Function()? kind, ConsultationService? Function()? service, String? Function()? language, int? Function()? durationMinutes}) => CounselorQuery(
        kind: kind != null ? kind() : this.kind,
        service: service != null ? service() : this.service,
        language: language != null ? language() : this.language,
        durationMinutes: durationMinutes != null ? durationMinutes() : this.durationMinutes,
      );

  @override
  bool operator ==(Object other) => other is CounselorQuery && other.kind == kind && other.service == service && other.language == language && other.durationMinutes == durationMinutes;
  @override
  int get hashCode => Object.hash(kind, service, language, durationMinutes);
}

/// Version of the professional policy shown at sign-up (server setting counselor.policyVersion).
const kProfessionalPolicyVersion = '2026-11';

/// What a professional submits to become a counselor (reviewed by moderators).
class CounselorApplication {
  const CounselorApplication({
    required this.kind,
    required this.displayName,
    required this.headline,
    required this.bio,
    required this.yearsExperience,
    required this.licenseNumber,
    required this.licenseAuthority,
    required this.licenseCountry,
    required this.languages,
    required this.services,
    required this.credentialKeys,
    this.gender,
    this.countryIso,
    this.city,
    this.policyVersion = kProfessionalPolicyVersion,
  });

  /// Clients may prefer a counselor of a given gender (from the sign-up gender step).
  final Gender? gender;
  final String? countryIso;
  final String? city;

  /// The professional policy the counselor accepted (15% commission, no
  /// off-platform dealings, fair review, permanent ban for circumvention).
  final String policyVersion;
  final CounselorKind kind;
  final String displayName, headline, bio, licenseNumber, licenseAuthority, licenseCountry;
  final int yearsExperience;
  final List<String> languages;
  final List<ConsultationService> services;
  final List<String> credentialKeys;
}

abstract interface class ConsultationsRepository {
  // client
  Future<List<Counselor>> counselors(CounselorQuery q);
  Future<Counselor> counselor(String id);

  /// Creates the booking (price snapshot) and the payment intent. The
  /// counselor only sees it after the payment succeeds.
  /// [slot]: one of [slots] when the counselor publishes hours; otherwise [preferredTime] is a wish.
  Future<BookingIntent> book({required String offeringId, String? note, DateTime? preferredTime, DateTime? slot});

  /// Bookable times for one offering (from the counselor's weekly hours, time off and bookings).
  Future<SlotList> slots(String counselorId, String offeringId);

  /// Completes payment for [intent] (payment sheet or, outside production, the test gateway).
  Future<void> pay(BookingIntent intent);

  /// A new payment attempt for a booking still waiting for payment (after a
  /// declined card or a closed sheet): same booking, time and note.
  Future<BookingIntent> retryPayment(String consultationId);
  Future<List<Consultation>> mine();
  Future<void> cancel(String consultationId);
  /// Mandatory questionnaire after a completed consultation.
  Future<void> review(String consultationId, ReviewAnswers answers);

  /// "The consultation did not take place": the held fee waits for support (refund or release).
  Future<void> reportNotHappened(String consultationId, String reason);

  /// Completed consultations still waiting for the questionnaire.
  Future<List<PendingReview>> pendingReviews();

  /// The counselor's latest integrity case (null when none).
  Future<IntegrityCase?> integrityCase();
  Future<IntegrityCase?> respondIntegrity(String caseId, String response);

  // counselor
  Future<Counselor?> myCounselorProfile();
  Future<String> uploadCredential(List<int> bytes, String mime);
  Future<Counselor> apply(CounselorApplication a);
  Future<void> saveOffering({required ConsultationService service, required String language, required int durationMinutes, required int priceMinor, required String currency, bool active = true});
  Future<List<Consultation>> desk();
  Future<String> confirm(String consultationId, DateTime scheduledAt); // → conversation id
  Future<void> decline(String consultationId, {String? reason});
  Future<void> complete(String consultationId);

  // counselor schedule + ratings (controlled from the counselor's own account)
  Future<CounselorSchedule> mySchedule();
  Future<CounselorSchedule> saveSchedule(ScheduleSettings s);
  Future<CounselorSchedule> saveAvailability(List<WeeklyWindow> windows);
  Future<void> addTimeOff(DateTime startsAt, DateTime endsAt, {String? note});
  Future<void> removeTimeOff(String id);
  Future<MyReviews> myReviews();
  Future<void> replyToReview(String consultationId, String reply);
}

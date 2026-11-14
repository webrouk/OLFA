import '../../../shared/models/models.dart';

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
  });
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
  Future<BookingIntent> book({required String offeringId, String? note, DateTime? preferredTime});

  /// Completes payment for [intent] (payment sheet or, outside production, the test gateway).
  Future<void> pay(BookingIntent intent);
  Future<List<Consultation>> mine();
  Future<void> cancel(String consultationId);
  Future<void> review(String consultationId, {required int rating, String? comment});

  // counselor
  Future<Counselor?> myCounselorProfile();
  Future<String> uploadCredential(List<int> bytes, String mime);
  Future<Counselor> apply(CounselorApplication a);
  Future<void> saveOffering({required ConsultationService service, required String language, required int durationMinutes, required int priceMinor, required String currency, bool active = true});
  Future<List<Consultation>> desk();
  Future<String> confirm(String consultationId, DateTime scheduledAt); // → conversation id
  Future<void> decline(String consultationId, {String? reason});
  Future<void> complete(String consultationId);
}

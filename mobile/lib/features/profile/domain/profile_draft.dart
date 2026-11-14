import '../../../shared/models/models.dart';

/// Everything collected during profile setup (screens 7–10) and edited later.
class ProfileDraft {
  const ProfileDraft({
    this.gender,
    this.name = '',
    this.birthDate,
    this.countryIso = 'AE',
    this.city = '',
    this.maritalStatus,
    this.education,
    this.occupation = '',
    this.timeline,
    this.bio = '',
    this.interests = const {},
    this.prefAgeMin = 24,
    this.prefAgeMax = 36,
    this.prefSameCountry = false,
    this.prefMarital = const {MaritalStatus.neverMarried},
    this.prefWantsChildren = true,
    this.photoSlots = const [false, false, false, false, false, false],
    this.photoRightsConfirmed = false,
    this.policyAccepted = false,
  });

  static const maxInterests = 8;
  static const minPhotos = 2;
  static const bioMax = 500;

  final Gender? gender;
  final String name;
  final DateTime? birthDate;
  final String countryIso;
  final String city;
  final MaritalStatus? maritalStatus;
  final Education? education;
  final String occupation;
  final MarriageTimeline? timeline;
  final String bio;
  final Set<String> interests;
  final int prefAgeMin;
  final int prefAgeMax;
  final bool prefSameCountry;
  final Set<MaritalStatus> prefMarital;
  final bool? prefWantsChildren; // null = doesn't matter
  final List<bool> photoSlots; // demo: true = slot has a picked image
  final bool photoRightsConfirmed;
  final bool policyAccepted;

  int get photoCount => photoSlots.where((x) => x).length;
  bool get photosReady => photoCount >= minPhotos && photoRightsConfirmed && policyAccepted;

  ProfileDraft copyWith({
    Gender? gender,
    String? name,
    DateTime? birthDate,
    String? countryIso,
    String? city,
    MaritalStatus? maritalStatus,
    Education? education,
    String? occupation,
    MarriageTimeline? timeline,
    String? bio,
    Set<String>? interests,
    int? prefAgeMin,
    int? prefAgeMax,
    bool? prefSameCountry,
    Set<MaritalStatus>? prefMarital,
    bool? Function()? prefWantsChildren,
    List<bool>? photoSlots,
    bool? photoRightsConfirmed,
    bool? policyAccepted,
  }) =>
      ProfileDraft(
        gender: gender ?? this.gender,
        name: name ?? this.name,
        birthDate: birthDate ?? this.birthDate,
        countryIso: countryIso ?? this.countryIso,
        city: city ?? this.city,
        maritalStatus: maritalStatus ?? this.maritalStatus,
        education: education ?? this.education,
        occupation: occupation ?? this.occupation,
        timeline: timeline ?? this.timeline,
        bio: bio ?? this.bio,
        interests: interests ?? this.interests,
        prefAgeMin: prefAgeMin ?? this.prefAgeMin,
        prefAgeMax: prefAgeMax ?? this.prefAgeMax,
        prefSameCountry: prefSameCountry ?? this.prefSameCountry,
        prefMarital: prefMarital ?? this.prefMarital,
        prefWantsChildren: prefWantsChildren != null ? prefWantsChildren() : this.prefWantsChildren,
        photoSlots: photoSlots ?? this.photoSlots,
        photoRightsConfirmed: photoRightsConfirmed ?? this.photoRightsConfirmed,
        policyAccepted: policyAccepted ?? this.policyAccepted,
      );

  factory ProfileDraft.fromProfile(UserProfile p) => ProfileDraft(
        gender: p.gender,
        name: p.name,
        countryIso: p.countryIso,
        city: p.city,
        maritalStatus: p.maritalStatus,
        education: p.education,
        occupation: p.occupation,
        timeline: p.timeline,
        bio: p.bio,
        interests: p.interests.toSet(),
        photoSlots: [for (var i = 0; i < 6; i++) i < p.photos.length],
        photoRightsConfirmed: true,
        policyAccepted: true,
      );
}

/// Field validators return an error key (mapped to l10n) or null.
abstract final class ProfileValidators {
  static String? name(String v) {
    final t = v.trim();
    if (t.isEmpty) return 'required';
    if (t.length < 2 || t.length > 40) return 'nameLength';
    if (RegExp(r'[0-9@#$%^&*()_+=<>/\\|{}\[\]]').hasMatch(t)) return 'nameChars';
    return null;
  }

  static String? required(Object? v) => (v == null || (v is String && v.trim().isEmpty)) ? 'required' : null;

  static String? bio(String v) {
    if (v.trim().length < 20) return 'bioShort';
    if (v.length > ProfileDraft.bioMax) return 'bioLong';
    // Contact details in bios are not allowed (anti-spam, safety).
    if (RegExp(r'(\+?\d[\d\s]{7,})|@|https?://|www\.').hasMatch(v)) return 'bioContact';
    return null;
  }
}

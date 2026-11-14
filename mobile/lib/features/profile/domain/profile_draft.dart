import '../../../shared/models/models.dart';

/// Everything collected during profile setup (screens 7–10) and edited later.
class ProfileDraft {
  const ProfileDraft({
    this.gender,
    this.name = '',
    this.birthDate,
    this.countryIso = 'AE',
    this.nationality = 'AE',
    this.nationalityEdited = false,
    this.city = '',
    this.maritalStatus,
    this.education,
    this.occupation = '',
    this.heightCm,
    this.weightKg,
    this.timeline,
    this.bio = '',
    this.interests = const {},
    this.prefAgeMin = 24,
    this.prefAgeMax = 36,
    this.prefSameCountry = false,
    this.prefMarital = const {MaritalStatus.neverMarried},
    this.prefWantsChildren = true,
    this.photoSlots = const [false, false, false, false, false, false],
    this.photoIds = const [null, null, null, null, null, null],
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

  /// Independent of the residence country; follows it until the user picks one.
  final String? nationality;
  final bool nationalityEdited;
  final String city;
  final MaritalStatus? maritalStatus;
  final Education? education;
  final String occupation;
  final int? heightCm;
  final int? weightKg;
  final MarriageTimeline? timeline;
  final String bio;
  final Set<String> interests;
  final int prefAgeMin;
  final int prefAgeMax;
  final bool prefSameCountry;
  final Set<MaritalStatus> prefMarital;
  final bool? prefWantsChildren; // null = doesn't matter
  final List<bool> photoSlots; // true = slot holds an uploaded photo
  final List<String?> photoIds; // server photo ids (API mode)
  final bool photoRightsConfirmed;
  final bool policyAccepted;

  /// Selecting a residence country picks its nationality — unless the user changed it.
  ProfileDraft withCountry(String iso) => copyWith(countryIso: iso, nationality: nationalityEdited ? nationality : countryOrNull(iso)?.nationality);

  int get photoCount => photoSlots.where((x) => x).length;
  bool get photosReady => photoCount >= minPhotos && photoRightsConfirmed && policyAccepted;

  ProfileDraft copyWith({
    Gender? gender,
    String? name,
    DateTime? birthDate,
    String? countryIso,
    String? nationality,
    bool? nationalityEdited,
    String? city,
    MaritalStatus? maritalStatus,
    Education? education,
    String? occupation,
    int? Function()? heightCm,
    int? Function()? weightKg,
    MarriageTimeline? timeline,
    String? bio,
    Set<String>? interests,
    int? prefAgeMin,
    int? prefAgeMax,
    bool? prefSameCountry,
    Set<MaritalStatus>? prefMarital,
    bool? Function()? prefWantsChildren,
    List<bool>? photoSlots,
    List<String?>? photoIds,
    bool? photoRightsConfirmed,
    bool? policyAccepted,
  }) =>
      ProfileDraft(
        gender: gender ?? this.gender,
        name: name ?? this.name,
        birthDate: birthDate ?? this.birthDate,
        countryIso: countryIso ?? this.countryIso,
        nationality: nationality ?? this.nationality,
        nationalityEdited: nationalityEdited ?? this.nationalityEdited,
        city: city ?? this.city,
        maritalStatus: maritalStatus ?? this.maritalStatus,
        education: education ?? this.education,
        occupation: occupation ?? this.occupation,
        heightCm: heightCm != null ? heightCm() : this.heightCm,
        weightKg: weightKg != null ? weightKg() : this.weightKg,
        timeline: timeline ?? this.timeline,
        bio: bio ?? this.bio,
        interests: interests ?? this.interests,
        prefAgeMin: prefAgeMin ?? this.prefAgeMin,
        prefAgeMax: prefAgeMax ?? this.prefAgeMax,
        prefSameCountry: prefSameCountry ?? this.prefSameCountry,
        prefMarital: prefMarital ?? this.prefMarital,
        prefWantsChildren: prefWantsChildren != null ? prefWantsChildren() : this.prefWantsChildren,
        photoSlots: photoSlots ?? this.photoSlots,
        photoIds: photoIds ?? this.photoIds,
        photoRightsConfirmed: photoRightsConfirmed ?? this.photoRightsConfirmed,
        policyAccepted: policyAccepted ?? this.policyAccepted,
      );

  factory ProfileDraft.fromProfile(UserProfile p) => ProfileDraft(
        gender: p.gender,
        name: p.name,
        countryIso: p.countryIso,
        nationality: p.nationality ?? countryOrNull(p.countryIso)?.nationality,
        nationalityEdited: p.nationality != null && p.nationality != countryOrNull(p.countryIso)?.nationality,
        city: p.city,
        maritalStatus: p.maritalStatus,
        education: p.education,
        occupation: p.occupation,
        heightCm: p.heightCm,
        weightKg: p.weightKg,
        timeline: p.timeline,
        bio: p.bio,
        interests: p.interests.toSet(),
        photoSlots: [for (var i = 0; i < 6; i++) i < p.photos.length],
        photoIds: [for (var i = 0; i < 6; i++) i < p.photos.length ? p.photos[i].id : null],
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

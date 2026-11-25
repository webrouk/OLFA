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
    this.accountType,
    this.religion,
    this.sect,
    this.religionConsent = false,
    this.prefReligions = const {},
    this.prefSects = const {},
  });

  /// Chosen on the step after gender; decides the rest of the sign-up flow.
  final AccountType? accountType;

  /// Religion key (shared/reference/religions.tsv), its sect, and the explicit
  /// consent to store it ("undisclosed" needs none).
  final String? religion;
  final String? sect;
  final bool religionConsent;

  /// Partner preference: accepted religions and "religion.sect" keys (empty = any).
  final Set<String> prefReligions;
  final Set<String> prefSects;

  bool get religionValid => religion != null && (religion == 'undisclosed' || religionConsent);

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

  /// Professionals need one clear professional photo.
  bool get professionalPhotosReady => photoCount >= 1 && photoRightsConfirmed && policyAccepted;

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
    AccountType? accountType,
    String? Function()? religion,
    String? Function()? sect,
    bool? religionConsent,
    Set<String>? prefReligions,
    Set<String>? prefSects,
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
        accountType: accountType ?? this.accountType,
        religion: religion != null ? religion() : this.religion,
        sect: sect != null ? sect() : this.sect,
        religionConsent: religionConsent ?? this.religionConsent,
        prefReligions: prefReligions ?? this.prefReligions,
        prefSects: prefSects ?? this.prefSects,
      );

  /// Changing the religion clears a sect that does not belong to it.
  ProfileDraft withReligion(String? key) => copyWith(religion: () => key, sect: () => sect != null && key != null && sectOf(key, sect) != null ? sect : null);

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
        accountType: AccountType.member,
        religion: p.religion ?? 'undisclosed',
        sect: p.sect,
        religionConsent: p.religion != null,
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

/// Sign-up progress kept on the device (encrypted, see [SecureStore]) so a
/// member who leaves the app half-way — or whose phone closes it — finds every
/// answer where they left it. Uploaded photos live on the server; only their
/// ids are kept here. Cleared once the profile is submitted or on sign-out.
abstract final class ProfileDraftCodec {
  static const version = 1;

  static Map<String, Object?> encode(ProfileDraft d) => {
        'v': version,
        'gender': d.gender?.name,
        'name': d.name,
        'birthDate': d.birthDate?.toIso8601String(),
        'countryIso': d.countryIso,
        'nationality': d.nationality,
        'nationalityEdited': d.nationalityEdited,
        'city': d.city,
        'maritalStatus': d.maritalStatus?.name,
        'education': d.education?.name,
        'occupation': d.occupation,
        'heightCm': d.heightCm,
        'weightKg': d.weightKg,
        'timeline': d.timeline?.name,
        'bio': d.bio,
        'interests': d.interests.toList(),
        'prefAgeMin': d.prefAgeMin,
        'prefAgeMax': d.prefAgeMax,
        'prefSameCountry': d.prefSameCountry,
        'prefMarital': d.prefMarital.map((m) => m.name).toList(),
        'prefWantsChildren': d.prefWantsChildren,
        'photoSlots': d.photoSlots,
        'photoIds': d.photoIds,
        'photoRightsConfirmed': d.photoRightsConfirmed,
        'policyAccepted': d.policyAccepted,
        'accountType': d.accountType?.name,
        'religion': d.religion,
        'sect': d.sect,
        'religionConsent': d.religionConsent,
        'prefReligions': d.prefReligions.toList(),
        'prefSects': d.prefSects.toList(),
      };

  /// Unknown or damaged data → null (start fresh rather than crash).
  static ProfileDraft? decode(Map<String, Object?> j) {
    try {
      if (j['v'] != version) return null;
      T? en<T extends Enum>(List<T> values, Object? v) => v is String ? values.where((e) => e.name == v).firstOrNull : null;
      List<T> list<T>(Object? v) => v is List ? v.whereType<T>().toList() : <T>[];
      final slots = list<bool>(j['photoSlots']);
      final ids = j['photoIds'] is List ? (j['photoIds'] as List).map((x) => x is String ? x : null).toList() : <String?>[];
      return ProfileDraft(
        gender: en(Gender.values, j['gender']),
        name: j['name'] as String? ?? '',
        birthDate: j['birthDate'] is String ? DateTime.tryParse(j['birthDate'] as String) : null,
        countryIso: j['countryIso'] as String? ?? 'AE',
        nationality: j['nationality'] as String?,
        nationalityEdited: j['nationalityEdited'] == true,
        city: j['city'] as String? ?? '',
        maritalStatus: en(MaritalStatus.values, j['maritalStatus']),
        education: en(Education.values, j['education']),
        occupation: j['occupation'] as String? ?? '',
        heightCm: (j['heightCm'] as num?)?.toInt(),
        weightKg: (j['weightKg'] as num?)?.toInt(),
        timeline: en(MarriageTimeline.values, j['timeline']),
        bio: j['bio'] as String? ?? '',
        interests: list<String>(j['interests']).toSet(),
        prefAgeMin: (j['prefAgeMin'] as num?)?.toInt() ?? 24,
        prefAgeMax: (j['prefAgeMax'] as num?)?.toInt() ?? 36,
        prefSameCountry: j['prefSameCountry'] == true,
        prefMarital: _nonEmpty(list<String>(j['prefMarital']).map((m) => en(MaritalStatus.values, m)).whereType<MaritalStatus>().toSet()),
        prefWantsChildren: j['prefWantsChildren'] as bool?,
        photoSlots: slots.length == 6 ? slots : const [false, false, false, false, false, false],
        photoIds: ids.length == 6 ? ids : const [null, null, null, null, null, null],
        photoRightsConfirmed: j['photoRightsConfirmed'] == true,
        policyAccepted: j['policyAccepted'] == true,
        accountType: en(AccountType.values, j['accountType']),
        religion: j['religion'] as String?,
        sect: j['sect'] as String?,
        religionConsent: j['religionConsent'] == true,
        prefReligions: list<String>(j['prefReligions']).toSet(),
        prefSects: list<String>(j['prefSects']).toSet(),
      );
    } catch (_) {
      return null;
    }
  }

  static Set<MaritalStatus> _nonEmpty(Set<MaritalStatus> s) => s.isEmpty ? const {MaritalStatus.neverMarried} : s;
}

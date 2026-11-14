// Shared domain models. Plain immutable Dart classes with JSON mapping so the
// data layer can swap the demo data source for the REST API without touching
// presentation code.

export '../reference/reference_data.dart';

enum Gender { male, female }

enum MaritalStatus { neverMarried, divorced, widowed }

enum Education { highSchool, diploma, bachelor, master, doctorate }

enum MarriageTimeline { within6Months, within1Year, within2Years, notSure }

enum VerificationStatus { pending, rejected, approved }

enum PlanCode { free, plus, premium }

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);

class Interest {
  const Interest(this.key, this.ar, this.en, {this.basic = true});
  final String key;
  final String ar;
  final String en;
  final bool basic; // usable in free filters

  String label(String lang) => lang == 'ar' ? ar : en;
}

const kInterests = <Interest>[
  Interest('reading', 'القراءة', 'Reading'),
  Interest('travel', 'السفر', 'Travel'),
  Interest('cooking', 'الطبخ', 'Cooking'),
  Interest('fitness', 'الرياضة', 'Fitness'),
  Interest('nature', 'الطبيعة', 'Nature'),
  Interest('volunteering', 'العمل التطوعي', 'Volunteering', basic: false),
  Interest('technology', 'التقنية', 'Technology', basic: false),
  Interest('languages', 'اللغات', 'Languages', basic: false),
  Interest('arts', 'الفنون', 'Arts', basic: false),
  Interest('photography', 'التصوير', 'Photography', basic: false),
  Interest('family', 'الأسرة', 'Family time', basic: false),
  Interest('hiking', 'المشي', 'Hiking', basic: false),
];

Interest? interestByKey(String key) {
  for (final i in kInterests) {
    if (i.key == key) return i;
  }
  return null;
}

class ProfilePhoto {
  const ProfilePhoto({required this.id, this.thumbUrl, this.cardUrl, this.fullUrl});
  final String id;
  final String? thumbUrl; // 200px
  final String? cardUrl; // 800px — used in discovery, never the original
  final String? fullUrl; // 1600px — used in the full-screen gallery only

  factory ProfilePhoto.fromJson(Map<String, dynamic> j) => ProfilePhoto(
        id: j['id'] as String,
        thumbUrl: (j['variants'] as Map?)?['thumb'] as String?,
        cardUrl: (j['variants'] as Map?)?['card'] as String?,
        fullUrl: (j['variants'] as Map?)?['full'] as String?,
      );
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.countryIso,
    required this.city,
    required this.maritalStatus,
    required this.education,
    required this.occupation,
    required this.timeline,
    required this.bio,
    required this.interests,
    required this.photos,
    this.photosReviewed = false,
    this.livenessVerified = false,
    this.identityVerified = false,
    this.compatibility = 0,
    this.completeness = 0,
    this.showLocation = true,
    this.online = false,
  });

  final String id;
  final String name;
  final int age;
  final Gender gender;
  final String countryIso;
  final String city;
  final MaritalStatus maritalStatus;
  final Education education;
  final String occupation;
  final MarriageTimeline timeline;
  final String bio;
  final List<String> interests;
  final List<ProfilePhoto> photos;
  final bool photosReviewed;
  final bool livenessVerified;
  final bool identityVerified;
  final int compatibility;
  final int completeness;
  final bool showLocation;
  final bool online;

  ProfilePhoto? get mainPhoto => photos.isEmpty ? null : photos.first;

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String,
        name: j['displayName'] as String,
        age: j['age'] as int,
        gender: _enum(Gender.values, j['gender'], Gender.male),
        countryIso: j['countryCode'] as String,
        city: j['city'] as String? ?? '',
        maritalStatus: _enum(MaritalStatus.values, j['maritalStatus'], MaritalStatus.neverMarried),
        education: _enum(Education.values, j['education'], Education.bachelor),
        occupation: j['occupation'] as String? ?? '',
        timeline: _enum(MarriageTimeline.values, j['marriageTimeline'], MarriageTimeline.notSure),
        bio: j['bio'] as String? ?? '',
        interests: (j['interests'] as List? ?? const []).cast<String>(),
        photos: (j['photos'] as List? ?? const [])
            .map((p) => ProfilePhoto.fromJson(p as Map<String, dynamic>))
            .toList(),
        photosReviewed: j['isPhotosReviewed'] as bool? ?? false,
        livenessVerified: j['isLivenessVerified'] as bool? ?? false,
        identityVerified: j['isIdentityVerified'] as bool? ?? false,
        compatibility: j['compatibility'] as int? ?? 0,
        completeness: j['completeness'] as int? ?? 0,
        showLocation: j['showLocation'] as bool? ?? true,
      );
}

/// Feature entitlements as returned by the backend. The UI reads these to
/// decide what to show; the server enforces them independently.
class Entitlements {
  const Entitlements({
    required this.plan,
    required this.dailyLikes,
    required this.likesUsed,
    required this.dailyMessages,
    required this.messagesUsed,
    required this.dailyUndos,
    required this.undosUsed,
    required this.advancedFilters,
    required this.seeWhoLikedYou,
    required this.incognito,
    this.resetsAt,
  });

  /// When today's quotas renew (server computes it in UTC; render in local time).
  final DateTime? resetsAt;
  final PlanCode plan;
  final int dailyLikes;
  final int likesUsed;
  final int dailyMessages; // credits to START new conversations
  final int messagesUsed;
  final int dailyUndos;
  final int undosUsed;
  final bool advancedFilters;
  final bool seeWhoLikedYou;
  final bool incognito;

  int get likesLeft => (dailyLikes - likesUsed).clamp(0, dailyLikes);
  int get messagesLeft => (dailyMessages - messagesUsed).clamp(0, dailyMessages);
  int get undosLeft => (dailyUndos - undosUsed).clamp(0, dailyUndos);

  Entitlements copyWith({int? likesUsed, int? messagesUsed, int? undosUsed}) => Entitlements(
        plan: plan,
        dailyLikes: dailyLikes,
        likesUsed: likesUsed ?? this.likesUsed,
        dailyMessages: dailyMessages,
        messagesUsed: messagesUsed ?? this.messagesUsed,
        dailyUndos: dailyUndos,
        undosUsed: undosUsed ?? this.undosUsed,
        advancedFilters: advancedFilters,
        seeWhoLikedYou: seeWhoLikedYou,
        incognito: incognito,
        resetsAt: resetsAt,
      );
}

class PlanInfo {
  const PlanInfo({
    required this.code,
    required this.dailyLikes,
    required this.dailyMessages,
    required this.dailyUndos,
    required this.advancedFilters,
    required this.seeWhoLikedYou,
    required this.priorityVisibility,
    this.storeProductId,
    this.localizedPrice,
  });
  final PlanCode code;
  final int dailyLikes;
  final int dailyMessages;
  final int dailyUndos;
  final bool advancedFilters;
  final bool seeWhoLikedYou;
  final bool priorityVisibility;
  final String? storeProductId;
  final String? localizedPrice; // from StoreKit / Play Billing, never hard-coded
}

class DiscoverFilters {
  const DiscoverFilters({
    this.ageMin = 22,
    this.ageMax = 38,
    this.countryIso,
    this.city = '',
    this.interests = const {},
    this.maritalStatuses = const {},
    this.educations = const {},
    this.profession = '',
    this.minCompatibility,
  });

  final int ageMin;
  final int ageMax;
  final String? countryIso; // null = any
  final String city;
  final Set<String> interests;
  final Set<MaritalStatus> maritalStatuses; // paid
  final Set<Education> educations; // paid
  final String profession; // paid
  final int? minCompatibility; // paid

  bool get usesPaidFilters =>
      maritalStatuses.isNotEmpty ||
      educations.isNotEmpty ||
      profession.isNotEmpty ||
      minCompatibility != null ||
      interests.length > 1 ||
      interests.any((k) => interestByKey(k)?.basic == false);

  DiscoverFilters copyWith({
    int? ageMin,
    int? ageMax,
    String? Function()? countryIso,
    String? city,
    Set<String>? interests,
    Set<MaritalStatus>? maritalStatuses,
    Set<Education>? educations,
    String? profession,
    int? Function()? minCompatibility,
  }) =>
      DiscoverFilters(
        ageMin: ageMin ?? this.ageMin,
        ageMax: ageMax ?? this.ageMax,
        countryIso: countryIso != null ? countryIso() : this.countryIso,
        city: city ?? this.city,
        interests: interests ?? this.interests,
        maritalStatuses: maritalStatuses ?? this.maritalStatuses,
        educations: educations ?? this.educations,
        profession: profession ?? this.profession,
        minCompatibility: minCompatibility != null ? minCompatibility() : this.minCompatibility,
      );

  Map<String, dynamic> toQuery() => {
        'ageMin': ageMin,
        'ageMax': ageMax,
        if (countryIso != null) 'country': countryIso,
        if (city.isNotEmpty) 'city': city,
        if (interests.isNotEmpty) 'interests': interests.join(','),
        if (maritalStatuses.isNotEmpty) 'marital': maritalStatuses.map((e) => e.name).join(','),
        if (educations.isNotEmpty) 'education': educations.map((e) => e.name).join(','),
        if (profession.isNotEmpty) 'profession': profession,
        if (minCompatibility != null) 'minCompatibility': minCompatibility,
      };
}

class MatchItem {
  const MatchItem({required this.id, required this.peer, required this.createdAt, this.conversationId, this.isNew = false});
  final String id;
  final UserProfile peer;
  final DateTime createdAt;
  final String? conversationId; // null until someone spends a start-credit
  final bool isNew;
}

enum MessageStatus { sending, sent, delivered, read, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.clientId,
    required this.conversationId,
    required this.fromMe,
    required this.body,
    required this.sentAt,
    required this.status,
  });
  final String id;
  final String clientId; // idempotency key
  final String conversationId;
  final bool fromMe;
  final String body;
  final DateTime sentAt;
  final MessageStatus status;

  ChatMessage copyWith({String? id, MessageStatus? status}) => ChatMessage(
        id: id ?? this.id,
        clientId: clientId,
        conversationId: conversationId,
        fromMe: fromMe,
        body: body,
        sentAt: sentAt,
        status: status ?? this.status,
      );
}

class Conversation {
  const Conversation({required this.id, required this.peer, this.lastMessage, this.lastAt, this.unread = 0});
  final String id;
  final UserProfile peer;
  final String? lastMessage;
  final DateTime? lastAt;
  final int unread;
}

enum NotificationKind { match, like, verification, message, reminder }

class AppNotification {
  const AppNotification({required this.id, required this.kind, required this.title, required this.createdAt, this.read = false});
  final String id;
  final NotificationKind kind;
  final String title; // rendered server-side in the user's locale
  final DateTime createdAt;
  final bool read;
}

enum PaymentStatus { succeeded, refunded, failed }

class PaymentRecord {
  const PaymentRecord({required this.id, required this.plan, required this.store, required this.date, required this.status, this.amountLabel});
  final String id;
  final PlanCode plan;
  final String store;
  final DateTime date;
  final PaymentStatus status;
  final String? amountLabel;
}

class FaqEntry {
  const FaqEntry({required this.id, required this.category, required this.question, required this.answer});
  final String id;
  final String category;
  final String question;
  final String answer;
}

class VerificationInfo {
  const VerificationInfo({required this.status, this.reason, this.fixSteps = const []});
  final VerificationStatus status;
  final String? reason;
  final List<String> fixSteps;
}

class PrivacySettings {
  const PrivacySettings({
    this.showCity = true,
    this.blurPhotosUntilMatch = false,
    this.showOnline = true,
    this.readReceipts = true,
    this.incognito = false,
  });
  final bool showCity;
  final bool blurPhotosUntilMatch;
  final bool showOnline;
  final bool readReceipts;
  final bool incognito;

  PrivacySettings copyWith({bool? showCity, bool? blurPhotosUntilMatch, bool? showOnline, bool? readReceipts, bool? incognito}) =>
      PrivacySettings(
        showCity: showCity ?? this.showCity,
        blurPhotosUntilMatch: blurPhotosUntilMatch ?? this.blurPhotosUntilMatch,
        showOnline: showOnline ?? this.showOnline,
        readReceipts: readReceipts ?? this.readReceipts,
        incognito: incognito ?? this.incognito,
      );
}

/// Realtime chat event (WebSocket in production).
class ChatEvent {
  const ChatEvent._(this.conversationId, {this.message, this.typing, this.readClientId});
  factory ChatEvent.newMessage(ChatMessage m) => ChatEvent._(m.conversationId, message: m);
  factory ChatEvent.typingChanged(String convId, bool on) => ChatEvent._(convId, typing: on);
  factory ChatEvent.readReceipt(String convId, String clientId) => ChatEvent._(convId, readClientId: clientId);

  final String conversationId;
  final ChatMessage? message;
  final bool? typing;
  final String? readClientId;
}

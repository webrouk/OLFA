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

/// Chosen once during sign-up. Members look for marriage; professionals
/// (psychologist / family counselor) get the counselor workspace and never
/// appear in discovery. The server enforces it on every route.
enum AccountType {
  member,
  psychologist,
  familyCounselor;

  bool get isProfessional => this != member;
  String get api => switch (this) { member => 'MEMBER', psychologist => 'PSYCHOLOGIST', familyCounselor => 'FAMILY_COUNSELOR' };
  static AccountType? fromApi(String? s) => switch (s) { 'MEMBER' => member, 'PSYCHOLOGIST' => psychologist, 'FAMILY_COUNSELOR' => familyCounselor, _ => null };
}

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
    this.nationality,
    this.distanceKm,
    this.photosBlurred = false,
    this.heightCm,
    this.weightKg,
    this.underReview = false,
    this.religion,
    this.sect,
  });

  /// Keys from shared/reference/religions.tsv; null when not shared ("prefer not to say").
  final String? religion;
  final String? sect;

  /// New account awaiting moderation: shown with basics only.
  final bool underReview;

  /// The owner shows photos only after a match (server sends blurred copies).
  final bool photosBlurred;

  /// Optional; shown on the profile and usable as filters.
  final int? heightCm;
  final int? weightKg;

  /// ISO code of the nationality (independent of the residence country).
  final String? nationality;

  /// Rounded distance from the viewer (≥1 km); null when hidden or unknown.
  final int? distanceKm;

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
    this.searchOutsideCountry = false,
    this.visibleConversations = 5,
    this.monthlyCompliments = 0,
    this.complimentsUsed = 0,
    this.complimentsResetAt,
    this.accountActive = true,
  });

  /// Compliments (a message sent with a like) per calendar month: Free 3, Plus 10, Premium 20.
  final int monthlyCompliments;
  final int complimentsUsed;
  final DateTime? complimentsResetAt;
  int get complimentsLeft => (monthlyCompliments - complimentsUsed).clamp(0, monthlyCompliments);

  /// False while the profile awaits review: discovery is read-only.
  final bool accountActive;

  /// Discovery beyond the user's current country (Plus / Premium).
  final bool searchOutsideCountry;

  /// Inbox + archive conversations shown; -1 = unlimited.
  final int visibleConversations;

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

  Entitlements copyWith({int? likesUsed, int? messagesUsed, int? undosUsed, int? complimentsUsed}) => Entitlements(
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
        searchOutsideCountry: searchOutsideCountry,
        visibleConversations: visibleConversations,
        monthlyCompliments: monthlyCompliments,
        complimentsUsed: complimentsUsed ?? this.complimentsUsed,
        complimentsResetAt: complimentsResetAt,
        accountActive: accountActive,
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

/// One store product from the server's catalogue (`GET /subscriptions/products`).
class StoreProductRef {
  const StoreProductRef({required this.plan, required this.provider, required this.productId});
  final PlanCode plan;
  final String provider; // APPLE | GOOGLE
  final String productId;
}

/// Where discovery looks. Nearest first is always the order; outside the
/// user's current country requires Plus or Premium (enforced by the server).
enum DiscoveryScope { nearby, myCountry, otherCountry }

class DiscoverFilters {
  const DiscoverFilters({
    this.scope = DiscoveryScope.nearby,
    this.nationality,
    this.ageMin = 22,
    this.ageMax = 38,
    this.countryIso,
    this.city = '',
    this.interests = const {},
    this.maritalStatuses = const {},
    this.educations = const {},
    this.profession = '',
    this.minCompatibility,
    this.height,
    this.weight,
    this.religions = const {},
    this.sects = const {},
  });

  /// Free for every plan. Sects are "religion.sect" and narrow only their own religion.
  final Set<String> religions;
  final Set<String> sects;

  /// Inclusive ranges; null = any. Members who left the value empty are not shown when a range is set.
  final (int, int)? height; // cm
  final (int, int)? weight; // kg

  final int ageMin;
  final int ageMax;
  final DiscoveryScope scope;
  final String? countryIso; // set for myCountry / otherCountry
  final String? nationality; // paid
  final String city;
  final Set<String> interests;
  final Set<MaritalStatus> maritalStatuses; // paid
  final Set<Education> educations; // paid
  final String profession; // paid · occupation key
  final int? minCompatibility; // paid

  bool get usesPaidFilters =>
      maritalStatuses.isNotEmpty ||
      nationality != null ||
      educations.isNotEmpty ||
      profession.isNotEmpty ||
      minCompatibility != null ||
      interests.length > 1 ||
      interests.any((k) => interestByKey(k)?.basic == false);

  DiscoverFilters copyWith({
    DiscoveryScope? scope,
    String? Function()? nationality,
    int? ageMin,
    int? ageMax,
    String? Function()? countryIso,
    String? city,
    Set<String>? interests,
    Set<MaritalStatus>? maritalStatuses,
    Set<Education>? educations,
    String? profession,
    int? Function()? minCompatibility,
    (int, int)? Function()? height,
    (int, int)? Function()? weight,
    Set<String>? religions,
    Set<String>? sects,
  }) =>
      DiscoverFilters(
        scope: scope ?? this.scope,
        nationality: nationality != null ? nationality() : this.nationality,
        ageMin: ageMin ?? this.ageMin,
        ageMax: ageMax ?? this.ageMax,
        countryIso: countryIso != null ? countryIso() : this.countryIso,
        city: city ?? this.city,
        interests: interests ?? this.interests,
        maritalStatuses: maritalStatuses ?? this.maritalStatuses,
        educations: educations ?? this.educations,
        profession: profession ?? this.profession,
        minCompatibility: minCompatibility != null ? minCompatibility() : this.minCompatibility,
        height: height != null ? height() : this.height,
        weight: weight != null ? weight() : this.weight,
        religions: religions ?? this.religions,
        sects: sects ?? this.sects,
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

/// One like received; compliments carry their message and arrive first.
class ReceivedLike {
  const ReceivedLike({required this.profile, required this.at, this.compliment});
  final UserProfile profile;
  final DateTime at;
  final String? compliment;
}

class LikesInbox {
  const LikesInbox({required this.count, required this.compliments, required this.items, required this.locked, this.nextCursor});
  final int count;

  /// Always visible with the sender, whatever the plan.
  final List<ReceivedLike> compliments;

  /// Empty when [locked] (Free: count only).
  final List<ReceivedLike> items;
  final bool locked;
  final String? nextCursor;
}

class MatchItem {
  const MatchItem({required this.id, required this.peer, required this.createdAt, this.conversationId, this.isNew = false, this.paused = false});

  /// The other person froze their account (taking a break).
  final bool paused;
  final String id;
  final UserProfile peer;
  final DateTime createdAt;
  final String? conversationId; // null until someone spends a start-credit
  final bool isNew;
}

enum MessageStatus { sending, sent, delivered, read, failed }

enum MessageKind { text, image, voice }

/// A photo or voice note. [url] is short-lived and signed (private storage);
/// [localPath] is set while the sender's copy is still uploading.
class ChatAttachment {
  const ChatAttachment({required this.kind, this.id, this.url, this.localPath, this.width, this.height, this.durationMs, this.waveform = const []});
  final MessageKind kind;
  final String? id;
  final String? url;
  final String? localPath;
  final int? width;
  final int? height;
  final int? durationMs;
  final List<int> waveform; // 0–100 peaks for the voice bubble
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.clientId,
    required this.conversationId,
    required this.fromMe,
    required this.body,
    required this.sentAt,
    required this.status,
    this.kind = MessageKind.text,
    this.attachments = const [],
    this.containsPhone = false,
  });
  final String id;
  final String clientId; // idempotency key
  final String conversationId;
  final bool fromMe;
  final String body; // text, or the caption of photos
  final DateTime sentAt;
  final MessageStatus status;
  final MessageKind kind;
  final List<ChatAttachment> attachments;

  /// Set by the server when the text looks like a phone number — both people see a safety note.
  final bool containsPhone;

  ChatMessage copyWith({String? id, MessageStatus? status, List<ChatAttachment>? attachments}) => ChatMessage(
        id: id ?? this.id,
        clientId: clientId,
        conversationId: conversationId,
        fromMe: fromMe,
        body: body,
        sentAt: sentAt,
        status: status ?? this.status,
        kind: kind,
        attachments: attachments ?? this.attachments,
        containsPhone: containsPhone,
      );
}

/// What the composer hands to the repository: text, up to 3 photos, or one voice note.
class OutgoingMedia {
  const OutgoingMedia.photos(this.files) : voice = null;
  const OutgoingMedia.voice(VoiceClip this.voice) : files = const [];
  final List<PreparedPhoto> files;
  final VoiceClip? voice;
  bool get isVoice => voice != null;
}

/// A photo already compressed on the device (≤ 2048 px, high-quality JPEG).
class PreparedPhoto {
  const PreparedPhoto({required this.path, required this.bytes, required this.width, required this.height});
  final String path;
  final List<int> bytes;
  final int width;
  final int height;
}

/// A recorded voice note (AAC-LC, 48 kHz mono, ≤ 60 s).
class VoiceClip {
  const VoiceClip({required this.path, required this.bytes, required this.durationMs, required this.waveform});
  final String path;
  final List<int> bytes;
  final int durationMs;
  final List<int> waveform;
}

/// Result of the messages search field: matching names and matching messages.
class ChatSearchResult {
  const ChatSearchResult({required this.conversationIds, required this.messages});
  final List<String> conversationIds;
  final List<ChatMessage> messages;
  static const empty = ChatSearchResult(conversationIds: [], messages: []);
}

/// Where a conversation is listed. Inbox and archive share the plan's
/// visible-conversation limit; unmatched and consultation chats do not.
enum ConversationSection { inbox, archive, unmatched, consultation }

enum RematchStatus { pending, accepted, declined }

/// The single re-match request a conversation may ever carry.
class RematchInfo {
  const RematchInfo({required this.status, required this.byMe});
  final RematchStatus status;
  final bool byMe;
}

/// The counselor side of a consultation chat.
class CounselorChatInfo {
  const CounselorChatInfo({required this.consultationId, required this.name, this.status, this.scheduledAt});
  final String consultationId;
  final String name;
  final ConsultationStatus? status;
  final DateTime? scheduledAt;
}

class Conversation {
  const Conversation({
    required this.id,
    this.peer,
    this.counselor,
    this.section = ConversationSection.inbox,
    this.lastMessage,
    this.lastMessageKind = MessageKind.text,
    this.lastFromMe = false,
    this.lastAt,
    this.unread = 0,
    this.expiresAt,
    this.expiringSoon = false,
    this.rematch,
    this.unmatchedByMe,
  });
  final String id;

  /// Null for consultation chats (see [counselor]).
  final UserProfile? peer;
  final CounselorChatInfo? counselor;
  final ConversationSection section;
  final String? lastMessage;
  final MessageKind lastMessageKind;

  /// The last message was sent by me (the row shows "You: …").
  final bool lastFromMe;
  final DateTime? lastAt;
  final int unread;

  /// When the server will remove it from this section (null = never).
  final DateTime? expiresAt;

  /// Inside the warning window (inbox: after day 10 of 15; archive: last 7 of 30).
  final bool expiringSoon;
  final RematchInfo? rematch;
  final bool? unmatchedByMe;

  String get title => peer?.name ?? counselor?.name ?? '';
  bool get isUnmatched => section == ConversationSection.unmatched;
  bool get isConsultation => section == ConversationSection.consultation;

  /// One request per conversation, ever.
  bool get canRequestRematch => isUnmatched && rematch == null;
  bool get canAnswerRematch => isUnmatched && rematch?.status == RematchStatus.pending && rematch?.byMe == false;
  bool get canWrite => !isUnmatched;
}

/// A row past the plan's visible-conversation limit: the server sends no
/// identity or preview for it.
class LockedConversation {
  const LockedConversation({required this.id, required this.section});
  final String id;
  final ConversationSection section;
}

/// Everything the Messages tab needs in one call.
class ConversationIndex {
  const ConversationIndex({required this.visible, required this.locked, required this.visibleLimit});
  final List<Conversation> visible;
  final List<LockedConversation> locked;

  /// -1 = unlimited.
  final int visibleLimit;

  List<Conversation> section(ConversationSection s) => visible.where((c) => c.section == s).toList();
  List<LockedConversation> lockedIn(ConversationSection s) => locked.where((c) => c.section == s).toList();
  int count(ConversationSection s) => section(s).length + lockedIn(s).length;
}

// ───────────── consultations ─────────────

enum CounselorKind { psychologist, familyCounselor }

enum ConsultationService { premarital, marital, family, parenting, individual, divorceRecovery }

enum ConsultationStatus { awaitingPayment, paid, confirmed, completed, declined, cancelled, refunded, expired }

enum CounselorStatus { pending, approved, rejected, suspended }

/// One bookable combination: service × language × duration, with its own price.
class CounselorOffering {
  const CounselorOffering({required this.id, required this.service, required this.language, required this.durationMinutes, required this.priceMinor, required this.currency, this.active = true});
  final String id;
  final ConsultationService service;
  final String language; // ISO 639-1
  final int durationMinutes;
  final int priceMinor; // integer minor units
  final String currency; // ISO 4217
  final bool active;
}

class CounselorReview {
  const CounselorReview({required this.rating, required this.createdAt, this.comment, this.by});
  final int rating;
  final String? comment;
  final String? by; // first name only
  final DateTime createdAt;
}

class Counselor {
  const Counselor({
    required this.id,
    required this.kind,
    required this.name,
    required this.headline,
    required this.bio,
    required this.yearsExperience,
    required this.licenseAuthority,
    required this.licenseCountry,
    required this.languages,
    required this.services,
    required this.offerings,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.reviews = const [],
    this.status,
    this.rejectReason,
  });
  final String id;
  final CounselorKind kind;
  final String name;
  final String headline;
  final String bio;
  final int yearsExperience;
  final String licenseAuthority;
  final String licenseCountry;
  final List<String> languages;
  final List<ConsultationService> services;
  final List<CounselorOffering> offerings;
  final double ratingAvg;
  final int ratingCount;
  final List<CounselorReview> reviews;

  /// Only present on the counselor's own profile.
  final CounselorStatus? status;
  final String? rejectReason;
}

class Consultation {
  const Consultation({
    required this.id,
    required this.counselorId,
    required this.counselorName,
    required this.service,
    required this.language,
    required this.durationMinutes,
    required this.priceMinor,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.clientName,
    this.note,
    this.scheduledAt,
    this.expiresAt,
    this.conversationId,
    this.myRating,
    this.declineReason,
  });
  final String id;
  final String counselorId;
  final String counselorName;
  final String? clientName; // counselor desk only
  final ConsultationService service;
  final String language;
  final int durationMinutes;
  final int priceMinor;
  final String currency;
  final ConsultationStatus status;
  final DateTime createdAt;
  final String? note;
  final DateTime? scheduledAt;
  final DateTime? expiresAt; // payment window
  final String? conversationId;
  final int? myRating;
  final String? declineReason;

  bool get canRate => status == ConsultationStatus.completed && myRating == null;
  bool get canCancel => status == ConsultationStatus.awaitingPayment || status == ConsultationStatus.paid;
}

/// Result of creating a booking: what the payment sheet needs.
class BookingIntent {
  const BookingIntent({required this.consultationId, required this.amountMinor, required this.currency, required this.expiresAt, required this.provider, this.clientSecret});
  final String consultationId;
  final int amountMinor;
  final String currency;
  final DateTime expiresAt;
  final String provider; // stripe | test
  final String? clientSecret;
}

enum NotificationKind { match, like, compliment, message, verification, consultation, rematch, chatExpiring, account, reminder }

class AppNotification {
  const AppNotification({required this.id, required this.kind, required this.title, required this.createdAt, this.body, this.data = const {}, this.read = false});
  final String id;
  final NotificationKind kind;
  final String title; // localised from the server's key
  final String? body;
  final Map<String, String> data; // conversationId, consultationId, fromUserId…
  final DateTime createdAt;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(id: id, kind: kind, title: title, body: body, data: data, createdAt: createdAt, read: read ?? this.read);
}

enum PaymentStatus { pending, succeeded, refunded, failed }

enum PaymentKind { subscription, consultation }

/// One row of GET /me/payments: a store subscription charge or a consultation payment.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.plan,
    required this.store,
    required this.date,
    required this.status,
    this.kind = PaymentKind.subscription,
    this.amountMinor,
    this.currency,
    this.reference,
    this.refundedAt,
    this.description,
    this.amountLabel,
  });
  final String id;
  final PlanCode plan;
  final String store; // App Store · Google Play · Card (web)
  final DateTime date;
  final PaymentStatus status;
  final PaymentKind kind;
  final int? amountMinor; // integer minor units
  final String? currency;
  final String? reference; // short receipt reference for support
  final DateTime? refundedAt;
  final String? description; // consultation: counselor · service
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

/// Privacy choices — stored and enforced by the server (GET/PUT /me/privacy).
class PrivacySettings {
  const PrivacySettings({
    this.discoverable = true,
    this.showCity = true,
    this.blurPhotosUntilMatch = false,
    this.showOnline = true,
    this.readReceipts = true,
    this.incognito = false,
  });

  /// Off: hidden from discovery; existing matches and chats continue.
  final bool discoverable;
  final bool showCity;
  final bool blurPhotosUntilMatch;

  /// Reciprocal: hiding yours also hides other people's from you.
  final bool showOnline;

  /// Reciprocal, like [showOnline].
  final bool readReceipts;

  /// Premium: only people you liked can see you.
  final bool incognito;

  PrivacySettings copyWith({bool? discoverable, bool? showCity, bool? blurPhotosUntilMatch, bool? showOnline, bool? readReceipts, bool? incognito}) =>
      PrivacySettings(
        discoverable: discoverable ?? this.discoverable,
        showCity: showCity ?? this.showCity,
        blurPhotosUntilMatch: blurPhotosUntilMatch ?? this.blurPhotosUntilMatch,
        showOnline: showOnline ?? this.showOnline,
        readReceipts: readReceipts ?? this.readReceipts,
        incognito: incognito ?? this.incognito,
      );

  factory PrivacySettings.fromJson(Map<String, dynamic> j) => PrivacySettings(
        discoverable: j['discoverable'] as bool? ?? true,
        showCity: j['showCity'] as bool? ?? true,
        blurPhotosUntilMatch: j['blurPhotos'] as bool? ?? false,
        showOnline: j['showOnline'] as bool? ?? true,
        readReceipts: j['readReceipts'] as bool? ?? true,
        incognito: j['incognito'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'discoverable': discoverable,
        'showCity': showCity,
        'blurPhotos': blurPhotosUntilMatch,
        'showOnline': showOnline,
        'readReceipts': readReceipts,
        'incognito': incognito,
      };

  /// How others currently find you (shown on My profile).
  ProfileVisibility get visibility => !discoverable
      ? ProfileVisibility.hidden
      : incognito
          ? ProfileVisibility.incognito
          : ProfileVisibility.visible;
}

enum ProfileVisibility { visible, incognito, hidden }

/// A signed-in device (one session per device; GET /auth/sessions).
class DeviceSession {
  const DeviceSession({required this.id, required this.platform, required this.lastUsedAt, required this.createdAt, this.appVersion, this.current = false});
  final String id;
  final String platform; // ios | android
  final String? appVersion;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final bool current;
}

class BlockedUser {
  const BlockedUser({required this.userId, required this.name, required this.blockedAt});
  final String userId;
  final String name;
  final DateTime blockedAt;
}

/// Realtime chat event (WebSocket in production).
class ChatEvent {
  const ChatEvent._(this.conversationId, {this.message, this.typing, this.readClientId, this.movedTo, this.readByMe = false});
  factory ChatEvent.newMessage(ChatMessage m) => ChatEvent._(m.conversationId, message: m);
  factory ChatEvent.typingChanged(String convId, bool on) => ChatEvent._(convId, typing: on);
  /// The other person read my messages (only when both keep read receipts on).
  factory ChatEvent.readReceipt(String convId, String clientId) => ChatEvent._(convId, readClientId: clientId);

  /// I read this conversation (here or on another device): unread badges clear.
  factory ChatEvent.readByMeEvent(String convId) => ChatEvent._(convId, readByMe: true);

  /// Unmatch / re-match / archive moved the conversation to another section.
  factory ChatEvent.moved(String convId, ConversationSection to) => ChatEvent._(convId, movedTo: to);

  final String conversationId;
  final ChatMessage? message;
  final bool? typing;
  final String? readClientId;
  final ConversationSection? movedTo;
  final bool readByMe;
}


// ───────────── counselor wallet ─────────────

/// Balance in one currency (amounts in integer minor units).
class WalletBalance {
  const WalletBalance({
    required this.currency,
    required this.availableMinor,
    required this.pendingMinor,
    required this.completedSessions,
    required this.grossMinor,
    required this.platformFeeMinor,
    required this.netEarnedMinor,
    required this.withdrawnMinor,
    required this.minimumMinor,
  });
  final String currency;
  final int availableMinor; // withdrawable now
  final int pendingMinor; // still in the hold period
  final int completedSessions;
  final int grossMinor; // what clients paid
  final int platformFeeMinor; // 15% commission
  final int netEarnedMinor; // the counselor's share
  final int withdrawnMinor;
  final int minimumMinor;
}

class WalletSummary {
  const WalletSummary({required this.commissionPercent, required this.holdDays, required this.balances, this.openWithdrawals = const [], this.payoutsOnHold = false});
  final int commissionPercent;
  final int holdDays;
  final List<WalletBalance> balances;
  final List<Withdrawal> openWithdrawals;

  /// True while an integrity review is open: requests are kept but not paid out.
  final bool payoutsOnHold;
}

enum WalletEntryKind { earning, earningReversal, withdrawal, withdrawalReturn, adjustment }

class WalletEntry {
  const WalletEntry({required this.id, required this.kind, required this.amountMinor, required this.currency, required this.createdAt, required this.availableAt, this.pending = false, this.memo, this.grossMinor, this.feeMinor, this.feePercent, this.service, this.durationMinutes});
  final String id;
  final WalletEntryKind kind;
  final int amountMinor; // signed
  final String currency;
  final DateTime createdAt;
  final DateTime availableAt;
  final bool pending;
  final String? memo;
  // for earnings: the consultation's split
  final int? grossMinor;
  final int? feeMinor;
  final int? feePercent;
  final ConsultationService? service;
  final int? durationMinutes;
}

enum PayoutKind { bankIban, bankSwift, wise, paypal, payoneer }

class PayoutMethod {
  const PayoutMethod({required this.id, required this.kind, required this.holderName, required this.countryIso, required this.currency, required this.mask, this.isDefault = false});
  final String id;
  final PayoutKind kind;
  final String holderName;
  final String countryIso;
  final String currency;
  final String mask; // e.g. AE07 •••• 3456 — the full number never comes back
  final bool isDefault;
}

/// What the counselor types when adding a payout method (sent once, sealed on the server).
class PayoutMethodDraft {
  const PayoutMethodDraft({required this.kind, required this.holderName, required this.countryIso, required this.currency, this.iban, this.accountNumber, this.bic, this.bankName, this.email, this.makeDefault = false});
  final PayoutKind kind;
  final String holderName;
  final String countryIso;
  final String currency;
  final String? iban;
  final String? accountNumber;
  final String? bic;
  final String? bankName;
  final String? email;
  final bool makeDefault;
}

enum WithdrawalStatus { requested, processing, paid, rejected, failed, cancelled }

class Withdrawal {
  const Withdrawal({required this.id, required this.amountMinor, required this.currency, required this.status, required this.requestedAt, this.processedAt, this.reference, this.failureReason, this.methodMask, this.methodKind});
  final String id;
  final int amountMinor;
  final String currency;
  final WithdrawalStatus status;
  final DateTime requestedAt;
  final DateTime? processedAt;
  final String? reference;
  final String? failureReason;
  final String? methodMask;
  final PayoutKind? methodKind;
  bool get open => status == WithdrawalStatus.requested || status == WithdrawalStatus.processing;
}

// ───────────── mandatory post-consultation questionnaire ─────────────

enum NextSession { bookedInApp, planInApp, agreedOutside, notDiscussed, no }

enum NextChannel { olfa, direct, otherApp, undecided }

enum YesNoUnsure { no, yes, unsure }

/// Quality questions plus direct and indirect questions about moving the
/// relationship outside OLFA. Counselors never see who answered what.
class ReviewAnswers {
  const ReviewAnswers({
    this.rating = 0,
    this.quality = 0,
    this.commitment = 0,
    this.effectiveness = 0,
    this.outcome = 0,
    this.nextSession,
    this.nextChannel,
    this.contactShared,
    this.offPlatformPayment,
    this.externalChannel,
    this.comment = '',
  });
  final int rating;
  final int quality;
  final int commitment;
  final int effectiveness;
  final int outcome;
  final NextSession? nextSession;
  final NextChannel? nextChannel;
  final YesNoUnsure? contactShared;
  final YesNoUnsure? offPlatformPayment;
  final YesNoUnsure? externalChannel;
  final String comment;

  bool get complete =>
      [rating, quality, commitment, effectiveness, outcome].every((v) => v >= 1 && v <= 5) &&
      nextSession != null && nextChannel != null && contactShared != null && offPlatformPayment != null && externalChannel != null;

  ReviewAnswers copyWith({int? rating, int? quality, int? commitment, int? effectiveness, int? outcome, NextSession? nextSession, NextChannel? nextChannel, YesNoUnsure? contactShared, YesNoUnsure? offPlatformPayment, YesNoUnsure? externalChannel, String? comment}) => ReviewAnswers(
        rating: rating ?? this.rating,
        quality: quality ?? this.quality,
        commitment: commitment ?? this.commitment,
        effectiveness: effectiveness ?? this.effectiveness,
        outcome: outcome ?? this.outcome,
        nextSession: nextSession ?? this.nextSession,
        nextChannel: nextChannel ?? this.nextChannel,
        contactShared: contactShared ?? this.contactShared,
        offPlatformPayment: offPlatformPayment ?? this.offPlatformPayment,
        externalChannel: externalChannel ?? this.externalChannel,
        comment: comment ?? this.comment,
      );

  static String _snake(String camel) => camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'quality': quality,
        'commitment': commitment,
        'effectiveness': effectiveness,
        'outcome': outcome,
        'nextSession': _snake(nextSession!.name),
        'nextChannel': _snake(nextChannel!.name),
        'contactShared': contactShared!.name.toUpperCase(),
        'offPlatformPayment': offPlatformPayment!.name.toUpperCase(),
        'externalChannel': externalChannel!.name.toUpperCase(),
        if (comment.trim().isNotEmpty) 'comment': comment.trim(),
      };
}

/// A completed consultation still waiting for the client's questionnaire.
class PendingReview {
  const PendingReview({required this.consultationId, required this.counselorName, required this.service, required this.durationMinutes, this.completedAt});
  final String consultationId;
  final String counselorName;
  final ConsultationService service;
  final int durationMinutes;
  final DateTime? completedAt;
}

/// Integrity review of a counselor, as the counselor sees it (never who reported what).
enum IntegrityCaseStatus { open, awaitingResponse, underReview, cleared, warned, suspended, banned }

class IntegrityCase {
  const IntegrityCase({required this.id, required this.status, required this.openedAt, this.responseDueAt, this.response, this.decisionReason});
  final String id;
  final IntegrityCaseStatus status;
  final DateTime openedAt;
  final DateTime? responseDueAt;
  final String? response;
  final String? decisionReason;
  bool get needsResponse => status == IntegrityCaseStatus.awaitingResponse || status == IntegrityCaseStatus.open;
  bool get isOpen => needsResponse || status == IntegrityCaseStatus.underReview;
}

// ───────────── store subscription state ─────────────

enum StoreSubStatus { active, gracePeriod, billingRetry, onHold, paused, cancelled, expired, refunded, revoked, pending }

/// The store subscription as the server last verified it with Apple / Google.
class StoreSubscription {
  const StoreSubscription({required this.plan, required this.status, required this.autoRenew, this.expiresAt, this.graceUntil, this.pendingPlan, this.isApple = true, this.manageUrl});
  final PlanCode plan;
  final StoreSubStatus status;
  final bool autoRenew;
  final DateTime? expiresAt;
  final DateTime? graceUntil; // features stay on until then while the store retries the payment
  final PlanCode? pendingPlan; // downgrade that starts at the next renewal
  final bool isApple;
  final String? manageUrl;
  bool get billingIssue => status == StoreSubStatus.gracePeriod || status == StoreSubStatus.billingRetry || status == StoreSubStatus.onHold;
}

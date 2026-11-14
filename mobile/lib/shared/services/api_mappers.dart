import '../models/models.dart';

/// API ⇄ domain mapping. Backend enums are SCREAMING_SNAKE (WITHIN_6_MONTHS),
/// Dart enums are lowerCamel (within6Months).
String toApiEnum(Enum e) => e.name
    .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z0-9])|(?<=[0-9])(?=[A-Za-z])'), (_) => '_')
    .toUpperCase();

T fromApiEnum<T extends Enum>(List<T> values, Object? api, T fallback) {
  for (final v in values) {
    if (toApiEnum(v) == api) return v;
  }
  return fallback;
}

abstract final class ApiMappers {
  static ProfilePhoto photo(Map<String, dynamic> j) => ProfilePhoto(
        id: j['id'] as String,
        thumbUrl: j['thumbUrl'] as String?,
        cardUrl: j['cardUrl'] as String?,
        fullUrl: j['fullUrl'] as String?,
      );

  /// Public profile (GET /profiles/:id, discovery items, match peers).
  static UserProfile profile(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String,
        name: j['displayName'] as String? ?? '',
        age: (j['age'] as num?)?.toInt() ?? 0,
        gender: fromApiEnum(Gender.values, j['gender'], Gender.male),
        countryIso: j['countryCode'] as String? ?? '',
        city: j['city'] as String? ?? '',
        maritalStatus: fromApiEnum(MaritalStatus.values, j['maritalStatus'], MaritalStatus.neverMarried),
        education: fromApiEnum(Education.values, j['education'], Education.bachelor),
        occupation: j['occupation'] as String? ?? '',
        timeline: fromApiEnum(MarriageTimeline.values, j['marriageTimeline'], MarriageTimeline.notSure),
        bio: j['bio'] as String? ?? '',
        interests: (j['interests'] as List? ?? const []).cast<String>(),
        photos: (j['photos'] as List? ?? const []).map((p) => photo(Map<String, dynamic>.from(p as Map))).toList(),
        photosReviewed: j['isPhotosReviewed'] as bool? ?? false,
        livenessVerified: j['isLivenessVerified'] as bool? ?? false,
        identityVerified: j['isIdentityVerified'] as bool? ?? false,
        compatibility: (j['compatibility'] as num?)?.toInt() ?? 0,
        completeness: (j['completeness'] as num?)?.toInt() ?? 0,
        showLocation: j['showLocation'] as bool? ?? true,
      );

  /// GET /me/entitlements
  static Entitlements entitlements(Map<String, dynamic> j) {
    Map<String, dynamic> m(String k) => Map<String, dynamic>.from(j[k] as Map);
    final f = m('features');
    int n(Map<String, dynamic> x, String k) => (x[k] as num).toInt();
    return Entitlements(
      plan: fromApiEnum(PlanCode.values, j['plan'], PlanCode.free),
      dailyLikes: n(m('likes'), 'limit'),
      likesUsed: n(m('likes'), 'used'),
      dailyMessages: n(m('messages'), 'limit'),
      messagesUsed: n(m('messages'), 'used'),
      dailyUndos: n(m('undos'), 'limit'),
      undosUsed: n(m('undos'), 'used'),
      advancedFilters: f['advancedFilters'] == true,
      seeWhoLikedYou: f['seeWhoLikedYou'] == true,
      incognito: f['incognito'] == true,
      resetsAt: j['resetsAt'] is String ? DateTime.tryParse(j['resetsAt'] as String)?.toLocal() : null,
    );
  }

  /// GET /plans
  static PlanInfo plan(Map<String, dynamic> j) {
    final e = Map<String, dynamic>.from(j['entitlements'] as Map);
    int n(String k) => (e[k] as num?)?.toInt() ?? 0;
    final products = (j['products'] as List? ?? const []).cast<Map>();
    return PlanInfo(
      code: fromApiEnum(PlanCode.values, j['code'], PlanCode.free),
      dailyLikes: n('daily_likes'),
      dailyMessages: n('daily_messages'),
      dailyUndos: n('daily_undos'),
      advancedFilters: e['advanced_filters'] == true,
      seeWhoLikedYou: e['see_who_liked_you'] == true,
      priorityVisibility: e['priority_visibility'] == true,
      storeProductId: products.isEmpty ? null : products.first['productId'] as String?,
    );
  }

  static ChatMessage message(Map<String, dynamic> j, String conversationId, String myId) {
    final receipts = (j['receipts'] as List? ?? const []).cast<Map>();
    final read = receipts.any((r) => r['readAt'] != null);
    final delivered = receipts.any((r) => r['deliveredAt'] != null);
    final mine = j['senderId'] == myId;
    return ChatMessage(
      id: j['id'] as String,
      clientId: j['clientMessageId'] as String,
      conversationId: conversationId,
      fromMe: mine,
      body: j['body'] as String,
      sentAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      status: !mine ? MessageStatus.delivered : (read ? MessageStatus.read : (delivered ? MessageStatus.delivered : MessageStatus.sent)),
    );
  }

  static NotificationKind notificationKind(String type) => switch (type) {
        'NEW_MATCH' => NotificationKind.match,
        'NEW_LIKE' => NotificationKind.like,
        'NEW_MESSAGE' => NotificationKind.message,
        'VERIFICATION_APPROVED' || 'VERIFICATION_REJECTED' => NotificationKind.verification,
        _ => NotificationKind.reminder,
      };
}

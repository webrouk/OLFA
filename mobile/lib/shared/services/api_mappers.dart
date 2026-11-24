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
        heightCm: (j['heightCm'] as num?)?.toInt(),
        weightKg: (j['weightKg'] as num?)?.toInt(),
        religion: j['religion'] as String?,
        sect: j['sect'] as String?,
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
        nationality: j['nationality'] as String?,
        distanceKm: (j['distanceKm'] as num?)?.round(),
        photosBlurred: j['photosBlurred'] == true,
        underReview: j['underReview'] == true,
        online: j['online'] == true, // reciprocal; computed by the server
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
      searchOutsideCountry: f['searchOutsideCountry'] == true,
      visibleConversations: (f['visibleConversations'] as num?)?.toInt() ?? 5,
      monthlyCompliments: j['compliments'] is Map ? n(m('compliments'), 'limit') : 0,
      complimentsUsed: j['compliments'] is Map ? n(m('compliments'), 'used') : 0,
      complimentsResetAt: j['compliments'] is Map && m('compliments')['resetsAt'] is String ? DateTime.tryParse(m('compliments')['resetsAt'] as String)?.toLocal() : null,
      accountActive: j['accountStatus'] == null || j['accountStatus'] == 'ACTIVE' || j['accountStatus'] == 'RESTRICTED',
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
      body: j['body'] as String? ?? '',
      sentAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      status: !mine ? MessageStatus.delivered : (read ? MessageStatus.read : (delivered ? MessageStatus.delivered : MessageStatus.sent)),
      kind: switch (j['type']) { 'IMAGE' => MessageKind.image, 'VOICE' => MessageKind.voice, _ => MessageKind.text },
      containsPhone: j['containsPhone'] == true,
      attachments: (j['attachments'] as List? ?? const [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .map((a) => ChatAttachment(
                id: a['id'] as String?,
                kind: a['kind'] == 'VOICE' ? MessageKind.voice : MessageKind.image,
                url: a['url'] as String?,
                width: (a['width'] as num?)?.toInt(),
                height: (a['height'] as num?)?.toInt(),
                durationMs: (a['durationMs'] as num?)?.toInt(),
                waveform: (a['waveform'] as List? ?? const []).map((v) => (v as num).toInt()).toList(),
              ))
          .toList(),
    );
  }

  static NotificationKind notificationKind(String type) => switch (type) {
        'NEW_MATCH' => NotificationKind.match,
        'NEW_LIKE' => NotificationKind.like,
        'NEW_COMPLIMENT' => NotificationKind.compliment,
        'NEW_MESSAGE' => NotificationKind.message,
        'VERIFICATION_APPROVED' || 'VERIFICATION_REJECTED' || 'COUNSELOR_APPROVED' || 'COUNSELOR_REJECTED' => NotificationKind.verification,
        'CONSULTATION_REQUEST' || 'CONSULTATION_CONFIRMED' || 'CONSULTATION_DECLINED' || 'CONSULTATION_COMPLETED' => NotificationKind.consultation,
        'REMATCH_REQUEST' || 'REMATCH_ACCEPTED' => NotificationKind.rematch,
        'CONVERSATION_EXPIRING' => NotificationKind.chatExpiring,
        'SUBSCRIPTION' || 'SYSTEM' => NotificationKind.account,
        _ => NotificationKind.reminder,
      };

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  /// One row of GET /conversations (unlocked).
  static Conversation conversation(Map<String, dynamic> j) {
    final last = j['lastMessage'] as Map?;
    final rm = j['rematch'] as Map?;
    final k = j['consultation'] as Map?;
    final c = k?['counselor'] as Map?;
    return Conversation(
      id: j['id'] as String,
      section: fromApiEnum(ConversationSection.values, j['section'], ConversationSection.inbox),
      peer: j['peer'] is Map ? profile(Map<String, dynamic>.from(j['peer'] as Map)) : null,
      counselor: k == null
          ? null
          : CounselorChatInfo(
              consultationId: k['id'] as String,
              name: c?['displayName'] as String? ?? '',
              status: fromApiEnum(ConsultationStatus.values, k['status'], ConsultationStatus.confirmed),
              scheduledAt: _date(k['scheduledAt']),
            ),
      lastMessage: last?['body'] as String?,
      lastMessageKind: switch (last?['type']) { 'IMAGE' => MessageKind.image, 'VOICE' => MessageKind.voice, _ => MessageKind.text },
      lastFromMe: last?['mine'] == true,
      lastAt: _date(j['lastMessageAt']),
      unread: (j['unread'] as num?)?.toInt() ?? 0,
      expiresAt: _date(j['expiresAt']),
      expiringSoon: j['expiringSoon'] == true,
      unmatchedByMe: j['unmatchedByMe'] as bool?,
      rematch: rm == null ? null : RematchInfo(status: fromApiEnum(RematchStatus.values, rm['status'], RematchStatus.pending), byMe: rm['byMe'] == true),
    );
  }

  static CounselorOffering offering(Map<String, dynamic> j) => CounselorOffering(
        id: j['id'] as String,
        service: fromApiEnum(ConsultationService.values, j['service'], ConsultationService.marital),
        language: j['language'] as String,
        durationMinutes: (j['durationMinutes'] as num).toInt(),
        priceMinor: (j['priceMinor'] as num).toInt(),
        currency: j['currency'] as String,
        active: j['active'] as bool? ?? true,
      );

  static Counselor counselor(Map<String, dynamic> j) => Counselor(
        id: j['userId'] as String,
        kind: fromApiEnum(CounselorKind.values, j['kind'], CounselorKind.familyCounselor),
        name: j['displayName'] as String? ?? '',
        headline: j['headline'] as String? ?? '',
        bio: j['bio'] as String? ?? '',
        yearsExperience: (j['yearsExperience'] as num?)?.toInt() ?? 0,
        licenseAuthority: j['licenseAuthority'] as String? ?? '',
        licenseCountry: j['licenseCountry'] as String? ?? '',
        languages: (j['languages'] as List? ?? const []).cast<String>(),
        services: (j['services'] as List? ?? const []).map((x) => fromApiEnum(ConsultationService.values, x, ConsultationService.marital)).toList(),
        offerings: (j['offerings'] as List? ?? const []).map((x) => offering(Map<String, dynamic>.from(x as Map))).toList(),
        // Prisma Decimal arrives as a string
        ratingAvg: double.tryParse('${j['ratingAvg'] ?? 0}') ?? 0,
        ratingCount: (j['ratingCount'] as num?)?.toInt() ?? 0,
        reviews: (j['reviews'] as List? ?? const [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .map((r) => CounselorReview(rating: (r['rating'] as num).toInt(), comment: r['comment'] as String?, by: r['by'] as String?, createdAt: _date(r['createdAt']) ?? DateTime.now()))
            .toList(),
        status: j['status'] == null ? null : fromApiEnum(CounselorStatus.values, j['status'], CounselorStatus.pending),
        rejectReason: j['rejectReason'] as String?,
      );

  static Consultation consultation(Map<String, dynamic> j) {
    final c = j['counselor'] as Map?;
    final client = j['client'] as Map?;
    return Consultation(
      id: j['id'] as String,
      counselorId: (c?['userId'] ?? j['counselorId'] ?? '') as String,
      counselorName: c?['displayName'] as String? ?? '',
      clientName: (client?['profile'] as Map?)?['displayName'] as String?,
      service: fromApiEnum(ConsultationService.values, j['service'], ConsultationService.marital),
      language: j['language'] as String,
      durationMinutes: (j['durationMinutes'] as num).toInt(),
      priceMinor: (j['priceMinor'] as num).toInt(),
      currency: j['currency'] as String,
      status: fromApiEnum(ConsultationStatus.values, j['status'], ConsultationStatus.awaitingPayment),
      createdAt: _date(j['createdAt']) ?? DateTime.now(),
      note: j['clientNote'] as String?,
      scheduledAt: _date(j['scheduledAt']),
      expiresAt: _date(j['expiresAt']),
      conversationId: (j['conversation'] as Map?)?['id'] as String?,
      myRating: ((j['review'] as Map?)?['rating'] as num?)?.toInt(),
      declineReason: j['declineReason'] as String?,
    );
  }
}

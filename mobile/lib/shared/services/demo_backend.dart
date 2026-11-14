import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failure.dart';
import '../../core/localization/locale_provider.dart';
import '../models/models.dart';

/// In-memory stand-in for the OLFA REST API + realtime gateway, used during
/// the UI phase (Phase 2). It enforces the same rules the real server will
/// (quotas, entitlements, duplicate protection, block lists) so the UI is
/// built against realistic behaviour. Replaced by HTTP repositories in Phase 3.
///
/// ALL DATA HERE IS DEMO DATA.
class DemoBackend {
  DemoBackend();

  String lang = 'ar';
  Gender myGender = Gender.male;
  bool online = true;

  // ── entitlements (server-managed, editable from the admin dashboard) ──
  PlanCode plan = PlanCode.free;
  int likesUsed = 3;
  int messagesUsed = 0;
  int undosUsed = 0;

  final Map<PlanCode, PlanInfo> plans = const {
    PlanCode.free: PlanInfo(code: PlanCode.free, dailyLikes: 10, dailyMessages: 1, dailyUndos: 0, advancedFilters: false, seeWhoLikedYou: false, priorityVisibility: false),
    PlanCode.plus: PlanInfo(code: PlanCode.plus, dailyLikes: 100, dailyMessages: 5, dailyUndos: 3, advancedFilters: true, seeWhoLikedYou: true, priorityVisibility: false, storeProductId: 'olfa.plus.monthly'),
    PlanCode.premium: PlanInfo(code: PlanCode.premium, dailyLikes: 200, dailyMessages: 10, dailyUndos: 10, advancedFilters: true, seeWhoLikedYou: true, priorityVisibility: true, storeProductId: 'olfa.premium.monthly'),
  };

  final _liked = <String>{};
  final _passed = <String>{};
  final _blocked = <String>{};
  final _likesMe = <String>{'d1', 'd3', 'd5', 'd7'};
  final _matches = <String, MatchItem>{};
  final _messages = <String, List<ChatMessage>>{};
  final _sentClientIds = <String>{};
  final _events = StreamController<ChatEvent>.broadcast();
  final _payments = <PaymentRecord>[];
  bool _notificationsRead = false;
  int _otpAttempts = 5;
  VerificationStatus verification = VerificationStatus.pending;
  PrivacySettings privacy = const PrivacySettings();
  bool deletionScheduled = false;

  Stream<ChatEvent> get events => _events.stream;

  Future<T> _call<T>(T Function() body, {int ms = 380}) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    if (!online) throw const NetworkFailure();
    return body();
  }

  // ───────────── auth ─────────────
  Future<void> requestOtp(String e164) => _call(() {
        if (e164.replaceAll(RegExp(r'\D'), '').length < 9) throw const ValidationFailure('phone');
        _otpAttempts = 5;
      }, ms: 700);

  Future<void> verifyOtp(String code) => _call(() {
        if (code == '000000') {
          _otpAttempts--;
          throw InvalidOtpFailure(_otpAttempts);
        }
      }, ms: 600);

  // ───────────── profile & verification ─────────────
  Future<void> submitForReview() => _call(() => verification = VerificationStatus.pending, ms: 900);

  Future<VerificationInfo> verificationInfo() => _call(() => VerificationInfo(
        status: verification,
        reason: verification == VerificationStatus.rejected
            ? (lang == 'ar' ? 'الصورة الرئيسية غير واضحة — يجب أن يظهر وجهك بوضوح.' : 'Main photo is unclear — your face must be clearly visible.')
            : null,
        fixSteps: verification == VerificationStatus.rejected
            ? (lang == 'ar'
                ? ['استبدل الصورة الرئيسية بصورة حديثة وواضحة', 'تأكد من الإضاءة الجيدة وعدم وجود نظارات شمسية']
                : ['Replace your main photo with a clear, recent one', 'Use good lighting and no sunglasses'])
            : const [],
      ));

  Future<UserProfile> me() => _call(() => _me());

  // ───────────── entitlements & plans ─────────────
  Entitlements entitlementsNow() {
    final p = plans[plan]!;
    return Entitlements(
      plan: plan,
      dailyLikes: p.dailyLikes,
      likesUsed: likesUsed,
      dailyMessages: p.dailyMessages,
      messagesUsed: messagesUsed,
      dailyUndos: p.dailyUndos,
      undosUsed: undosUsed,
      advancedFilters: p.advancedFilters,
      seeWhoLikedYou: p.seeWhoLikedYou,
      incognito: plan == PlanCode.premium,
    );
  }

  Future<Entitlements> entitlements() => _call(entitlementsNow, ms: 200);
  Future<List<PlanInfo>> listPlans() => _call(() => plans.values.toList());

  Future<void> purchase(PlanCode code) => _call(() {
        // Real flow: StoreKit / Play Billing → server receipt validation.
        plan = code;
        _payments.insert(
          0,
          PaymentRecord(id: 'TX-${8800 + _payments.length}', plan: code, store: 'App Store', date: DateTime.now(), status: PaymentStatus.succeeded),
        );
      }, ms: 900);

  Future<List<PaymentRecord>> payments() => _call(() => List.unmodifiable(_payments));

  // ───────────── discovery ─────────────
  Future<List<UserProfile>> discover(DiscoverFilters f) => _call(() {
        if (f.usesPaidFilters && !plans[plan]!.advancedFilters) {
          throw const EntitlementRequiredFailure('advancedFilters');
        }
        return _all()
            .where((p) => p.gender != myGender) // mutual base preference
            .where((p) => !_liked.contains(p.id) && !_passed.contains(p.id) && !_blocked.contains(p.id))
            .where((p) => p.age >= f.ageMin && p.age <= f.ageMax)
            .where((p) => f.countryIso == null || p.countryIso == f.countryIso)
            .where((p) => f.maritalStatuses.isEmpty || f.maritalStatuses.contains(p.maritalStatus))
            .where((p) => f.educations.isEmpty || f.educations.contains(p.education))
            .where((p) => f.minCompatibility == null || p.compatibility >= f.minCompatibility!)
            .toList();
      }, ms: 650);

  Future<UserProfile> profile(String id) => _call(() {
        if (_blocked.contains(id)) throw const ServerFailure('not_found');
        return _all().firstWhere((p) => p.id == id, orElse: () => throw const ServerFailure('not_found'));
      });

  /// Returns the created match, or null when the like is not mutual.
  Future<MatchItem?> like(String id) => _call(() {
        if (_liked.contains(id)) throw const AlreadyActedFailure();
        if (likesUsed >= plans[plan]!.dailyLikes) throw const QuotaExceededFailure('likes');
        _liked.add(id);
        likesUsed++;
        if (_likesMe.contains(id)) {
          final m = MatchItem(id: 'm-$id', peer: _all().firstWhere((p) => p.id == id), createdAt: DateTime.now(), isNew: true);
          _matches[m.id] = m;
          return m;
        }
        return null;
      }, ms: 300);

  Future<void> pass(String id) => _call(() {
        if (_passed.contains(id)) throw const AlreadyActedFailure();
        _passed.add(id);
      }, ms: 250);

  Future<void> undo(String id) => _call(() {
        if (undosUsed >= plans[plan]!.dailyUndos) throw const QuotaExceededFailure('undos');
        if (_matches.containsKey('m-$id')) throw const ServerFailure('undo_after_match');
        undosUsed++;
        if (_liked.remove(id)) likesUsed--;
        _passed.remove(id);
      }, ms: 250);

  /// Free users get the count only — identities are never sent to them.
  Future<({int count, List<UserProfile> profiles})> likesReceived() => _call(() {
        final ps = _all().where((p) => _likesMe.contains(p.id) && !_blocked.contains(p.id) && p.gender != myGender).toList();
        return (count: ps.length + 8, profiles: plans[plan]!.seeWhoLikedYou ? ps : <UserProfile>[]);
      });

  // ───────────── matches & chat ─────────────
  Future<List<MatchItem>> matches() => _call(() {
        _seedMatches();
        return _matches.values.where((m) => !_blocked.contains(m.peer.id)).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });

  Future<String> startConversation(String matchId) => _call(() {
        final m = _matches[matchId]!;
        if (m.conversationId != null) return m.conversationId!;
        if (messagesUsed >= plans[plan]!.dailyMessages) throw const QuotaExceededFailure('messages');
        messagesUsed++;
        final convId = 'c-${m.peer.id}';
        _matches[matchId] = MatchItem(id: m.id, peer: m.peer, createdAt: m.createdAt, conversationId: convId);
        _messages.putIfAbsent(convId, () => []);
        return convId;
      });

  Future<List<Conversation>> conversations() => _call(() {
        _seedMatches();
        final out = <Conversation>[];
        for (final m in _matches.values) {
          final id = m.conversationId;
          if (id == null || _blocked.contains(m.peer.id)) continue;
          final msgs = _messages[id] ?? const [];
          out.add(Conversation(
            id: id,
            peer: m.peer,
            lastMessage: msgs.isEmpty ? null : msgs.last.body,
            lastAt: msgs.isEmpty ? m.createdAt : msgs.last.sentAt,
            unread: msgs.where((x) => !x.fromMe && x.status != MessageStatus.read).length,
          ));
        }
        out.sort((a, b) => b.lastAt!.compareTo(a.lastAt!));
        return out;
      });

  Future<Conversation> conversation(String id) async {
    final all = await conversations();
    return all.firstWhere((c) => c.id == id, orElse: () => throw const ServerFailure('not_found'));
  }

  /// Cursor pagination: newest first page, [before] loads older.
  Future<({List<ChatMessage> items, bool hasMore})> messages(String convId, {DateTime? before, int limit = 20}) => _call(() {
        final all = _messages[convId] ?? const <ChatMessage>[];
        final older = before == null ? all : all.where((m) => m.sentAt.isBefore(before)).toList();
        final start = (older.length - limit).clamp(0, older.length);
        return (items: older.sublist(start), hasMore: start > 0);
      });

  Future<ChatMessage> send(String convId, String clientId, String body) => _call(() {
        final list = _messages.putIfAbsent(convId, () => []);
        if (_sentClientIds.contains(clientId)) {
          return list.firstWhere((m) => m.clientId == clientId); // idempotent retry
        }
        final peerId = convId.substring(2);
        if (_blocked.contains(peerId)) throw const ServerFailure('blocked');
        _sentClientIds.add(clientId);
        final msg = ChatMessage(id: 'srv-$clientId', clientId: clientId, conversationId: convId, fromMe: true, body: body.trim(), sentAt: DateTime.now(), status: MessageStatus.sent);
        list.add(msg);
        _scheduleReply(convId, msg);
        return msg;
      }, ms: 250);

  void _scheduleReply(String convId, ChatMessage mine) {
    Timer(const Duration(milliseconds: 700), () {
      _events.add(ChatEvent.readReceipt(convId, mine.clientId));
      _events.add(ChatEvent.typingChanged(convId, true));
    });
    Timer(const Duration(milliseconds: 2200), () {
      final reply = ChatMessage(
        id: 'srv-r${DateTime.now().microsecondsSinceEpoch}',
        clientId: 'r${DateTime.now().microsecondsSinceEpoch}',
        conversationId: convId,
        fromMe: false,
        body: lang == 'ar' ? 'جميل، يسعدني التعرف عليك أكثر' : 'Lovely, happy to get to know you more',
        sentAt: DateTime.now(),
        status: MessageStatus.delivered,
      );
      _messages[convId]?.add(reply);
      _events.add(ChatEvent.typingChanged(convId, false));
      _events.add(ChatEvent.newMessage(reply));
    });
  }

  // ───────────── safety ─────────────
  Future<void> report(String userId, String reason, {bool block = false}) => _call(() {
        if (block) _blocked.add(userId);
      });

  Future<void> block(String userId) => _call(() => _blocked.add(userId));
  Future<int> blockedCount() => _call(() => _blocked.length);

  // ───────────── notifications ─────────────
  Future<List<AppNotification>> notifications() => _call(() {
        final now = DateTime.now();
        final ar = lang == 'ar';
        return [
          AppNotification(id: 'n1', kind: NotificationKind.match, title: ar ? 'توافق جديد مع سارة' : 'New match with Sara', createdAt: now.subtract(const Duration(minutes: 2)), read: _notificationsRead),
          AppNotification(id: 'n2', kind: NotificationKind.like, title: ar ? 'لديك 3 إعجابات جديدة' : 'You have 3 new likes', createdAt: now.subtract(const Duration(hours: 1)), read: _notificationsRead),
          AppNotification(id: 'n3', kind: NotificationKind.verification, title: ar ? 'تم اعتماد ملفك وصورك' : 'Your profile and photos were approved', createdAt: now.subtract(const Duration(hours: 3)), read: true),
          AppNotification(id: 'n4', kind: NotificationKind.message, title: ar ? 'رسالة جديدة من مريم' : 'New message from Mariam', createdAt: now.subtract(const Duration(days: 1)), read: true),
          AppNotification(id: 'n5', kind: NotificationKind.reminder, title: ar ? 'أكمل ملفك لزيادة فرص التوافق' : 'Complete your profile to get better matches', createdAt: now.subtract(const Duration(days: 2)), read: true),
        ];
      });

  Future<void> markAllNotificationsRead() => _call(() => _notificationsRead = true, ms: 150);

  // ───────────── settings & support ─────────────
  Future<PrivacySettings> getPrivacy() => _call(() => privacy, ms: 200);
  Future<void> setPrivacy(PrivacySettings s) => _call(() {
        if (s.incognito && plan != PlanCode.premium) throw const EntitlementRequiredFailure('incognito');
        privacy = s;
      }, ms: 200);

  Future<void> requestDeletion(String? reason) => _call(() => deletionScheduled = true, ms: 800);

  Future<List<FaqEntry>> faq() => _call(() {
        final ar = lang == 'ar';
        return [
          FaqEntry(id: 'f1', category: 'account', question: ar ? 'كيف تتم مراجعة الملفات؟' : 'How are profiles reviewed?', answer: ar ? 'يراجع فريقنا كل ملف وصوره قبل ظهوره للآخرين، مع فحص تلقائي للصور. تتم المراجعة عادةً خلال 24 ساعة.' : 'Our team reviews every profile and its photos before it is shown to others, alongside automated photo checks. Reviews usually take under 24 hours.'),
          FaqEntry(id: 'f2', category: 'account', question: ar ? 'متى يمكنني بدء محادثة؟' : 'When can I start a conversation?', answer: ar ? 'بعد حدوث إعجاب متبادل فقط. يُستخدم رصيد الرسائل اليومي لبدء محادثات جديدة، ويمكنك متابعة المحادثات القائمة بحرية.' : 'Only after a mutual like. Daily message credits start new conversations; continuing existing ones is free.'),
          FaqEntry(id: 'f3', category: 'payment', question: ar ? 'هل تتجدد الحصص اليومية؟' : 'Do daily limits reset?', answer: ar ? 'نعم، تتجدد يوميًا حسب منطقتك الزمنية، ولا يُرحَّل الرصيد غير المستخدم.' : 'Yes, daily in your time zone. Unused credits do not roll over.'),
          FaqEntry(id: 'f4', category: 'verification', question: ar ? 'ما الفرق بين مراجعة الصور وتوثيق الهوية؟' : 'Photo review vs. identity verification?', answer: ar ? 'شارة "صور مُراجَعة" تعني أن فريقنا راجع الصور. توثيق الهوية خطوة منفصلة تتم عبر وثيقة رسمية.' : '"Photos reviewed" means our team checked the photos. Identity verification is a separate step using an official document.'),
          FaqEntry(id: 'f5', category: 'account', question: ar ? 'كيف أحذف حسابي؟' : 'How do I delete my account?', answer: ar ? 'من الإعدادات ← حذف الحساب. يُخفى حسابك فورًا ويُحذف نهائيًا بعد 30 يومًا.' : 'Settings → Delete account. It is hidden immediately and permanently deleted after 30 days.'),
        ];
      });

  Future<String> submitTicket(String category, String message) => _call(() {
        if (message.trim().length < 10) throw const ValidationFailure('message');
        return '#1042';
      }, ms: 700);

  // ───────────── demo data ─────────────
  void _seedMatches() {
    if (_matches.isNotEmpty) return;
    final peers = _all().where((p) => p.gender != myGender).take(4).toList();
    for (var i = 0; i < peers.length; i++) {
      final p = peers[i];
      final convId = i < 2 ? 'c-${p.id}' : null;
      _matches['m-${p.id}'] = MatchItem(id: 'm-${p.id}', peer: p, createdAt: DateTime.now().subtract(Duration(hours: i * 5 + 1)), conversationId: convId, isNew: i >= 2);
      if (convId != null) {
        final t0 = DateTime.now().subtract(Duration(hours: i * 5 + 1));
        _messages[convId] = List.generate(i == 0 ? 26 : 3, (k) {
          final mine = k.isOdd;
          final body = lang == 'ar'
              ? (mine ? 'سعدت بالحديث معك، ما الذي تبحث عنه في شريك الحياة؟' : 'السلام عليكم، سعيدة بالتوافق')
              : (mine ? 'Great talking to you — what matters most to you in a partner?' : 'Hello! Glad we matched');
          return ChatMessage(id: 's$i$k', clientId: 's$i$k', conversationId: convId, fromMe: mine, body: body, sentAt: t0.add(Duration(minutes: k * 3)), status: MessageStatus.read);
        });
      }
    }
  }

  UserProfile _me() => _p('me', myGender == Gender.male ? 'أحمد' : 'سارة', myGender == Gender.male ? 'Ahmed' : 'Sara', 32, myGender, 'AE', 'دبي', 'Dubai', MaritalStatus.neverMarried, Education.master, 'مهندس برمجيات', 'Software engineer', MarriageTimeline.within1Year, 'أحب الرياضة والسفر، وأبحث عن شريك حياة لبناء أسرة مستقرة.', 'Into sports and travel. Looking for a partner to build a stable family together.', ['fitness', 'travel', 'technology'], 0, true, true, completeness: 80);

  List<UserProfile> _all() => [
        _p('d1', 'سارة', 'Sara', 27, Gender.female, 'AE', 'دبي', 'Dubai', MaritalStatus.neverMarried, Education.master, 'مهندسة معمارية', 'Architect', MarriageTimeline.within1Year, 'أحب التصميم والقراءة، وأبحث عن شريك حياة يقدّر الأسرة والطموح معًا.', 'I love design and reading. Looking for a partner who values both family and ambition.', ['reading', 'travel', 'cooking'], 92, true, true),
        _p('d2', 'مريم', 'Mariam', 29, Gender.female, 'SA', 'الرياض', 'Riyadh', MaritalStatus.neverMarried, Education.bachelor, 'طبيبة أسنان', 'Dentist', MarriageTimeline.within6Months, 'هادئة ومحبة للطبيعة. أقدّر الصدق والوضوح منذ البداية.', 'Calm and nature-loving. I value honesty and clarity from the start.', ['volunteering', 'fitness', 'nature'], 86, true, false),
        _p('d3', 'نور', 'Nour', 25, Gender.female, 'EG', 'القاهرة', 'Cairo', MaritalStatus.neverMarried, Education.bachelor, 'محللة بيانات', 'Data analyst', MarriageTimeline.within2Years, 'شغوفة بالتعلم واللغات. أبحث عن علاقة مبنية على الاحترام.', 'Passionate about learning and languages. Looking for a relationship built on respect.', ['technology', 'languages', 'arts'], 81, false, true),
        _p('d4', 'ليلى', 'Layla', 31, Gender.female, 'JO', 'عمّان', 'Amman', MaritalStatus.divorced, Education.master, 'معلمة', 'Teacher', MarriageTimeline.within1Year, 'أم لطفلة، أحب التعليم والطبخ، وأبحث عن شريك ناضج ومسؤول.', 'Mother of one, love teaching and cooking. Looking for a mature, responsible partner.', ['reading', 'cooking', 'volunteering'], 77, true, true),
        _p('d9', 'هند', 'Hind', 28, Gender.female, 'KW', 'الكويت', 'Kuwait City', MaritalStatus.neverMarried, Education.bachelor, 'صيدلانية', 'Pharmacist', MarriageTimeline.within1Year, 'اجتماعية ومحبة للعائلة، أبحث عن شريك يشاركني القيم.', 'Sociable and family-oriented. Looking for someone who shares my values.', ['family', 'travel', 'photography'], 74, true, false),
        _p('d5', 'أحمد', 'Ahmed', 32, Gender.male, 'AE', 'أبوظبي', 'Abu Dhabi', MaritalStatus.neverMarried, Education.master, 'مهندس برمجيات', 'Software engineer', MarriageTimeline.within1Year, 'أحب الرياضة والسفر، وأبحث عن شريكة حياة لبناء أسرة مستقرة.', 'Into sports and travel. Looking for a partner to build a stable family together.', ['technology', 'fitness', 'travel'], 90, true, true),
        _p('d6', 'يوسف', 'Youssef', 30, Gender.male, 'SA', 'جدة', 'Jeddah', MaritalStatus.neverMarried, Education.bachelor, 'محاسب', 'Accountant', MarriageTimeline.within6Months, 'هادئ ومنظم، أقدّر الحوار والتفاهم.', 'Calm and organised. I value dialogue and understanding.', ['reading', 'nature', 'cooking'], 84, true, false),
        _p('d7', 'عمر', 'Omar', 34, Gender.male, 'QA', 'الدوحة', 'Doha', MaritalStatus.divorced, Education.doctorate, 'طبيب', 'Doctor', MarriageTimeline.within1Year, 'طبيب يحب العمل التطوعي. أبحث عن شريكة متفهمة.', 'A doctor who loves volunteering. Looking for an understanding partner.', ['volunteering', 'languages', 'fitness'], 79, false, true),
        _p('d8', 'خالد', 'Khalid', 28, Gender.male, 'KW', 'الكويت', 'Kuwait City', MaritalStatus.neverMarried, Education.bachelor, 'رائد أعمال', 'Entrepreneur', MarriageTimeline.within2Years, 'أدير مشروعي الخاص، وأبحث عن علاقة جادة مبنية على الثقة.', 'I run my own business and want a serious relationship built on trust.', ['technology', 'travel', 'arts'], 75, true, true),
      ];

  UserProfile _p(String id, String nAr, String nEn, int age, Gender g, String iso, String cAr, String cEn, MaritalStatus m, Education e, String jAr, String jEn, MarriageTimeline t, String bAr, String bEn, List<String> ints, int cmp, bool reviewed, bool live, {int completeness = 85}) {
    final ar = lang == 'ar';
    return UserProfile(
      id: id,
      name: ar ? nAr : nEn,
      age: age,
      gender: g,
      countryIso: iso,
      city: ar ? cAr : cEn,
      maritalStatus: m,
      education: e,
      occupation: ar ? jAr : jEn,
      timeline: t,
      bio: ar ? bAr : bEn,
      interests: ints,
      // No remote URLs in demo mode: the image widget renders its placeholder.
      photos: [for (var k = 0; k < 3; k++) ProfilePhoto(id: '$id-p$k')],
      photosReviewed: reviewed,
      livenessVerified: live,
      compatibility: cmp,
      completeness: completeness,
      online: id == 'd1' || id == 'd5',
    );
  }
}

final demoBackendProvider = Provider<DemoBackend>((ref) {
  final b = DemoBackend();
  ref.listen(localeProvider, (_, next) => b.lang = next.languageCode, fireImmediately: true);
  return b;
});

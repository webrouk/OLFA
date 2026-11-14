import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failure.dart';
import '../../core/localization/locale_provider.dart';
import '../models/models.dart';
import '../utils/phone_detect.dart';

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
  final _conv = <String, _DemoConv>{};
  final _sentClientIds = <String>{};
  final _events = StreamController<ChatEvent>.broadcast();
  final _payments = <PaymentRecord>[];
  bool _notificationsRead = false;
  int _otpAttempts = 5;
  VerificationStatus verification = VerificationStatus.pending;
  PrivacySettings privacy = const PrivacySettings();
  bool deletionScheduled = false;
  String? locationCountry; // set by the location step

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
      searchOutsideCountry: plan != PlanCode.free,
      monthlyCompliments: monthlyCompliments,
      complimentsUsed: complimentsUsed,
      complimentsResetAt: DateTime(DateTime.now().year, DateTime.now().month + 1),
      visibleConversations: visibleLimit,
      resetsAt: DateTime.now().toUtc().add(const Duration(days: 1)).copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0).toLocal(),
    );
  }

  Future<Entitlements> entitlements() => _call(entitlementsNow, ms: 200);
  Future<List<PlanInfo>> listPlans() => _call(() => plans.values.toList());

  Future<void> purchase(PlanCode code) => _call(() {
        // Real flow: StoreKit / Play Billing → server receipt validation.
        plan = code;
        _payments.insert(
          0,
          PaymentRecord(
            id: 'TX-${8800 + _payments.length}',
            plan: code,
            store: 'App Store',
            date: DateTime.now(),
            status: PaymentStatus.succeeded,
            amountMinor: code == PlanCode.premium ? 7999 : 3999,
            currency: 'AED',
            reference: 'DEMO${8800 + _payments.length}',
          ),
        );
      }, ms: 900);

  Future<List<PaymentRecord>> payments() => _call(() {
        _seedConsultations();
        // consultation payments appear next to store purchases, like GET /me/payments
        final consult = [
          for (final k in _bookings.where((b) => b.status != ConsultationStatus.awaitingPayment && b.status != ConsultationStatus.expired))
            PaymentRecord(
              id: 'P-${k.id}',
              kind: PaymentKind.consultation,
              plan: plan,
              store: 'Card',
              date: k.createdAt,
              status: k.status == ConsultationStatus.refunded ? PaymentStatus.refunded : PaymentStatus.succeeded,
              amountMinor: k.priceMinor,
              currency: k.currency,
              reference: 'DEMO-${k.id.toUpperCase()}',
              description: '${k.counselorName} · ${k.durationMinutes}′',
            ),
        ];
        return [..._payments, ...consult]..sort((a, b) => b.date.compareTo(a.date));
      });

  // ───────────── discovery ─────────────
  Future<List<UserProfile>> discover(DiscoverFilters f) => _call(() {
        if (f.usesPaidFilters && !plans[plan]!.advancedFilters) {
          throw const EntitlementRequiredFailure('advancedFilters');
        }
        // Same rule as the server: outside the current country needs Plus/Premium.
        final home = locationCountry ?? _me().countryIso;
        if (f.countryIso != null && f.countryIso != home && plan == PlanCode.free) {
          throw const EntitlementRequiredFailure('searchOutsideCountry');
        }
        final onlyHome = f.countryIso == null && plan == PlanCode.free;
        return _all()
            .where((p) => p.gender != myGender) // mutual base preference
            .where((p) => !onlyHome || p.countryIso == home)
            .where((p) => f.nationality == null || p.nationality == f.nationality)
            .where((p) => f.profession.isEmpty || p.occupation == f.profession)
            .where((p) => !_liked.contains(p.id) && !_passed.contains(p.id) && !_blocked.contains(p.id))
            .where((p) => p.age >= f.ageMin && p.age <= f.ageMax)
            .where((p) => f.countryIso == null || p.countryIso == f.countryIso)
            .where((p) => f.maritalStatuses.isEmpty || f.maritalStatuses.contains(p.maritalStatus))
            .where((p) => f.educations.isEmpty || f.educations.contains(p.education))
            .where((p) => f.minCompatibility == null || p.compatibility >= f.minCompatibility!)
            .where((p) => f.height == null || (p.heightCm != null && p.heightCm! >= f.height!.$1 && p.heightCm! <= f.height!.$2))
            .where((p) => f.weight == null || (p.weightKg != null && p.weightKg! >= f.weight!.$1 && p.weightKg! <= f.weight!.$2))
            .toList()
          // nearest first, unknown distance last
          ..sort((a, b) => (a.distanceKm ?? 1 << 30).compareTo(b.distanceKm ?? 1 << 30));
      }, ms: 650);

  Future<UserProfile> profile(String id) => _call(() {
        if (_blocked.contains(id)) throw const ServerFailure('not_found');
        return _all().firstWhere((p) => p.id == id, orElse: () => throw const ServerFailure('not_found'));
      });

  /// Returns the created match, or null when the like is not mutual.
  int complimentsUsed = 0;
  int get monthlyCompliments => switch (plan) { PlanCode.free => 3, PlanCode.plus => 10, PlanCode.premium => 20 };

  Future<MatchItem?> like(String id, {String? compliment}) => _call(() {
        if (_liked.contains(id)) throw const AlreadyActedFailure();
        if (likesUsed >= plans[plan]!.dailyLikes) throw const QuotaExceededFailure('likes');
        if (compliment != null) {
          if (complimentsUsed >= monthlyCompliments) throw const QuotaExceededFailure('compliments');
          complimentsUsed++;
        }
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
  Future<LikesInbox> likesReceived() => _call(() {
        final ps = _all().where((p) => _likesMe.contains(p.id) && !_blocked.contains(p.id) && !_liked.contains(p.id) && p.gender != myGender).toList();
        final now = DateTime.now();
        // Demo: the first one arrived with a compliment (always shown with the sender).
        final compliments = ps.take(1).map((p) => ReceivedLike(profile: p, at: now.subtract(const Duration(hours: 2)), compliment: lang == 'ar' ? 'أعجبتني نبذتك عن العائلة والطموح، تبدو صادقًا وواضحًا.' : 'I loved what you wrote about family and ambition — you seem genuine.')).toList();
        final rest = ps.skip(1).toList();
        return LikesInbox(
          count: ps.length + 8,
          compliments: compliments,
          items: plans[plan]!.seeWhoLikedYou ? [for (var i = 0; i < rest.length; i++) ReceivedLike(profile: rest[i], at: now.subtract(Duration(hours: 5 + i * 9)))] : const [],
          locked: !plans[plan]!.seeWhoLikedYou,
        );
      });

  // ───────────── matches & chat ─────────────
  Future<List<MatchItem>> matches() => _call(() {
        _seedMatches();
        return _matches.values
            .where((m) => !_blocked.contains(m.peer.id) && _conv[m.conversationId]?.section != ConversationSection.unmatched)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });

  Future<String> startConversation(String matchId) => _call(() {
        final m = _matches[matchId]!;
        if (m.conversationId != null) return m.conversationId!;
        if (messagesUsed >= plans[plan]!.dailyMessages) throw const QuotaExceededFailure('messages');
        messagesUsed++;
        final convId = 'c-${m.peer.id}';
        _matches[matchId] = MatchItem(id: m.id, peer: m.peer, createdAt: m.createdAt, conversationId: convId);
        _messages.putIfAbsent(convId, () => []);
        _conv.putIfAbsent(convId, _DemoConv.new);
        return convId;
      });

  // ───────────── conversations (same rules as olfa_conversation_list) ─────────────
  static const inboxDays = 15, inboxWarnAfter = 10, archiveDays = 30, archiveWarnBefore = 7, unmatchedDays = 30;

  int get visibleLimit => switch (plan) { PlanCode.free => 5, PlanCode.plus => 10, PlanCode.premium => -1 };

  Conversation _row(MatchItem m, _DemoConv st) {
    final msgs = _messages[m.conversationId] ?? const <ChatMessage>[];
    final now = DateTime.now();
    final (DateTime? exp, bool warn) = switch (st.section) {
      ConversationSection.inbox => (st.anchor.add(const Duration(days: inboxDays)), now.isAfter(st.anchor.add(const Duration(days: inboxWarnAfter)))),
      ConversationSection.archive => (
          st.anchor.add(const Duration(days: archiveDays)),
          now.isAfter(st.anchor.add(const Duration(days: archiveDays - archiveWarnBefore))),
        ),
      ConversationSection.unmatched => (st.unmatchedAt!.add(const Duration(days: unmatchedDays)), false),
      ConversationSection.consultation => (null, false),
    };
    return Conversation(
      id: m.conversationId!,
      peer: m.peer,
      section: st.section,
      lastMessage: msgs.isEmpty ? null : msgs.last.body,
      lastMessageKind: msgs.isEmpty ? MessageKind.text : msgs.last.kind,
      lastAt: msgs.isEmpty ? m.createdAt : msgs.last.sentAt,
      unread: msgs.where((x) => !x.fromMe && x.status != MessageStatus.read).length,
      expiresAt: exp,
      expiringSoon: warn,
      rematch: st.rematch,
      unmatchedByMe: st.section == ConversationSection.unmatched ? st.unmatchedByMe : null,
    );
  }

  ConversationIndex _index() {
    _seedMatches();
    final rows = <Conversation>[];
    for (final m in _matches.values) {
      final id = m.conversationId;
      if (id == null || _blocked.contains(m.peer.id)) continue;
      rows.add(_row(m, _conv.putIfAbsent(id, _DemoConv.new)));
    }
    _seedConsultations();
    // client side shows the counselor's name; the counselor desk shows the client's
    for (final k in [..._bookings, ..._desk].where((k) => k.conversationId != null)) {
      final msgs = _messages[k.conversationId] ?? const <ChatMessage>[];
      rows.add(Conversation(
        id: k.conversationId!,
        section: ConversationSection.consultation,
        counselor: CounselorChatInfo(consultationId: k.id, name: k.clientName ?? k.counselorName, status: k.status, scheduledAt: k.scheduledAt),
        lastMessage: msgs.isEmpty ? null : msgs.last.body,
        lastAt: msgs.isEmpty ? k.createdAt : msgs.last.sentAt,
        unread: msgs.where((x) => !x.fromMe && x.status != MessageStatus.read).length,
      ));
    }
    rows.sort((a, b) => b.lastAt!.compareTo(a.lastAt!));
    final visible = <Conversation>[], locked = <LockedConversation>[];
    var pos = 0;
    for (final c in rows) {
      final counted = c.section == ConversationSection.inbox || c.section == ConversationSection.archive;
      if (counted && visibleLimit >= 0 && pos++ >= visibleLimit) {
        locked.add(LockedConversation(id: c.id, section: c.section));
      } else {
        visible.add(c);
      }
    }
    return ConversationIndex(visible: visible, locked: locked, visibleLimit: visibleLimit);
  }

  Future<ConversationIndex> conversationIndex() => _call(_index);

  Future<Conversation> conversation(String id) => _call(() {
        final ix = _index();
        if (ix.locked.any((c) => c.id == id)) throw const EntitlementRequiredFailure('visibleConversations');
        return ix.visible.firstWhere((c) => c.id == id, orElse: () => throw const ServerFailure('not_found'));
      }, ms: 150);

  _DemoConv _state(String id) => _conv[id] ?? (throw const ServerFailure('not_found'));

  Future<void> setFolder(String id, ConversationSection folder) => _call(() {
        final st = _state(id);
        if (st.section == ConversationSection.unmatched) throw const ServerFailure('conversation_closed');
        st
          ..section = folder
          ..anchor = DateTime.now();
        _events.add(ChatEvent.moved(id, folder));
      }, ms: 200);

  Future<void> unmatch(String id) => _call(() {
        final st = _state(id);
        if (st.section == ConversationSection.unmatched) throw const ServerFailure('invalid_state');
        st
          ..section = ConversationSection.unmatched
          ..unmatchedAt = DateTime.now()
          ..unmatchedByMe = true;
        _events.add(ChatEvent.moved(id, ConversationSection.unmatched));
      });

  /// One request per conversation, ever. In the demo the other person accepts after a moment.
  Future<void> requestRematch(String id) => _call(() {
        final st = _state(id);
        if (st.section != ConversationSection.unmatched) throw const ServerFailure('invalid_state');
        if (st.rematch != null) throw const ServerFailure('rematch_used');
        st.rematch = const RematchInfo(status: RematchStatus.pending, byMe: true);
        _events.add(ChatEvent.moved(id, ConversationSection.unmatched));
        Timer(const Duration(seconds: 4), () {
          if (st.rematch?.status != RematchStatus.pending) return;
          _acceptRematch(id, st, byMe: true);
        });
      });

  Future<void> respondRematch(String id, bool accept) => _call(() {
        final st = _state(id);
        if (st.rematch?.status != RematchStatus.pending || st.rematch!.byMe) throw const ServerFailure('invalid_state');
        if (accept) {
          _acceptRematch(id, st, byMe: false);
        } else {
          st.rematch = const RematchInfo(status: RematchStatus.declined, byMe: false);
          _events.add(ChatEvent.moved(id, ConversationSection.unmatched));
        }
      });

  void _acceptRematch(String id, _DemoConv st, {required bool byMe}) {
    st
      ..rematch = RematchInfo(status: RematchStatus.accepted, byMe: byMe)
      ..section = ConversationSection.inbox
      ..anchor = DateTime.now()
      ..unmatchedAt = null;
    _events.add(ChatEvent.moved(id, ConversationSection.inbox));
  }

  /// Cursor pagination: newest first page, [before] loads older.
  Future<({List<ChatMessage> items, bool hasMore})> messages(String convId, {DateTime? before, int limit = 20}) => _call(() {
        final all = _messages[convId] ?? const <ChatMessage>[];
        final older = before == null ? all : all.where((m) => m.sentAt.isBefore(before)).toList();
        final start = (older.length - limit).clamp(0, older.length);
        return (items: older.sublist(start), hasMore: start > 0);
      });

  Future<ChatMessage> send(String convId, String clientId, String body, {OutgoingMedia? media}) => _call(() {
        final list = _messages.putIfAbsent(convId, () => []);
        if (_sentClientIds.contains(clientId)) {
          return list.firstWhere((m) => m.clientId == clientId); // idempotent retry
        }
        final peerId = convId.substring(2);
        if (_blocked.contains(peerId)) throw const ServerFailure('blocked');
        final k = _bookings.where((b) => b.conversationId == convId).firstOrNull;
        if (k != null && k.status != ConsultationStatus.confirmed && k.status != ConsultationStatus.completed) throw const ServerFailure('conversation_closed');
        final st = _conv[convId];
        if (st?.section == ConversationSection.unmatched) throw const ServerFailure('conversation_closed');
        if (_index().locked.any((c) => c.id == convId)) throw const EntitlementRequiredFailure('visibleConversations');
        if (media?.isVoice ?? false) {
          final q = _voiceLeft(convId);
          if (q.remaining == 0) throw const QuotaExceededFailure('voice');
        }
        st?.anchor = DateTime.now(); // a message keeps the chat (inbox and archive)
        _sentClientIds.add(clientId);
        final msg = ChatMessage(
          id: 'srv-$clientId',
          clientId: clientId,
          conversationId: convId,
          fromMe: true,
          body: body.trim(),
          sentAt: DateTime.now(),
          status: MessageStatus.sent,
          kind: media == null ? MessageKind.text : (media.isVoice ? MessageKind.voice : MessageKind.image),
          containsPhone: containsPhoneNumber(body),
          attachments: media == null
              ? const []
              : media.isVoice
                  ? [ChatAttachment(kind: MessageKind.voice, localPath: media.voice!.path, durationMs: media.voice!.durationMs, waveform: media.voice!.waveform)]
                  : [for (final f in media.files) ChatAttachment(kind: MessageKind.image, localPath: f.path, width: f.width, height: f.height)],
        );
        list.add(msg);
        _scheduleReply(convId, msg);
        return msg;
      }, ms: 250);

  ({int limit, int? remaining}) _voiceLeft(String convId) {
    final limit = switch (plan) { PlanCode.free => 10, PlanCode.plus => 30, PlanCode.premium => -1 };
    if (limit < 0 || convId.startsWith('k-')) return (limit: -1, remaining: null);
    final used = (_messages[convId] ?? const <ChatMessage>[]).where((m) => m.fromMe && m.kind == MessageKind.voice).length;
    return (limit: limit, remaining: (limit - used).clamp(0, limit).toInt());
  }

  Future<({int limit, int? remaining})> voiceQuota(String convId) => _call(() => _voiceLeft(convId), ms: 100);

  /// Names and message text, like GET /conversations/search.
  Future<ChatSearchResult> searchChats(String q) => _call(() {
        final t = q.trim().toLowerCase();
        if (t.length < 2) return ChatSearchResult.empty;
        final ix = _index();
        final ids = ix.visible.where((c) => c.title.toLowerCase().contains(t)).map((c) => c.id).toList();
        final allowed = ix.visible.map((c) => c.id).toSet();
        final msgs = [
          for (final e in _messages.entries)
            if (allowed.contains(e.key))
              for (final m in e.value)
                if (m.kind == MessageKind.text && m.body.toLowerCase().contains(t)) m,
        ]..sort((a, b) => b.sentAt.compareTo(a.sentAt));
        return ChatSearchResult(conversationIds: ids, messages: msgs.take(30).toList());
      }, ms: 120);

  void _scheduleReply(String convId, ChatMessage mine) {
    Timer(const Duration(milliseconds: 700), () {
      if (privacy.readReceipts) _events.add(ChatEvent.readReceipt(convId, mine.clientId)); // reciprocal
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

  // ───────────── consultations (demo data — sample counselors, clearly not real) ─────────────
  final _bookings = <Consultation>[];
  final _desk = <Consultation>[];
  Counselor? _myCounselor;
  int _bookingSeq = 0;

  CounselorOffering _o(String id, ConsultationService s, String lang, int d, int price) =>
      CounselorOffering(id: id, service: s, language: lang, durationMinutes: d, priceMinor: price, currency: 'AED');

  List<Counselor> _counselorsAll() {
    final ar = lang == 'ar';
    const s = ConsultationService.values;
    return [
      Counselor(
        id: 'k1',
        kind: CounselorKind.familyCounselor,
        name: ar ? 'د. هدى المنصوري (نموذج)' : 'Dr. Huda Al Mansoori (sample)',
        headline: ar ? 'مستشارة أسرية وزوجية' : 'Marriage & family counselor',
        bio: ar ? 'خبرة في الإرشاد قبل الزواج وتحسين الحوار بين الزوجين وحل الخلافات الأسرية بأسلوب عملي.' : 'Experienced in premarital guidance, couple communication and resolving family conflict with practical tools.',
        yearsExperience: 12,
        licenseAuthority: ar ? 'هيئة تنمية المجتمع' : 'Community Development Authority',
        licenseCountry: 'AE',
        languages: const ['ar', 'en'],
        services: [s[0], s[1], s[2]],
        offerings: [
          _o('o11', ConsultationService.premarital, 'ar', 45, 25000),
          _o('o12', ConsultationService.marital, 'ar', 60, 30000),
          _o('o13', ConsultationService.marital, 'en', 60, 30000),
          _o('o14', ConsultationService.family, 'ar', 90, 42000),
        ],
        ratingAvg: 4.9,
        ratingCount: 128,
      ),
      Counselor(
        id: 'k2',
        kind: CounselorKind.psychologist,
        name: ar ? 'د. عمر الخطيب (نموذج)' : 'Dr. Omar Al Khatib (sample)',
        headline: ar ? 'أخصائي نفسي إكلينيكي' : 'Clinical psychologist',
        bio: ar ? 'يساعد الأفراد والأزواج على التعامل مع القلق والضغوط والتعافي بعد الانفصال.' : 'Helps individuals and couples with anxiety, stress and recovery after separation.',
        yearsExperience: 9,
        licenseAuthority: ar ? 'هيئة الصحة بدبي' : 'Dubai Health Authority',
        licenseCountry: 'AE',
        languages: const ['ar', 'en', 'fr'],
        services: [s[4], s[5], s[1]],
        offerings: [
          _o('o21', ConsultationService.individual, 'ar', 45, 28000),
          _o('o22', ConsultationService.divorceRecovery, 'en', 60, 35000),
          _o('o23', ConsultationService.marital, 'fr', 60, 35000),
        ],
        ratingAvg: 4.8,
        ratingCount: 86,
      ),
      Counselor(
        id: 'k3',
        kind: CounselorKind.familyCounselor,
        name: ar ? 'أ. ريم السيد (نموذج)' : 'Reem Elsayed (sample)',
        headline: ar ? 'مستشارة تربوية وأسرية' : 'Parenting & family counselor',
        bio: ar ? 'تركّز على التربية الإيجابية والتوازن بين الحياة الزوجية والأبناء.' : 'Focused on positive parenting and balancing married life with children.',
        yearsExperience: 7,
        licenseAuthority: ar ? 'وزارة التضامن الاجتماعي' : 'Ministry of Social Solidarity',
        licenseCountry: 'EG',
        languages: const ['ar'],
        services: [s[3], s[2]],
        offerings: [_o('o31', ConsultationService.parenting, 'ar', 30, 15000), _o('o32', ConsultationService.family, 'ar', 60, 24000)],
        ratingAvg: 4.7,
        ratingCount: 41,
      ),
    ];
  }

  void _seedConsultations() {
    if (_bookingSeq > 0) return;
    _bookingSeq = 2;
    final c = _counselorsAll();
    final now = DateTime.now();
    Consultation mk(String id, Counselor k, CounselorOffering o, ConsultationStatus st, {String? conv, DateTime? at, int? rating}) => Consultation(
          id: id,
          counselorId: k.id,
          counselorName: k.name,
          service: o.service,
          language: o.language,
          durationMinutes: o.durationMinutes,
          priceMinor: o.priceMinor,
          currency: o.currency,
          status: st,
          createdAt: now.subtract(const Duration(days: 2)),
          scheduledAt: at,
          conversationId: conv,
          myRating: rating,
        );
    _bookings
      ..add(mk('b1', c[0], c[0].offerings[1], ConsultationStatus.confirmed, conv: 'k-b1', at: now.add(const Duration(days: 1, hours: 3))))
      ..add(mk('b2', c[1], c[1].offerings[0], ConsultationStatus.completed, conv: 'k-b2', at: now.subtract(const Duration(days: 3))));
    final ar = lang == 'ar';
    _messages['k-b1'] = [
      ChatMessage(
        id: 'kb1', clientId: 'kb1', conversationId: 'k-b1', fromMe: false, status: MessageStatus.delivered, sentAt: now.subtract(const Duration(hours: 5)),
        body: ar ? 'أهلًا بك، أنا د. هدى. يسعدني مساعدتك. هل تود أن تخبرني باختصار عن موضوع الجلسة؟' : "Welcome, I'm Dr. Huda. Happy to help — could you tell me briefly what you'd like to focus on?",
      ),
    ];
    _messages['k-b2'] = [
      ChatMessage(id: 'kb2', clientId: 'kb2', conversationId: 'k-b2', fromMe: false, status: MessageStatus.read, sentAt: now.subtract(const Duration(days: 3)), body: ar ? 'شكرًا لك على الجلسة، أتمنى لك التوفيق.' : 'Thank you for the session — wishing you all the best.'),
    ];
  }

  Future<List<Counselor>> counselors(CounselorKind? kind, ConsultationService? svc, String? language, int? duration) => _call(() {
        return _counselorsAll()
            .where((c) => kind == null || c.kind == kind)
            .where((c) => c.offerings.any((o) => (svc == null || o.service == svc) && (language == null || o.language == language) && (duration == null || o.durationMinutes == duration)))
            .toList();
      });

  Future<Counselor> counselor(String id) => _call(() {
        final c = _counselorsAll().firstWhere((x) => x.id == id, orElse: () => throw const ServerFailure('not_found'));
        final ar = lang == 'ar';
        return Counselor(
          id: c.id, kind: c.kind, name: c.name, headline: c.headline, bio: c.bio, yearsExperience: c.yearsExperience, licenseAuthority: c.licenseAuthority,
          licenseCountry: c.licenseCountry, languages: c.languages, services: c.services, offerings: c.offerings, ratingAvg: c.ratingAvg, ratingCount: c.ratingCount,
          reviews: [
            CounselorReview(rating: 5, by: ar ? 'مريم' : 'Mariam', comment: ar ? 'نصائح عملية غيّرت طريقة حوارنا.' : 'Practical advice that changed how we talk.', createdAt: DateTime.now().subtract(const Duration(days: 4))),
            CounselorReview(rating: 5, by: ar ? 'خالد' : 'Khaled', comment: ar ? 'مستمع رائع ومتفهم.' : 'A wonderful, understanding listener.', createdAt: DateTime.now().subtract(const Duration(days: 11))),
            CounselorReview(rating: 4, by: ar ? 'نور' : 'Nour', comment: ar ? 'جلسة مفيدة جدًا.' : 'A very helpful session.', createdAt: DateTime.now().subtract(const Duration(days: 20))),
          ],
        );
      });

  Future<BookingIntent> book(String offeringId, String? note) => _call(() {
        _seedConsultations();
        final k = _counselorsAll().firstWhere((c) => c.offerings.any((o) => o.id == offeringId), orElse: () => throw const ServerFailure('not_found'));
        if (_bookings.any((b) => b.counselorId == k.id && (b.status == ConsultationStatus.awaitingPayment || b.status == ConsultationStatus.paid || b.status == ConsultationStatus.confirmed))) {
          throw const ServerFailure('conflict');
        }
        final o = k.offerings.firstWhere((x) => x.id == offeringId);
        final id = 'b${++_bookingSeq}';
        final exp = DateTime.now().add(const Duration(minutes: 30));
        _bookings.insert(0, Consultation(
          id: id, counselorId: k.id, counselorName: k.name, service: o.service, language: o.language, durationMinutes: o.durationMinutes,
          priceMinor: o.priceMinor, currency: o.currency, status: ConsultationStatus.awaitingPayment, createdAt: DateTime.now(), expiresAt: exp, note: note,
        ));
        return BookingIntent(consultationId: id, amountMinor: o.priceMinor, currency: o.currency, expiresAt: exp, provider: 'test');
      });

  void _setBooking(String id, Consultation Function(Consultation k) f) {
    final i = _bookings.indexWhere((b) => b.id == id);
    if (i < 0) throw const ServerFailure('not_found');
    _bookings[i] = f(_bookings[i]);
  }

  Consultation _with(Consultation k, {ConsultationStatus? status, String? conversationId, DateTime? scheduledAt, int? myRating}) => Consultation(
        id: k.id, counselorId: k.counselorId, counselorName: k.counselorName, clientName: k.clientName, service: k.service, language: k.language,
        durationMinutes: k.durationMinutes, priceMinor: k.priceMinor, currency: k.currency, status: status ?? k.status, createdAt: k.createdAt,
        note: k.note, scheduledAt: scheduledAt ?? k.scheduledAt, expiresAt: k.expiresAt, conversationId: conversationId ?? k.conversationId, myRating: myRating ?? k.myRating,
      );

  /// Demo payment: succeeds immediately; then the (sample) counselor confirms and writes first.
  Future<void> payBooking(String id) => _call(() {
        _setBooking(id, (k) {
          if (k.status != ConsultationStatus.awaitingPayment) throw const ServerFailure('invalid_state');
          return _with(k, status: ConsultationStatus.paid);
        });
        Timer(const Duration(seconds: 3), () {
          final k = _bookings.where((b) => b.id == id && b.status == ConsultationStatus.paid).firstOrNull;
          if (k == null) return;
          final conv = 'k-$id';
          _setBooking(id, (k) => _with(k, status: ConsultationStatus.confirmed, conversationId: conv, scheduledAt: DateTime.now().add(const Duration(days: 1))));
          _messages[conv] = [
            ChatMessage(id: 'k$id', clientId: 'k$id', conversationId: conv, fromMe: false, status: MessageStatus.delivered, sentAt: DateTime.now(),
                body: lang == 'ar' ? 'مرحبًا، تم تأكيد موعدك. أخبرني بما تود التركيز عليه في الجلسة.' : 'Hello, your session is confirmed. Tell me what you would like to focus on.'),
          ];
          _events.add(ChatEvent.moved(conv, ConversationSection.consultation));
        });
      }, ms: 1200);

  Future<List<Consultation>> myConsultations() => _call(() {
        _seedConsultations();
        return List.unmodifiable(_bookings);
      });

  Future<void> cancelConsultation(String id) => _call(() => _setBooking(id, (k) {
        if (!k.canCancel) throw const ServerFailure('invalid_state');
        return _with(k, status: k.status == ConsultationStatus.paid ? ConsultationStatus.refunded : ConsultationStatus.cancelled);
      }));

  Future<void> reviewConsultation(String id, int rating) => _call(() => _setBooking(id, (k) {
        if (k.status != ConsultationStatus.completed) throw const ServerFailure('invalid_state');
        if (k.myRating != null) throw const ServerFailure('conflict');
        return _with(k, myRating: rating);
      }));

  // counselor side (demo: moderation approves after a few seconds)
  Future<Counselor?> myCounselor() => _call(() => _myCounselor, ms: 200);

  Future<Counselor> applyCounselor(CounselorKind kind, String name, String headline, String bio, int years, String authority, String country, List<String> langs, List<ConsultationService> svcs) => _call(() {
        final c = Counselor(id: 'me', kind: kind, name: name, headline: headline, bio: bio, yearsExperience: years, licenseAuthority: authority, licenseCountry: country, languages: langs, services: svcs, offerings: _myCounselor?.offerings ?? const [], status: CounselorStatus.pending);
        _myCounselor = c;
        Timer(const Duration(seconds: 5), () => _myCounselor = _counselorWith(status: CounselorStatus.approved));
        return c;
      }, ms: 900);

  Counselor _counselorWith({CounselorStatus? status, List<CounselorOffering>? offerings}) {
    final c = _myCounselor!;
    return Counselor(id: c.id, kind: c.kind, name: c.name, headline: c.headline, bio: c.bio, yearsExperience: c.yearsExperience, licenseAuthority: c.licenseAuthority, licenseCountry: c.licenseCountry, languages: c.languages, services: c.services, offerings: offerings ?? c.offerings, status: status ?? c.status);
  }

  Future<void> saveOffering(ConsultationService svc, String language, int duration, int price, String currency) => _call(() {
        final c = _myCounselor;
        if (c?.status != CounselorStatus.approved) throw const ServerFailure('invalid_state');
        final rest = c!.offerings.where((o) => !(o.service == svc && o.language == language && o.durationMinutes == duration));
        _myCounselor = _counselorWith(offerings: [...rest, CounselorOffering(id: 'mo${DateTime.now().microsecondsSinceEpoch}', service: svc, language: language, durationMinutes: duration, priceMinor: price, currency: currency)]);
      });

  Future<List<Consultation>> desk() => _call(() {
        if (_myCounselor?.status != CounselorStatus.approved) throw const ServerFailure('invalid_state');
        if (_desk.isEmpty) {
          final ar = lang == 'ar';
          Consultation d(String id, String client, ConsultationService s, int dur, int price) => Consultation(
              id: id, counselorId: 'me', counselorName: _myCounselor!.name, clientName: client, service: s, language: 'ar', durationMinutes: dur,
              priceMinor: price, currency: 'AED', status: ConsultationStatus.paid, createdAt: DateTime.now().subtract(const Duration(hours: 2)),
              note: ar ? 'نرغب في تحسين أسلوب الحوار بيننا.' : 'We would like to improve how we communicate.');
          _desk.addAll([d('dk1', ar ? 'عميل نموذجي ١' : 'Sample client 1', ConsultationService.marital, 60, 30000), d('dk2', ar ? 'عميل نموذجي ٢' : 'Sample client 2', ConsultationService.premarital, 45, 25000)]);
        }
        return List.unmodifiable(_desk);
      });

  void _setDesk(String id, ConsultationStatus st, {String? conv, DateTime? at}) {
    final i = _desk.indexWhere((x) => x.id == id);
    if (i < 0) throw const ServerFailure('not_found');
    _desk[i] = _with(_desk[i], status: st, conversationId: conv, scheduledAt: at);
  }

  Future<String> confirmBooking(String id, DateTime at) => _call(() {
        final conv = 'k-$id';
        _setDesk(id, ConsultationStatus.confirmed, conv: conv, at: at);
        _messages.putIfAbsent(conv, () => []);
        return conv;
      });
  Future<void> declineBooking(String id) => _call(() => _setDesk(id, ConsultationStatus.refunded));
  Future<void> completeBooking(String id) => _call(() => _setDesk(id, ConsultationStatus.completed));

  // ───────────── safety ─────────────
  Future<void> report(String userId, String reason, {bool block = false}) => _call(() {
        if (block) _blocked.add(userId);
      });

  Future<void> block(String userId) => _call(() => _blocked.add(userId));
  Future<int> blockedCount() => _call(() => _blocked.length);
  Future<List<BlockedUser>> blockedUsers() => _call(() {
        final all = _all();
        return [
          for (final id in _blocked)
            BlockedUser(userId: id, name: all.where((p) => p.id == id).firstOrNull?.name ?? id, blockedAt: DateTime.now().subtract(const Duration(days: 2))),
        ];
      });
  Future<void> unblock(String userId) => _call(() => _blocked.remove(userId));

  // ───────────── devices (demo: this phone + one tablet) ─────────────
  final _devices = <DeviceSession>[
    DeviceSession(id: 's-this', platform: 'ios', appVersion: '0.3.0', createdAt: DateTime.now().subtract(const Duration(days: 20)), lastUsedAt: DateTime.now(), current: true),
    DeviceSession(id: 's-tab', platform: 'android', appVersion: '0.3.0', createdAt: DateTime.now().subtract(const Duration(days: 40)), lastUsedAt: DateTime.now().subtract(const Duration(days: 3))),
  ];
  Future<List<DeviceSession>> devices() => _call(() => List.unmodifiable(_devices));
  Future<void> signOutDevice(String id) => _call(() => _devices.removeWhere((d) => d.id == id && !d.current));

  // ───────────── freeze ─────────────
  bool frozen = false;
  Future<void> freeze() => _call(() => frozen = true, ms: 600);
  Future<void> unfreeze() => _call(() => frozen = false, ms: 600);

  // ───────────── notifications ─────────────
  final _readNotifications = <String>{};
  final _removedNotifications = <String>{};

  Future<List<AppNotification>> notifications() => _call(() {
        final now = DateTime.now();
        final ar = lang == 'ar';
        AppNotification n(String id, NotificationKind k, String tAr, String tEn, String? bAr, String? bEn, Duration ago, {Map<String, String> data = const {}, bool read = false}) => AppNotification(
              id: id,
              kind: k,
              title: ar ? tAr : tEn,
              body: ar ? bAr : bEn,
              data: data,
              createdAt: now.subtract(ago),
              read: read || _notificationsRead || _readNotifications.contains(id),
            );
        return [
          n('n0', NotificationKind.compliment, 'رسالة إطراء من نور', 'A compliment from Nour', '«ابتسامتك جميلة وكلامك عن التطوع أعجبني»', '“Lovely smile — I liked what you wrote about volunteering”', const Duration(minutes: 1)),
          n('n1', NotificationKind.match, 'توافق جديد مع سارة', 'New match with Sara', 'أعجب كلٌّ منكما بالآخر — ابدأ المحادثة', 'You both liked each other — say hello', const Duration(minutes: 2), data: const {'conversationId': 'c-d1'}),
          n('n2', NotificationKind.like, 'لديك 3 إعجابات جديدة', 'You have 3 new likes', 'اطّلع على من أعجب بك', 'See who liked you', const Duration(hours: 1)),
          n('n6', NotificationKind.chatExpiring, 'محادثة ستُحذف قريبًا', 'A chat expires soon', 'أرسل رسالة لتبقى المحادثة', 'Send a message to keep it', const Duration(hours: 2)),
          n('n3', NotificationKind.verification, 'تم اعتماد ملفك وصورك', 'Your profile and photos were approved', 'ملفك ظاهر الآن لمن يناسبك', 'Your profile is now live', const Duration(hours: 3), read: true),
          n('n7', NotificationKind.consultation, 'تم تأكيد استشارتك', 'Consultation confirmed', 'يمكنك الآن التحدث مع الاستشاري', 'You can now chat with your counselor', const Duration(hours: 20), data: const {'conversationId': 'k-b1'}, read: true),
          n('n4', NotificationKind.message, 'رسالة جديدة من مريم', 'New message from Mariam', 'لديك رسالة جديدة', 'You have a new message', const Duration(days: 1), read: true),
          n('n5', NotificationKind.reminder, 'أكمل ملفك لزيادة فرص التوافق', 'Complete your profile to get better matches', 'أضف الطول والاهتمامات وصورة ثالثة', 'Add your height, interests and a third photo', const Duration(days: 4), read: true),
        ].where((x) => !_removedNotifications.contains(x.id)).toList();
      });

  Future<void> markAllNotificationsRead() => _call(() => _notificationsRead = true, ms: 150);
  Future<void> markNotificationRead(String id) => _call(() => _readNotifications.add(id), ms: 80);
  Future<void> removeNotification(String id) => _call(() => _removedNotifications.add(id), ms: 80);

  // ───────────── settings & support ─────────────
  Future<PrivacySettings> getPrivacy() => _call(() => privacy, ms: 200);
  Future<PrivacySettings> setPrivacy(PrivacySettings s) => _call(() {
        if (s.incognito && plan != PlanCode.premium) throw const EntitlementRequiredFailure('incognito');
        return privacy = s;
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
    final peers = _all().where((p) => p.gender != myGender).take(5).toList();
    final now = DateTime.now();
    // Demo spread: 0 inbox · 1 inbox, quiet for 11 days (warning) · 2 archived 24 days ago (warning)
    // · 3 unmatched by the other person · 4 new match without a chat.
    final ages = [const Duration(hours: 1), const Duration(days: 11), const Duration(days: 24), const Duration(days: 3), const Duration(hours: 16)];
    for (var i = 0; i < peers.length; i++) {
      final p = peers[i];
      final convId = i < 4 ? 'c-${p.id}' : null;
      final t0 = now.subtract(ages[i]);
      _matches['m-${p.id}'] = MatchItem(id: 'm-${p.id}', peer: p, createdAt: t0.subtract(const Duration(hours: 2)), conversationId: convId, isNew: i == 4);
      if (convId != null) {
        _conv[convId] = _DemoConv()
          ..anchor = t0
          ..section = switch (i) { 2 => ConversationSection.archive, 3 => ConversationSection.unmatched, _ => ConversationSection.inbox }
          ..unmatchedAt = i == 3 ? t0 : null
          ..unmatchedByMe = false;
        _messages[convId] = List.generate(i == 0 ? 26 : 3, (k) {
          final mine = k.isOdd;
          final body = lang == 'ar'
              ? (mine ? 'سعدت بالحديث معك، ما الذي تبحث عنه في شريك الحياة؟' : 'السلام عليكم، سعيدة بالتوافق')
              : (mine ? 'Great talking to you — what matters most to you in a partner?' : 'Hello! Glad we matched');
          return ChatMessage(id: 's$i$k', clientId: 's$i$k', conversationId: convId, fromMe: mine, body: body, sentAt: t0.subtract(Duration(minutes: (i == 0 ? 26 : 3) * 3 - k * 3)), status: MessageStatus.read);
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
      // stored as a reference key, like the server (labels come from reference_data)
      occupation: occupationByKey(jEn.toLowerCase().replaceAll(' ', '_'))?.key ?? (ar ? jAr : jEn),
      nationality: countryOrNull(iso)?.nationality,
      // demo distances from Dubai, rounded like the server (≥1 km)
      distanceKm: const {'AE': 12, 'SA': 870, 'EG': 2420, 'JO': 2050, 'KW': 850, 'QA': 380, 'OM': 340, 'BH': 480}[iso] ?? (id.hashCode % 40 + 3),
      // demo sample values (deterministic per profile)
      heightCm: (g == Gender.female ? 155 : 168) + (id.codeUnits.fold<int>(0, (x, c) => x + c) % 18),
      weightKg: (g == Gender.female ? 52 : 68) + (id.codeUnits.fold<int>(0, (x, c) => x * 7 + c) % 20),
      timeline: t,
      bio: ar ? bAr : bEn,
      interests: ints,
      // No remote URLs in demo mode: the image widget renders its placeholder.
      photos: [for (var k = 0; k < 3; k++) ProfilePhoto(id: '$id-p$k')],
      photosReviewed: reviewed,
      livenessVerified: live,
      compatibility: cmp,
      completeness: completeness,
      // reciprocal, like the server: hiding your own status hides everyone's from you
      online: privacy.showOnline && (id == 'd1' || id == 'd5'),
    );
  }
}

final demoBackendProvider = Provider<DemoBackend>((ref) {
  final b = DemoBackend();
  ref.listen(localeProvider, (_, next) => b.lang = next.languageCode, fireImmediately: true);
  return b;
});

/// Per-conversation lifecycle state kept by the demo server.
class _DemoConv {
  ConversationSection section = ConversationSection.inbox;
  DateTime anchor = DateTime.now();
  DateTime? unmatchedAt;
  bool unmatchedByMe = false;
  RematchInfo? rematch;
}

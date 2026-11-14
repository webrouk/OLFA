import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../../messaging/data/messaging_repository_impl.dart';
import '../application/consultation_providers.dart';
import '../data/consultations_repository_impl.dart';
import '../domain/consultations_repository.dart';
import 'consult_labels.dart';

/// C1 — Family & marital consultations: directory filtered by counselor
/// type, service, language and duration.
class ConsultationsScreen extends ConsumerWidget {
  const ConsultationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final q = ref.watch(counselorQueryProvider);
    final ctrl = ref.read(counselorQueryProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.screenConsultations),
        actions: [OlfaIconButton(icon: Icons.event_note_outlined, tooltip: l.screenMyConsultations, onPressed: () => context.push(Routes.myConsultations)), const SizedBox(width: 6)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          InfoBanner(text: l.consultIntro, icon: Icons.support_agent_rounded, accent: true),
          const SizedBox(height: 16),
          ChoiceWrap<CounselorKind?>(
            options: const [null, CounselorKind.familyCounselor, CounselorKind.psychologist],
            label: (k) => k == null ? l.all : kindLabel(l, k),
            isSelected: (k) => q.kind == k,
            onTap: (k) => ctrl.set(q.copyWith(kind: () => k)),
          ),
          const SizedBox(height: 16),
          Text(l.serviceType, style: context.type.inputLabel),
          const SizedBox(height: 8),
          ChoiceWrap<ConsultationService?>(
            options: [null, ...ConsultationService.values],
            label: (s) => s == null ? l.all : serviceLabel(l, s),
            isSelected: (s) => q.service == s,
            onTap: (s) => ctrl.set(q.copyWith(service: () => s)),
          ),
          const SizedBox(height: 16),
          Text(l.serviceLanguage, style: context.type.inputLabel),
          const SizedBox(height: 8),
          ChoiceWrap<String?>(
            options: const [null, 'ar', 'en', 'fr', 'tr', 'ur'],
            label: (c) => c == null ? l.all : languageName(context, c),
            isSelected: (c) => q.language == c,
            onTap: (c) => ctrl.set(q.copyWith(language: () => c)),
          ),
          const SizedBox(height: 16),
          Text(l.sessionDuration, style: context.type.inputLabel),
          const SizedBox(height: 8),
          ChoiceWrap<int?>(
            options: const [null, ...kDurations],
            label: (d) => d == null ? l.all : l.minutesShort(d),
            isSelected: (d) => q.durationMinutes == d,
            onTap: (d) => ctrl.set(q.copyWith(durationMinutes: () => d)),
          ),
          const SizedBox(height: 18),
          AsyncView<List<Counselor>>(
            value: ref.watch(counselorsProvider),
            onRetry: () => ref.invalidate(counselorsProvider),
            loading: const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: OlfaColors.primary))),
            data: (list) => list.isEmpty
                ? Padding(padding: const EdgeInsets.all(24), child: Text(l.noCounselors, textAlign: TextAlign.center, style: context.type.bodyMedium.copyWith(color: OlfaColors.textMuted)))
                : Column(children: [for (final c in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: _CounselorCard(c: c))]),
          ),
          const SizedBox(height: 8),
          SecondaryButton(label: l.becomeCounselor, icon: Icons.badge_outlined, onPressed: () => context.push(Routes.counselorApply)),
        ],
      ),
    );
  }
}

class _CounselorCard extends StatelessWidget {
  const _CounselorCard({required this.c});
  final Counselor c;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final from = c.offerings.isEmpty ? null : c.offerings.reduce((a, b) => a.priceMinor <= b.priceMinor ? a : b);
    return InkWell(
      borderRadius: OlfaRadius.all(OlfaRadius.card),
      onTap: () => context.push(Routes.counselorDetails(c.id)),
      child: OlfaCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CounselorAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Text(c.name, style: t.h3, overflow: TextOverflow.ellipsis)), const SizedBox(width: 6), VerifiedBadge(size: 16, semanticLabel: l.licenseVerified)]),
                Text('${c.headline} · ${l.yearsCount(c.yearsExperience)}', style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [StarRow(value: c.ratingAvg, size: 13), const SizedBox(width: 6), Text('${c.ratingAvg.toStringAsFixed(1)} (${c.ratingCount})', style: t.caption)]),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in c.services.take(3)) OlfaTag(serviceLabel(l, s)),
            for (final lg in c.languages) OlfaTag(languageName(context, lg), style: OlfaTagStyle.accent),
          ]),
          if (from != null) ...[
            const SizedBox(height: 10),
            Text(l.priceFrom(money(context, from.priceMinor, from.currency), from.durationMinutes), style: t.bodySmall.copyWith(fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }
}

/// C2 — Counselor profile: credentials, services, prices and reviews.
class CounselorDetailsScreen extends ConsumerWidget {
  const CounselorDetailsScreen({super.key, required this.counselorId});
  final String counselorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenCounselor)),
      body: AsyncView<Counselor>(
        value: ref.watch(counselorProvider(counselorId)),
        onRetry: () => ref.invalidate(counselorProvider(counselorId)),
        data: (c) => Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
              Center(child: Column(children: [
                const CounselorAvatar(size: 96),
                const SizedBox(height: 10),
                Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: Text(c.name, style: t.h2, textAlign: TextAlign.center)), const SizedBox(width: 8), VerifiedBadge(size: 20, semanticLabel: l.licenseVerified)]),
                Text(c.headline, style: t.caption),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [StarRow(value: c.ratingAvg, size: 16), const SizedBox(width: 6), Text('${c.ratingAvg.toStringAsFixed(1)} · ${l.reviewsCount(c.ratingCount)}', style: t.bodySmall)]),
              ])),
              const SizedBox(height: 16),
              TileGroup(children: [
                OlfaListTile(icon: Icons.badge_outlined, title: kindLabel(l, c.kind), subtitle: l.counselorType, showChevron: false),
                OlfaListTile(icon: Icons.verified_outlined, title: c.licenseAuthority, subtitle: '${l.licensedBy} · ${countryByIso(c.licenseCountry).label(langOf(context))}', showChevron: false),
                OlfaListTile(icon: Icons.work_history_outlined, title: l.yearsCount(c.yearsExperience), subtitle: l.experience, showChevron: false),
                OlfaListTile(icon: Icons.translate_rounded, title: c.languages.map((x) => languageName(context, x)).join('، '), subtitle: l.serviceLanguage, showChevron: false),
              ]),
              SectionLabel(l.about),
              Text(c.bio, style: t.bodyMedium),
              SectionLabel(l.pricing),
              TileGroup(children: [
                for (final o in c.offerings)
                  OlfaListTile(
                    icon: Icons.schedule_rounded,
                    title: '${serviceLabel(l, o.service)} · ${l.minutesShort(o.durationMinutes)}',
                    subtitle: languageName(context, o.language),
                    showChevron: false,
                    trailing: Text(money(context, o.priceMinor, o.currency), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                  ),
              ]),
              SectionLabel(l.reviews),
              if (c.reviews.isEmpty) Text(l.noReviewsYet, style: t.bodySmall.copyWith(color: OlfaColors.textMuted)),
              for (final r in c.reviews)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [StarRow(value: r.rating.toDouble(), size: 13), const SizedBox(width: 8), Text(r.by ?? '', style: t.caption.copyWith(fontWeight: FontWeight.w600)), const Spacer(), Text(shortTime(context, r.createdAt), style: t.caption)]),
                    if (r.comment != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.comment!, style: t.bodySmall)),
                  ]),
                ),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: PrimaryButton(label: l.bookConsultation, icon: Icons.event_available_rounded, onPressed: c.offerings.isEmpty ? null : () => context.push(Routes.bookCounselor(c.id))),
            ),
          ),
        ]),
      ),
    );
  }
}

/// C3 — Booking: service type, service language and duration (each a real
/// offering with its own price), preferred time and a note; then payment.
/// The request reaches the counselor only after the payment succeeds.
class BookConsultationScreen extends ConsumerStatefulWidget {
  const BookConsultationScreen({super.key, required this.counselorId});
  final String counselorId;
  @override
  ConsumerState<BookConsultationScreen> createState() => _BookConsultationScreenState();
}

class _BookConsultationScreenState extends ConsumerState<BookConsultationScreen> {
  ConsultationService? _svc;
  String? _lang;
  int? _dur;
  DateTime? _time;
  final _note = TextEditingController();
  bool _busy = false;
  BookingIntent? _intent;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  CounselorOffering? _match(Counselor c) =>
      c.offerings.where((o) => o.service == _svc && o.language == _lang && o.durationMinutes == _dur).firstOrNull;

  void _normalize(Counselor c) {
    final svcs = c.offerings.map((o) => o.service).toSet();
    _svc = svcs.contains(_svc) ? _svc : svcs.first;
    final langs = c.offerings.where((o) => o.service == _svc).map((o) => o.language).toSet();
    _lang = langs.contains(_lang) ? _lang : langs.first;
    final durs = c.offerings.where((o) => o.service == _svc && o.language == _lang).map((o) => o.durationMinutes).toSet();
    _dur = durs.contains(_dur) ? _dur : (durs.toList()..sort()).first;
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), initialDate: now.add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 0));
    if (tm == null) return;
    setState(() => _time = DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
  }

  Future<void> _payNow(CounselorOffering o) async {
    final l = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    final repo = ref.read(consultationsRepositoryProvider);
    try {
      _intent ??= await repo.book(offeringId: o.id, note: _note.text, preferredTime: _time);
      await repo.pay(_intent!);
      ref.invalidate(myConsultationsProvider);
      if (!mounted) return;
      showToast(context, l.paymentDone);
      router.pushReplacement(Routes.myConsultations);
    } on Failure catch (e) {
      if (mounted) {
        showToast(
          context,
          switch (e) {
            ServerFailure(code: 'payment_cancelled') => l.paymentCancelled,
            ServerFailure(code: 'conflict') => l.bookingOpenExists,
            ServerFailure(code: 'payments_not_configured' || 'payment_failed') => l.paymentFailed,
            _ => failureMessage(context, e),
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenBookConsultation)),
      body: AsyncView<Counselor>(
        value: ref.watch(counselorProvider(widget.counselorId)),
        onRetry: () => ref.invalidate(counselorProvider(widget.counselorId)),
        data: (c) {
          if (c.offerings.isEmpty) return EmptyState(icon: Icons.event_busy_outlined, title: l.noCounselors, body: '');
          _normalize(c);
          final o = _match(c)!;
          final svcs = c.offerings.map((x) => x.service).toSet().toList();
          final langs = c.offerings.where((x) => x.service == _svc).map((x) => x.language).toSet().toList();
          final durs = c.offerings.where((x) => x.service == _svc && x.language == _lang).toList()..sort((a, b) => a.durationMinutes.compareTo(b.durationMinutes));
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
                OlfaCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const CounselorAvatar(size: 44),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.name, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)), Text(kindLabel(l, c.kind), style: t.caption)])),
                  ]),
                ),
                const SizedBox(height: 18),
                Text(l.serviceType, style: t.inputLabel),
                const SizedBox(height: 8),
                ChoiceWrap<ConsultationService>(options: svcs, label: (s) => serviceLabel(l, s), isSelected: (s) => s == _svc, onTap: (s) => setState(() { _svc = s; _intent = null; })),
                const SizedBox(height: 16),
                Text(l.serviceLanguage, style: t.inputLabel),
                const SizedBox(height: 8),
                ChoiceWrap<String>(options: langs, label: (x) => languageName(context, x), isSelected: (x) => x == _lang, onTap: (x) => setState(() { _lang = x; _intent = null; })),
                const SizedBox(height: 16),
                Text(l.sessionDuration, style: t.inputLabel),
                const SizedBox(height: 8),
                ChoiceWrap<CounselorOffering>(
                  options: durs,
                  label: (x) => '${l.minutesShort(x.durationMinutes)} · ${money(context, x.priceMinor, x.currency)}',
                  isSelected: (x) => x.durationMinutes == _dur,
                  onTap: (x) => setState(() { _dur = x.durationMinutes; _intent = null; }),
                ),
                const SizedBox(height: 16),
                Text(l.preferredTime, style: t.inputLabel),
                const SizedBox(height: 8),
                OlfaChoice(
                  label: _time == null ? l.choosePreferredTime : DateFormat.yMMMEd(langOf(context)).add_Hm().format(_time!),
                  selected: _time != null,
                  onTap: _pickTime,
                ),
                const SizedBox(height: 6),
                Text(l.preferredTimeNote, style: t.caption),
                const SizedBox(height: 16),
                OlfaTextField(label: l.noteForCounselor, hint: l.noteForCounselorHint, controller: _note, maxLines: 3, maxLength: 1000),
                OlfaCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.summary, style: t.caption),
                    const SizedBox(height: 4),
                    Text('${serviceLabel(l, o.service)} · ${languageName(context, o.language)} · ${l.minutesShort(o.durationMinutes)}', style: t.bodyMedium),
                    const Divider(height: 20),
                    Row(children: [Text(l.total, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)), const Spacer(), Text(money(context, o.priceMinor, o.currency), style: t.h3)]),
                  ]),
                ),
                const SizedBox(height: 14),
                InfoBanner(icon: Icons.shield_outlined, accent: true, text: l.payBeforeConfirmNote),
              ]),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: PrimaryButton(label: l.payAndRequest(money(context, o.priceMinor, o.currency)), icon: Icons.lock_outline_rounded, loading: _busy, onPressed: _busy ? null : () => _payNow(o)),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// C4 — My consultations: status, chat, cancel (refund before confirmation), rate.
class MyConsultationsScreen extends ConsumerWidget {
  const MyConsultationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenMyConsultations)),
      body: AsyncView<List<Consultation>>(
        value: ref.watch(myConsultationsProvider),
        onRetry: () => ref.invalidate(myConsultationsProvider),
        data: (list) => RefreshIndicator(
          color: OlfaColors.primary,
          onRefresh: () => ref.refresh(myConsultationsProvider.future),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), children: [
            if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(l.noConsultations, textAlign: TextAlign.center, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted))),
            for (final k in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OlfaCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const CounselorAvatar(size: 42),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(k.counselorName, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                          Text('${serviceLabel(l, k.service)} · ${l.minutesShort(k.durationMinutes)} · ${languageName(context, k.language)}', style: t.caption),
                        ]),
                      ),
                      StatusPill(k.status),
                    ]),
                    if (k.scheduledAt != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [const Icon(Icons.event_rounded, size: 16, color: OlfaColors.primary), const SizedBox(width: 6), Text(DateFormat.yMMMEd(langOf(context)).add_Hm().format(k.scheduledAt!), style: t.bodySmall)]),
                    ],
                    if (k.status == ConsultationStatus.paid) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.waitingCounselorConfirm, style: t.caption)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text(money(context, k.priceMinor, k.currency), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (k.canCancel)
                        TextButton(
                          onPressed: () async {
                            final ok = await showConfirmation(context, title: l.cancelBookingTitle, body: k.status == ConsultationStatus.paid ? l.cancelBookingRefund : l.cancelBookingBody, confirmLabel: l.cancelBooking, destructive: true);
                            if (!ok) return;
                            try {
                              await ref.read(consultationsRepositoryProvider).cancel(k.id);
                              ref.invalidate(myConsultationsProvider);
                            } on Failure catch (e) {
                              if (context.mounted) showToast(context, failureMessage(context, e));
                            }
                          },
                          child: Text(l.cancelBooking),
                        ),
                      if (k.conversationId != null && (k.status == ConsultationStatus.confirmed || k.status == ConsultationStatus.completed))
                        PrimaryButton(label: l.openChat, icon: Icons.chat_bubble_outline_rounded, expand: false, onPressed: () => context.push(Routes.chatWith(k.conversationId!))),
                      if (k.canRate) ...[
                        const SizedBox(width: 8),
                        PrimaryButton(label: l.rateCounselor, icon: Icons.star_outline_rounded, expand: false, onPressed: () => showRateSheet(context, ref, k)),
                      ],
                      if (k.myRating != null) ...[const SizedBox(width: 8), StarRow(value: k.myRating!.toDouble(), size: 14)],
                    ]),
                  ]),
                ),
              ),
            SecondaryButton(label: l.bookConsultation, icon: Icons.add_rounded, onPressed: () => context.push(Routes.consultations)),
          ]),
        ),
      ),
    );
  }
}

Future<void> showRateSheet(BuildContext context, WidgetRef ref, Consultation k) async {
  final l = AppLocalizations.of(context);
  var stars = 0;
  final comment = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.rateCounselorTitle(k.counselorName), style: sheet.type.h2),
          const SizedBox(height: 6),
          Text(l.rateCounselorBody, style: sheet.type.bodySmall.copyWith(color: OlfaColors.textMuted)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: l.ratingOutOf5('$i'),
                iconSize: 38,
                onPressed: () => setSheet(() => stars = i),
                icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: OlfaColors.primary),
              ),
          ]),
          const SizedBox(height: 8),
          OlfaTextField(label: l.reviewComment, controller: comment, maxLines: 3, maxLength: 1000),
          PrimaryButton(
            label: l.submitRating,
            onPressed: stars == 0
                ? null
                : () async {
                    try {
                      await ref.read(consultationsRepositoryProvider).review(k.id, rating: stars, comment: comment.text);
                      ref.invalidate(myConsultationsProvider);
                      if (sheet.mounted) Navigator.of(sheet).pop();
                      if (context.mounted) showToast(context, l.ratingThanks);
                    } on Failure catch (e) {
                      if (sheet.mounted) showToast(sheet, failureMessage(sheet, e));
                    }
                  },
          ),
        ]),
      ),
    ),
  );
  comment.dispose();
}

/// C5 — Become a counselor: psychologist or family counselor, licence,
/// languages and services. Reviewed by moderators before it is listed.
class CounselorApplyScreen extends ConsumerStatefulWidget {
  const CounselorApplyScreen({super.key});
  @override
  ConsumerState<CounselorApplyScreen> createState() => _CounselorApplyScreenState();
}

class _CounselorApplyScreenState extends ConsumerState<CounselorApplyScreen> {
  CounselorKind _kind = CounselorKind.familyCounselor;
  final _name = TextEditingController(), _headline = TextEditingController(), _bio = TextEditingController();
  final _years = TextEditingController(), _licNo = TextEditingController(), _licAuth = TextEditingController();
  String _licCountry = 'AE';
  final _langs = <String>{'ar'};
  final _svcs = <ConsultationService>{};
  final _credentials = <String>[];
  bool _submitted = false, _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _headline, _bio, _years, _licNo, _licAuth]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addCredential() async {
    final l = AppLocalizations.of(context);
    try {
      final picked = await pickCredentialFile(context);
      if (picked == null) return;
      final key = await ref.read(consultationsRepositoryProvider).uploadCredential(picked.$1, picked.$2);
      setState(() => _credentials.add(key));
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } catch (_) {
      if (mounted) showToast(context, l.errorGeneric);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    final years = int.tryParse(_years.text.trim());
    final ok = _name.text.trim().length >= 2 && _headline.text.trim().length >= 5 && _bio.text.trim().length >= 80 && years != null && _licNo.text.trim().length >= 3 && _licAuth.text.trim().length >= 3 && _langs.isNotEmpty && _svcs.isNotEmpty && _credentials.isNotEmpty;
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(consultationsRepositoryProvider).apply(CounselorApplication(
            kind: _kind,
            displayName: _name.text,
            headline: _headline.text,
            bio: _bio.text,
            yearsExperience: years,
            licenseNumber: _licNo.text,
            licenseAuthority: _licAuth.text,
            licenseCountry: _licCountry,
            languages: _langs.toList(),
            services: _svcs.toList(),
            credentialKeys: _credentials,
          ));
      ref.invalidate(myCounselorProvider);
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final mine = ref.watch(myCounselorProvider);
    final status = mine.valueOrNull?.status;
    if (status == CounselorStatus.pending || status == CounselorStatus.approved || status == CounselorStatus.suspended) {
      return Scaffold(
        appBar: AppBar(title: Text(l.screenCounselorApply)),
        body: EmptyState(
          icon: status == CounselorStatus.approved ? Icons.verified_outlined : Icons.hourglass_top_rounded,
          title: switch (status!) { CounselorStatus.approved => l.counselorApproved, CounselorStatus.suspended => l.counselorSuspended, _ => l.counselorPending },
          body: status == CounselorStatus.approved ? l.counselorApprovedBody : l.counselorPendingBody,
          action: status == CounselorStatus.approved
              ? PrimaryButton(label: l.screenCounselorDesk, expand: false, onPressed: () => context.pushReplacement(Routes.counselorDesk))
              : SecondaryButton(label: l.refresh, onPressed: () => ref.invalidate(myCounselorProvider)),
        ),
      );
    }
    String? req(TextEditingController c, int min) => _submitted && c.text.trim().length < min ? l.errorValidation : null;
    return FormPage(
      title: l.screenCounselorApply,
      action: PrimaryButton(label: l.submitForReview, loading: _busy, onPressed: _busy ? null : _submit),
      children: [
        if (status == CounselorStatus.rejected && mine.valueOrNull?.rejectReason != null) ...[
          InfoBanner(text: '${l.counselorRejected}: ${mine.valueOrNull!.rejectReason}', accent: true),
          const SizedBox(height: 14),
        ],
        Text(l.counselorApplyBody, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
        const SizedBox(height: 18),
        Text(l.counselorType, style: t.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<CounselorKind>(options: CounselorKind.values, label: (k) => kindLabel(l, k), isSelected: (k) => k == _kind, onTap: (k) => setState(() => _kind = k)),
        const SizedBox(height: 18),
        OlfaTextField(label: l.professionalName, controller: _name, error: req(_name, 2)),
        OlfaTextField(label: l.headline, hint: l.headlineHint, controller: _headline, error: req(_headline, 5)),
        OlfaTextField(label: l.bio, hint: l.counselorBioHint, controller: _bio, maxLines: 5, maxLength: 1500, counter: true, error: req(_bio, 80)),
        OlfaTextField(label: l.experience, controller: _years, keyboardType: TextInputType.number, error: _submitted && int.tryParse(_years.text.trim()) == null ? l.errorValidation : null),
        OlfaTextField(label: l.licenseNumber, controller: _licNo, error: req(_licNo, 3)),
        OlfaTextField(label: l.licenseAuthority, controller: _licAuth, error: req(_licAuth, 3)),
        Text(l.licenseCountry, style: t.inputLabel),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _licCountry,
          isExpanded: true,
          items: [for (final c in kCountries) DropdownMenuItem(value: c.iso, child: Text('${c.flag}  ${c.label(langOf(context))}'))],
          onChanged: (v) => setState(() => _licCountry = v ?? _licCountry),
        ),
        const SizedBox(height: 18),
        Text(l.serviceLanguage, style: t.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<String>(options: kServiceLanguages, label: (x) => languageName(context, x), isSelected: _langs.contains, onTap: (x) => setState(() => _langs.contains(x) ? _langs.remove(x) : _langs.add(x))),
        if (_submitted && _langs.isEmpty) Text(l.errorValidation, style: t.bodySmall.copyWith(color: OlfaColors.primary)),
        const SizedBox(height: 18),
        Text(l.servicesOffered, style: t.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<ConsultationService>(options: ConsultationService.values, label: (s) => serviceLabel(l, s), isSelected: _svcs.contains, onTap: (s) => setState(() => _svcs.contains(s) ? _svcs.remove(s) : _svcs.add(s))),
        if (_submitted && _svcs.isEmpty) Text(l.errorValidation, style: t.bodySmall.copyWith(color: OlfaColors.primary)),
        const SizedBox(height: 18),
        Text(l.credentials, style: t.inputLabel),
        const SizedBox(height: 6),
        Text(l.credentialsNote, style: t.caption),
        const SizedBox(height: 8),
        for (var i = 0; i < _credentials.length; i++)
          OlfaListTile(icon: Icons.description_outlined, title: l.credentialN(i + 1), showChevron: false, trailing: const Icon(Icons.check_rounded, color: OlfaColors.primary)),
        if (_credentials.length < 5) SecondaryButton(label: l.uploadCredential, icon: Icons.upload_file_rounded, onPressed: _addCredential),
        if (_submitted && _credentials.isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.credentialRequired, style: t.bodySmall.copyWith(color: OlfaColors.primary))),
      ],
    );
  }
}

/// C6 — Counselor desk: paid requests to confirm (opens the chat — the
/// counselor may write first), decline (full refund) or complete; prices.
class CounselorDeskScreen extends ConsumerWidget {
  const CounselorDeskScreen({super.key});

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() op) async {
    try {
      await op();
      ref.invalidate(counselorDeskProvider);
      ref.invalidate(conversationIndexProvider);
    } on Failure catch (e) {
      if (context.mounted) showToast(context, failureMessage(context, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final repo = ref.read(consultationsRepositoryProvider);
    final me = ref.watch(myCounselorProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.screenCounselorDesk),
        actions: [OlfaIconButton(icon: Icons.sell_outlined, tooltip: l.myPrices, onPressed: () => showOfferingSheet(context, ref, me)), const SizedBox(width: 6)],
      ),
      body: AsyncView<List<Consultation>>(
        value: ref.watch(counselorDeskProvider),
        onRetry: () => ref.invalidate(counselorDeskProvider),
        data: (list) {
          final incoming = list.where((k) => k.status == ConsultationStatus.paid).toList();
          final confirmed = list.where((k) => k.status == ConsultationStatus.confirmed).toList();
          Widget card(Consultation k) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OlfaCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(k.clientName ?? '', style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                          Text('${serviceLabel(l, k.service)} · ${l.minutesShort(k.durationMinutes)} · ${languageName(context, k.language)}', style: t.caption),
                        ]),
                      ),
                      Text(money(context, k.priceMinor, k.currency), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                    if (k.note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('“${k.note}”', style: t.bodySmall)),
                    if (k.scheduledAt != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(DateFormat.yMMMEd(langOf(context)).add_Hm().format(k.scheduledAt!), style: t.caption)),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (k.status == ConsultationStatus.paid) ...[
                        TextButton(
                          onPressed: () async {
                            final ok = await showConfirmation(context, title: l.declineBooking, body: l.declineBookingBody, confirmLabel: l.declineBooking, destructive: true);
                            if (ok && context.mounted) await _act(context, ref, () => repo.decline(k.id));
                          },
                          child: Text(l.declineBooking),
                        ),
                        const SizedBox(width: 8),
                        PrimaryButton(
                          label: l.confirmBooking,
                          expand: false,
                          onPressed: () async {
                            final now = DateTime.now();
                            final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), initialDate: now.add(const Duration(days: 1)));
                            if (d == null || !context.mounted) return;
                            final tm = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 0));
                            if (tm == null || !context.mounted) return;
                            final at = DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
                            String? conv;
                            await _act(context, ref, () async => conv = await repo.confirm(k.id, at));
                            if (conv != null && context.mounted) context.push(Routes.chatWith(conv!));
                          },
                        ),
                      ] else ...[
                        TextButton(onPressed: () => _act(context, ref, () => repo.complete(k.id)), child: Text(l.markCompleted)),
                        const SizedBox(width: 8),
                        if (k.conversationId != null) PrimaryButton(label: l.openChat, icon: Icons.chat_bubble_outline_rounded, expand: false, onPressed: () => context.push(Routes.chatWith(k.conversationId!))),
                      ],
                    ]),
                  ]),
                ),
              );
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
            if ((me?.offerings ?? const []).isEmpty) ...[
              InfoBanner(text: l.addPricesFirst, accent: true, trailing: TextButton(onPressed: () => showOfferingSheet(context, ref, me), child: Text(l.add))),
              const SizedBox(height: 8),
            ],
            SectionLabel('${l.incomingRequests} · ${incoming.length}', top: 8),
            if (incoming.isEmpty) Text(l.noIncoming, style: t.bodySmall.copyWith(color: OlfaColors.textMuted)),
            for (final k in incoming) card(k),
            SectionLabel('${l.confirmedSessions} · ${confirmed.length}'),
            for (final k in confirmed) card(k),
          ]);
        },
      ),
    );
  }
}

/// Add or update one offering (service × language × duration → price).
Future<void> showOfferingSheet(BuildContext context, WidgetRef ref, Counselor? me) async {
  final l = AppLocalizations.of(context);
  if (me == null) return;
  var svc = me.services.isEmpty ? ConsultationService.marital : me.services.first;
  var lang = me.languages.isEmpty ? 'ar' : me.languages.first;
  var dur = 60;
  var cur = 'AED';
  final price = TextEditingController();
  String? err;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.myPrices, style: sheet.type.h2),
            const SizedBox(height: 12),
            ChoiceWrap<ConsultationService>(options: me.services, label: (s) => serviceLabel(l, s), isSelected: (s) => s == svc, onTap: (s) => set(() => svc = s)),
            const SizedBox(height: 12),
            ChoiceWrap<String>(options: me.languages, label: (x) => languageName(sheet, x), isSelected: (x) => x == lang, onTap: (x) => set(() => lang = x)),
            const SizedBox(height: 12),
            ChoiceWrap<int>(options: kDurations, label: l.minutesShort, isSelected: (d) => d == dur, onTap: (d) => set(() => dur = d)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: OlfaTextField(label: l.price, controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), error: err)),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: Padding(
                  padding: const EdgeInsets.only(top: 26),
                  child: DropdownButtonFormField<String>(value: cur, items: [for (final c in kPriceCurrencies) DropdownMenuItem(value: c, child: Text(c))], onChanged: (v) => set(() => cur = v ?? cur)),
                ),
              ),
            ]),
            PrimaryButton(
              label: l.save,
              onPressed: () async {
                final minor = parseMinor(price.text, cur);
                if (minor == null) return set(() => err = l.errorValidation);
                try {
                  await ref.read(consultationsRepositoryProvider).saveOffering(service: svc, language: lang, durationMinutes: dur, priceMinor: minor, currency: cur);
                  ref.invalidate(myCounselorProvider);
                  if (sheet.mounted) Navigator.of(sheet).pop();
                  if (context.mounted) showToast(context, l.saved);
                } on Failure catch (e) {
                  if (sheet.mounted) showToast(sheet, failureMessage(sheet, e));
                }
              },
            ),
          ]),
        ),
      ),
    ),
  );
  price.dispose();
}

/// Picks a photo/scan of a licence or certificate. Stored privately; only
/// moderators can open it through a short-lived link.
Future<(List<int>, String)?> pickCredentialFile(BuildContext context) async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  final mime = x.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
  return (bytes.toList(), mime);
}

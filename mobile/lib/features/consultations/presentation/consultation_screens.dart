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
import '../../profile/application/profile_controllers.dart';
import '../../../shared/utils/text_fold.dart';
import '../../../core/routing/navigation.dart';

/// C1 — Family & marital consultations: a directory with the counselor type
/// as quick tabs and the other filters (service, language, duration) in one
/// sheet. Results are cached per filter combination, so going back is instant.
class ConsultationsScreen extends ConsumerWidget {
  const ConsultationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final q = ref.watch(counselorQueryProvider);
    final ctrl = ref.read(counselorQueryProvider.notifier);
    final extra = [q.service != null, q.language != null, q.durationMinutes != null].where((x) => x).length;
    final list = ref.watch(counselorsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.screenConsultations),
        actions: [OlfaIconButton(icon: Icons.event_note_outlined, tooltip: l.screenMyConsultations, onPressed: () => context.push(Routes.myConsultations)), const SizedBox(width: 6)],
      ),
      body: RefreshIndicator(
        color: OlfaColors.primary,
        onRefresh: () => ref.refresh(counselorsByQueryProvider(q).future),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverToBoxAdapter(child: InfoBanner(text: l.consultIntro, icon: Icons.support_agent_rounded, accent: true)),
            ),
            // Counselor type: quick tabs, always visible while scrolling.
            SliverPersistentHeader(
              pinned: true,
              delegate: _FixedHeader(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ChoiceWrap<CounselorKind?>(
                          options: const [null, CounselorKind.familyCounselor, CounselorKind.psychologist],
                          label: (k) => k == null ? l.all : kindLabel(l, k),
                          isSelected: (k) => q.kind == k,
                          onTap: (k) => ctrl.set(q.copyWith(kind: () => k)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Stack(clipBehavior: Clip.none, children: [
                      OlfaIconButton(icon: Icons.tune_rounded, tooltip: l.filters, style: OlfaIconStyle.soft, onPressed: () => _showFilters(context, ref)),
                      if (extra > 0) PositionedDirectional(top: -4, end: -4, child: CountBadge(count: extra)),
                    ]),
                  ]),
                ),
              ),
            ),
            if (extra > 0)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    if (q.service != null) _ActiveFilter(serviceLabel(l, q.service!), () => ctrl.set(q.copyWith(service: () => null))),
                    if (q.language != null) _ActiveFilter(languageName(context, q.language!), () => ctrl.set(q.copyWith(language: () => null))),
                    if (q.durationMinutes != null) _ActiveFilter(l.minutesShort(q.durationMinutes!), () => ctrl.set(q.copyWith(durationMinutes: () => null))),
                  ]),
                ),
              ),
            ...switch (list) {
              AsyncValue(:final valueOrNull?) when valueOrNull.isEmpty => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: l.noCounselors,
                      body: l.professionalsRegisterNote,
                      action: (extra > 0 || q.kind != null) ? SecondaryButton(label: l.clearFilters, expand: false, onPressed: () => ctrl.set(const CounselorQuery())) : null,
                    ),
                  ),
                ],
              AsyncValue(valueOrNull: final value?) => [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Row(children: [
                        Expanded(child: Text(l.counselorsFound(value.length), style: t.caption)),
                        if (list.isLoading) const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: OlfaColors.primary)),
                      ]),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    sliver: SliverList.separated(
                      itemCount: value.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => CounselorCard(c: value[i]),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                    sliver: SliverToBoxAdapter(child: Text(l.professionalsRegisterNote, style: t.caption, textAlign: TextAlign.center)),
                  ),
                ],
              AsyncValue(:final error?) => [
                  SliverFillRemaining(hasScrollBody: false, child: ErrorState(error: error, onRetry: () => ref.invalidate(counselorsByQueryProvider(q)))),
                ],
              _ => [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverList.separated(itemCount: 3, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (_, __) => const _CounselorCardSkeleton()),
                  ),
                ],
            },
          ],
        ),
      ),
    );
  }

  Future<void> _showFilters(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    var draft = ref.read(counselorQueryProvider);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(l.filters, style: sheet.type.h3),
                const SizedBox(height: 16),
                Text(l.serviceType, style: sheet.type.inputLabel),
                const SizedBox(height: 8),
                ChoiceWrap<ConsultationService?>(
                  options: [null, ...ConsultationService.values],
                  label: (s) => s == null ? l.all : serviceLabel(l, s),
                  isSelected: (s) => draft.service == s,
                  onTap: (s) => set(() => draft = draft.copyWith(service: () => s)),
                ),
                const SizedBox(height: 16),
                Text(l.serviceLanguage, style: sheet.type.inputLabel),
                const SizedBox(height: 8),
                ChoiceWrap<String?>(
                  options: const [null, 'ar', 'en', 'fr', 'tr', 'ur'],
                  label: (c) => c == null ? l.all : languageName(sheet, c),
                  isSelected: (c) => draft.language == c,
                  onTap: (c) => set(() => draft = draft.copyWith(language: () => c)),
                ),
                const SizedBox(height: 16),
                Text(l.sessionDuration, style: sheet.type.inputLabel),
                const SizedBox(height: 8),
                ChoiceWrap<int?>(
                  options: const [null, ...kDurations],
                  label: (d) => d == null ? l.all : l.minutesShort(d),
                  isSelected: (d) => draft.durationMinutes == d,
                  onTap: (d) => set(() => draft = draft.copyWith(durationMinutes: () => d)),
                ),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                    child: SecondaryButton(
                      label: l.reset,
                      onPressed: () => set(() => draft = CounselorQuery(kind: draft.kind)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: l.showResults,
                      onPressed: () {
                        ref.read(counselorQueryProvider.notifier).set(draft);
                        Navigator.of(sheet).pop();
                      },
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _FixedHeader extends SliverPersistentHeaderDelegate {
  _FixedHeader({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: OlfaColors.white, child: Align(alignment: AlignmentDirectional.centerStart, child: child));
  @override
  bool shouldRebuild(_FixedHeader old) => old.child != child || old.height != height;
}

class _ActiveFilter extends StatelessWidget {
  const _ActiveFilter(this.label, this.onRemove);
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return InputChip(
      label: Text(label),
      onDeleted: onRemove,
      deleteButtonTooltipMessage: l.clear,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      backgroundColor: OlfaColors.primaryTint(),
      side: BorderSide.none,
      labelStyle: context.type.bodySmall.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(OlfaRadius.chip)),
    );
  }
}

class _CounselorCardSkeleton extends StatelessWidget {
  const _CounselorCardSkeleton();
  @override
  Widget build(BuildContext context) => OlfaCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const OlfaSkeleton(width: 56, height: 56, circle: true),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [OlfaSkeleton(width: 140, height: 14), SizedBox(height: 8), OlfaSkeleton(width: 200), SizedBox(height: 8), OlfaSkeleton(width: 90)])),
          ]),
          const SizedBox(height: 14),
          const OlfaSkeleton(width: 220),
        ]),
      );
}

/// Counselor in the directory — the same facts, order and labels as the
/// admin dashboard's counselor card (type, rating, languages, services, price).
class CounselorCard extends StatelessWidget {
  const CounselorCard({super.key, required this.c});
  final Counselor c;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final from = cheapestOffering(c);
    return Semantics(
      button: true,
      label: '${c.name}, ${kindLabel(l, c.kind)}',
      child: Material(
        color: OlfaColors.white,
        shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(OlfaRadius.card), side: const BorderSide(color: OlfaColors.gray)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushOnce(Routes.counselorDetails(c.id)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CounselorAvatar(name: c.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Flexible(child: Text(c.name, style: t.h3, overflow: TextOverflow.ellipsis)), const SizedBox(width: 6), VerifiedBadge(size: 16, semanticLabel: l.licenseVerified)]),
                    Text('${kindLabel(l, c.kind)} · ${l.yearsCount(c.yearsExperience)}', style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    RatingLine(avg: c.ratingAvg, count: c.ratingCount),
                  ]),
                ),
                Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: OlfaColors.textMuted),
              ]),
              if (c.headline.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(c.headline, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in c.services.take(3)) OlfaTag(serviceLabel(l, s)),
                if (c.services.length > 3) OlfaTag('+${c.services.length - 3}'),
                for (final lg in c.languages) OlfaTag(languageName(context, lg), style: OlfaTagStyle.accent),
              ]),
              if (from != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: OlfaColors.gray),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text(l.priceFrom(money(context, from.priceMinor, from.currency), from.durationMinutes), style: t.bodySmall.copyWith(fontWeight: FontWeight.w700))),
                  Text(l.bookConsultation, style: t.bodySmall.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w700)),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// C2 — Counselor profile: a summary strip (rating, reviews, years, type),
/// then about, prices and reviews, with "Book" always reachable at the bottom.
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
        loading: const _CounselorDetailsSkeleton(),
        data: (c) {
          final from = cheapestOffering(c);
          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                color: OlfaColors.primary,
                onRefresh: () => ref.refresh(counselorProvider(counselorId).future),
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
                  Center(
                    child: Column(children: [
                      CounselorAvatar(size: 88, name: c.name),
                      const SizedBox(height: 10),
                      Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: Text(c.name, style: t.h2, textAlign: TextAlign.center)), const SizedBox(width: 8), VerifiedBadge(size: 20, semanticLabel: l.licenseVerified)]),
                      const SizedBox(height: 2),
                      Text(kindLabel(l, c.kind), style: t.bodySmall.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w700)),
                      if (c.headline.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.headline, style: t.caption, textAlign: TextAlign.center)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  // Same three numbers as the admin dashboard's counselor card.
                  Row(children: [
                    Expanded(child: _Fact(value: c.ratingCount == 0 ? '—' : c.ratingAvg.toStringAsFixed(1), label: l.rating, icon: Icons.star_rounded)),
                    const SizedBox(width: 10),
                    Expanded(child: _Fact(value: '${c.ratingCount}', label: l.reviews, icon: Icons.reviews_outlined)),
                    const SizedBox(width: 10),
                    Expanded(child: _Fact(value: '${c.yearsExperience}', label: l.experience, icon: Icons.work_history_outlined)),
                  ]),
                  const SizedBox(height: 16),
                  TileGroup(children: [
                    OlfaListTile(icon: Icons.verified_outlined, title: c.licenseAuthority, subtitle: '${l.licensedBy} · ${countryByIso(c.licenseCountry).label(langOf(context))}', showChevron: false),
                    OlfaListTile(icon: Icons.translate_rounded, title: c.languages.map((x) => languageName(context, x)).join(listSeparator(langOf(context))), subtitle: l.serviceLanguage, showChevron: false),
                  ]),
                  SectionLabel(l.about),
                  Text(c.bio, style: t.bodyMedium),
                  SectionLabel(l.services),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final s in c.services) OlfaTag(serviceLabel(l, s))]),
                  SectionLabel(l.pricing),
                  if (c.offerings.isEmpty) Text(l.noOfferingsYet, style: t.bodySmall.copyWith(color: OlfaColors.textMuted)),
                  if (c.offerings.isNotEmpty)
                    TileGroup(children: [
                      for (final o in c.offerings)
                        OlfaListTile(
                          icon: Icons.schedule_rounded,
                          title: '${serviceLabel(l, o.service)} · ${l.minutesShort(o.durationMinutes)}',
                          subtitle: languageName(context, o.language),
                          showChevron: false,
                          trailing: Text(money(context, o.priceMinor, o.currency), textDirection: TextDirection.ltr, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  SectionLabel(l.reviews),
                  if (c.reviews.isEmpty) Text(l.noReviewsYet, style: t.bodySmall.copyWith(color: OlfaColors.textMuted)),
                  for (final r in c.reviews)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OlfaCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [StarRow(value: r.rating.toDouble(), size: 13), const SizedBox(width: 8), Expanded(child: Text(r.by ?? '', style: t.caption.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)), Text(shortTime(context, r.createdAt), style: t.caption)]),
                          if (r.comment != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.comment!, style: t.bodySmall)),
                          if (r.reply != null)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(12)),
                              child: Text(r.reply!, style: t.bodySmall),
                            ),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
            // Book bar: price on one side, the action on the other — always visible.
            Container(
              decoration: const BoxDecoration(color: OlfaColors.white, border: Border(top: BorderSide(color: OlfaColors.gray))),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Row(children: [
                    if (from != null) ...[
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(l.startingFrom, style: t.caption),
                          Text(money(context, from.priceMinor, from.currency), textDirection: TextDirection.ltr, style: t.h3),
                        ]),
                      ),
                      PrimaryButton(
                        label: l.bookConsultation,
                        icon: Icons.event_available_rounded,
                        expand: false,
                        onPressed: () => context.pushOnce(Routes.bookCounselor(c.id)),
                      ),
                    ] else
                      Expanded(child: PrimaryButton(label: l.bookConsultation, icon: Icons.event_available_rounded, onPressed: null)),
                  ]),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(OlfaRadius.card)),
          child: Column(children: [
            Icon(icon, size: 18, color: OlfaColors.primary),
            const SizedBox(height: 4),
            Text(value, textDirection: TextDirection.ltr, style: context.type.number(18)),
            Text(label, style: context.type.caption, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _CounselorDetailsSkeleton extends StatelessWidget {
  const _CounselorDetailsSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: const [
          Center(child: OlfaSkeleton(width: 88, height: 88, circle: true)),
          SizedBox(height: 12),
          Center(child: OlfaSkeleton(width: 160, height: 18)),
          SizedBox(height: 8),
          Center(child: OlfaSkeleton(width: 110)),
          SizedBox(height: 18),
          OlfaSkeleton(height: 84, radius: 18),
          SizedBox(height: 16),
          OlfaSkeleton(height: 120, radius: 18),
          SizedBox(height: 16),
          OlfaSkeleton(height: 60),
        ],
      );
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
  DateTime? _time; // free-text wish (counselor without published hours)
  DateTime? _slot; // one of the counselor's offered times
  DateTime? _day;
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
      _intent ??= await repo.book(offeringId: o.id, note: _note.text, preferredTime: _slot == null ? _time : null, slot: _slot);
      await repo.pay(_intent!);
      ref.invalidate(myConsultationsProvider);
      if (!mounted) return;
      showToast(context, l.paymentDone);
      router.pushReplacement(Routes.myConsultations);
    } on ServerFailure catch (e) when (e.code == 'review_required') {
      // Mandatory questionnaire first: open the pending review.
      final pending = await repo.pendingReviews().catchError((Object _) => const <PendingReview>[]);
      if (mounted) showToast(context, l.errReviewRequired);
      if (pending.isNotEmpty) router.push(Routes.reviewConsultation(pending.first.consultationId), extra: pending.first.counselorName);
    } on Failure catch (e) {
      if (e is SlotUnavailableFailure) {
        // someone booked it a moment ago: refresh the times
        _intent = null;
        setState(() => _slot = null);
        ref.invalidate(slotsProvider((widget.counselorId, o.id)));
      }
      if (mounted) {
        showToast(
          context,
          switch (e) {
            ServerFailure(code: 'payment_cancelled') => l.paymentCancelled,
            ServerFailure(code: 'conflict') => l.bookingOpenExists,
            SlotUnavailableFailure() => l.slotTaken,
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
                    CounselorAvatar(size: 44, name: c.name),
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
                _SlotPicker(
                  slots: ref.watch(slotsProvider((widget.counselorId, o.id))),
                  day: _day,
                  slot: _slot,
                  onDay: (d) => setState(() {
                    _day = d;
                    _slot = null;
                    _intent = null;
                  }),
                  onSlot: (s) => setState(() {
                    _slot = s;
                    _intent = null;
                  }),
                  onRetry: () => ref.invalidate(slotsProvider((widget.counselorId, o.id))),
                  fallback: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.preferredTime, style: t.inputLabel),
                    const SizedBox(height: 8),
                    OlfaChoice(
                      label: _time == null ? l.choosePreferredTime : DateFormat.yMMMEd(langOf(context)).add_Hm().format(_time!),
                      selected: _time != null,
                      onTap: _pickTime,
                    ),
                    const SizedBox(height: 6),
                    Text(l.preferredTimeNote, style: t.caption),
                  ]),
                ),
                const SizedBox(height: 16),
                OlfaTextField(label: l.noteForCounselor, hint: l.noteForCounselorHint, controller: _note, maxLines: 3, maxLength: 1000),
                OlfaCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.summary, style: t.caption),
                    const SizedBox(height: 4),
                    Text('${serviceLabel(l, o.service)} · ${languageName(context, o.language)} · ${l.minutesShort(o.durationMinutes)}', style: t.bodyMedium),
                    if (_slot != null) Text(DateFormat.yMMMMEEEEd(langOf(context)).add_Hm().format(_slot!), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
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
                child: PrimaryButton(
                  label: l.payAndRequest(money(context, o.priceMinor, o.currency)),
                  icon: Icons.lock_outline_rounded,
                  loading: _busy,
                  // a counselor with published hours is booked on one of them
                  onPressed: _busy || (ref.watch(slotsProvider((widget.counselorId, o.id))).valueOrNull?.scheduled == true && _slot == null) ? null : () => _payNow(o),
                ),
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
            if (list.any((k) => k.canRate)) ...[
              InfoBanner(text: l.reviewRequiredBanner, icon: Icons.rate_review_outlined, accent: true),
              const SizedBox(height: 12),
            ],
            if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(l.noConsultations, textAlign: TextAlign.center, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted))),
            for (final k in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OlfaCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CounselorAvatar(size: 42, name: k.counselorName),
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
                        PrimaryButton(label: l.openChat, icon: Icons.chat_bubble_outline_rounded, expand: false, onPressed: () => context.pushOnce(Routes.chatWith(k.conversationId!))),
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

/// The questionnaire is a full screen (mandatory before booking again).
void showRateSheet(BuildContext context, WidgetRef ref, Consultation k) => context.pushOnce(Routes.reviewConsultation(k.id), extra: k.counselorName);

/// C5 — Become a counselor: psychologist or family counselor, licence,
/// languages and services. Reviewed by moderators before it is listed.
class CounselorApplyScreen extends ConsumerStatefulWidget {
  const CounselorApplyScreen({super.key, this.setupMode = false});

  /// Sign-up "about you" step of a professional account (kind comes from the
  /// account type; continues to location). Otherwise: edit and resubmit.
  final bool setupMode;
  @override
  ConsumerState<CounselorApplyScreen> createState() => _CounselorApplyScreenState();
}

class _CounselorApplyScreenState extends ConsumerState<CounselorApplyScreen> {
  CounselorKind _kind = CounselorKind.familyCounselor;
  final _name = TextEditingController(), _headline = TextEditingController(), _bio = TextEditingController();
  final _years = TextEditingController(), _licNo = TextEditingController(), _licAuth = TextEditingController(), _city = TextEditingController();
  String _licCountry = 'AE';
  bool _policy = false;

  @override
  void initState() {
    super.initState();
    final type = ref.read(profileDraftProvider).accountType;
    if (type == AccountType.psychologist) _kind = CounselorKind.psychologist;
    if (type == AccountType.familyCounselor) _kind = CounselorKind.familyCounselor;
  }
  final _langs = <String>{'ar'};
  final _svcs = <ConsultationService>{};
  final _credentials = <String>[];
  bool _submitted = false, _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _headline, _bio, _years, _licNo, _licAuth, _city]) {
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
    final ok = _name.text.trim().length >= 2 && _headline.text.trim().length >= 5 && _bio.text.trim().length >= 80 && years != null && _licNo.text.trim().length >= 3 && _licAuth.text.trim().length >= 3 && _langs.isNotEmpty && _svcs.isNotEmpty && _credentials.isNotEmpty && _policy;
    if (!ok) return;
    final draft = ref.read(profileDraftProvider);
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
            gender: draft.gender,
            countryIso: _licCountry,
            city: _city.text,
          ));
      ref.invalidate(myCounselorProvider);
      if (widget.setupMode && mounted) context.push(Routes.location);
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
    if (!widget.setupMode && (status == CounselorStatus.pending || status == CounselorStatus.approved || status == CounselorStatus.suspended)) {
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
      title: widget.setupMode ? null : l.screenCounselorApply,
      header: widget.setupMode ? const SetupProgress(step: 3, total: 5) : null,
      action: PrimaryButton(label: widget.setupMode ? l.continueLabel : l.submitForReview, loading: _busy, onPressed: _busy ? null : _submit),
      children: [
        if (status == CounselorStatus.rejected && mine.valueOrNull?.rejectReason != null) ...[
          InfoBanner(text: '${l.counselorRejected}: ${mine.valueOrNull!.rejectReason}', accent: true),
          const SizedBox(height: 14),
        ],
        if (widget.setupMode) PageHeading(l.aboutYouProfessional, body: l.counselorApplyBody) else Text(l.counselorApplyBody, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
        const SizedBox(height: 18),
        Text(l.counselorType, style: t.inputLabel),
        const SizedBox(height: 8),
        // the kind follows the account type chosen at sign-up
        Align(alignment: AlignmentDirectional.centerStart, child: OlfaTag(kindLabel(l, _kind), style: OlfaTagStyle.primary, icon: Icons.verified_user_outlined)),
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
        OlfaTextField(label: l.cityOfPractice, controller: _city),
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
        const SizedBox(height: 22),
        // Professional policy: the 15% commission and the off-platform rules, accepted explicitly.
        OlfaCard(
          padding: const EdgeInsets.all(16),
          color: OlfaColors.primaryTint(),
          borderColor: _submitted && !_policy ? OlfaColors.primary : OlfaColors.primaryTint(0.2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.policySummaryTitle, style: t.h3),
            const SizedBox(height: 8),
            for (final p in [l.policyPoint1(kPlatformFeePercent), l.policyPoint2, l.policyPoint3, l.policyPoint4])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.circle, size: 6, color: OlfaColors.primary)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p, style: t.bodySmall)),
                ]),
              ),
            Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: () => context.push(Routes.professionalPolicy), child: Text(l.readProfessionalPolicy))),
            OlfaCheck(value: _policy, onChanged: (v) => setState(() => _policy = v), label: l.acceptProfessionalPolicy),
          ]),
        ),
      ],
    );
  }
}

/// C6 — Counselor desk: at-a-glance numbers, then Requests (paid, waiting
/// for you), Upcoming (confirmed — open the chat; you may write first) and
/// Completed; plus your profile status and prices.
class CounselorDeskScreen extends ConsumerStatefulWidget {
  const CounselorDeskScreen({super.key});
  @override
  ConsumerState<CounselorDeskScreen> createState() => _CounselorDeskScreenState();
}

enum _DeskTab { requests, upcoming, completed }

class _CounselorDeskScreenState extends ConsumerState<CounselorDeskScreen> {
  _DeskTab _tab = _DeskTab.requests;

  Future<void> _act(Future<void> Function() op) async {
    try {
      await op();
      ref
        ..invalidate(counselorDeskProvider)
        ..invalidate(conversationIndexProvider);
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    }
  }

  Future<void> _confirm(Consultation k) async {
    final l = AppLocalizations.of(context);
    // The client picked one of your published times: confirm it in one tap (or propose another).
    if (k.preferredTime != null && k.preferredTime!.isAfter(DateTime.now())) {
      final at = DateFormat.yMMMMEEEEd(langOf(context)).add_Hm().format(k.preferredTime!);
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l.confirmPickedTime, style: c.type.h3),
              const SizedBox(height: 6),
              Text(at, style: c.type.bodyLarge),
              const SizedBox(height: 16),
              PrimaryButton(label: l.confirmBooking, onPressed: () => Navigator.pop(c, 'ok')),
              const SizedBox(height: 8),
              SecondaryButton(label: l.proposeOtherTime, onPressed: () => Navigator.pop(c, 'other')),
            ]),
          ),
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'ok') {
        String? conv;
        await _act(() async => conv = await ref.read(consultationsRepositoryProvider).confirm(k.id, k.preferredTime!));
        if (conv != null && mounted) context.pushOnce(Routes.chatWith(conv!));
        return;
      }
    }
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), initialDate: now.add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 0));
    if (tm == null || !mounted) return;
    String? conv;
    await _act(() async => conv = await ref.read(consultationsRepositoryProvider).confirm(k.id, DateTime(d.year, d.month, d.day, tm.hour, tm.minute)));
    if (conv != null && mounted) context.pushOnce(Routes.chatWith(conv!));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final me = ref.watch(myCounselorProvider).valueOrNull;
    final integrity = ref.watch(integrityCaseProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenCounselorDesk), automaticallyImplyLeading: context.canPop()),
      body: AsyncView<List<Consultation>>(
        value: ref.watch(counselorDeskProvider),
        onRetry: () => ref.invalidate(counselorDeskProvider),
        data: (list) {
          final requests = list.where((k) => k.status == ConsultationStatus.paid).toList();
          final upcoming = list.where((k) => k.status == ConsultationStatus.confirmed).toList()
            ..sort((a, b) => (a.scheduledAt ?? a.createdAt).compareTo(b.scheduledAt ?? b.createdAt));
          final done = list.where((k) => k.status == ConsultationStatus.completed).toList();
          final now = DateTime.now();
          final monthDone = done.where((k) => k.createdAt.year == now.year && k.createdAt.month == now.month).toList();
          final currency = list.isEmpty ? 'AED' : list.first.currency;
          final monthValue = monthDone.where((k) => k.currency == currency).fold<int>(0, (a, k) => a + k.priceMinor);
          final shown = switch (_tab) { _DeskTab.requests => requests, _DeskTab.upcoming => upcoming, _DeskTab.completed => done };
          return RefreshIndicator(
            color: OlfaColors.primary,
            onRefresh: () => ref.refresh(counselorDeskProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                // profile header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: OlfaColors.black, borderRadius: OlfaRadius.all(OlfaRadius.card)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const CounselorAvatar(size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(me?.name ?? '', style: t.h3.copyWith(color: OlfaColors.white), overflow: TextOverflow.ellipsis),
                          Text(me == null ? '' : kindLabel(l, me.kind), style: t.caption.copyWith(color: OlfaColors.white.withValues(alpha: 0.7))),
                        ]),
                      ),
                      // live = taking bookings on published hours (tap to manage)
                      Builder(builder: (_) {
                        final sch = ref.watch(myScheduleProvider).valueOrNull;
                        final live = sch == null || (sch.published && sch.settings.accepting);
                        return InkWell(
                          onTap: () => context.push(Routes.counselorSchedule),
                          borderRadius: OlfaRadius.all(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: live ? OlfaColors.primary : OlfaColors.white.withValues(alpha: 0.15), borderRadius: OlfaRadius.all(12)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(live ? Icons.circle : Icons.pause_rounded, size: 8, color: OlfaColors.white),
                              const SizedBox(width: 6),
                              Text(live ? l.counselorLive : l.bookingsPaused, style: t.caption.copyWith(color: OlfaColors.white, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        );
                      }),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      _DeskStat(value: '${requests.length}', label: l.incomingRequests, highlight: requests.isNotEmpty),
                      _DeskStat(value: '${upcoming.length}', label: l.upcomingSessions),
                      _DeskStat(value: me == null || me.ratingCount == 0 ? '—' : me.ratingAvg.toStringAsFixed(1), label: l.rating),
                      _DeskStat(value: monthValue == 0 ? '—' : money(context, monthValue, currency), label: l.thisMonth),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _DeskShortcut(icon: Icons.event_available_outlined, label: l.myHours, sub: _hoursSummary(context, ref), onTap: () => context.push(Routes.counselorSchedule))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DeskShortcut(
                      icon: Icons.star_outline_rounded,
                      label: l.ratingsAndReviews,
                      sub: me == null || me.ratingCount == 0 ? l.noRatingsYet : '${me.ratingAvg.toStringAsFixed(1)} · ${l.reviewsCount(me.ratingCount)}',
                      onTap: () => context.push(Routes.counselorReviews),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (integrity != null && (integrity.isOpen || integrity.status == IntegrityCaseStatus.warned)) ...[
                  IntegrityBanner(c: integrity),
                  const SizedBox(height: 12),
                ],
                InfoBanner(
                  text: l.deskCommissionNote,
                  icon: Icons.account_balance_wallet_outlined,
                  trailing: TextButton(onPressed: () => context.go(Routes.wallet), child: Text(l.walletTitle)),
                ),
                const SizedBox(height: 12),
                if ((me?.offerings ?? const []).isEmpty)
                  InfoBanner(text: l.addPricesFirst, accent: true, trailing: TextButton(onPressed: () => showOfferingSheet(context, ref, me), child: Text(l.add)))
                else
                  _PricesStrip(counselor: me!, onEdit: () => showOfferingSheet(context, ref, me)),
                const SizedBox(height: 16),
                SegmentedButton<_DeskTab>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: _DeskTab.requests, label: Text('${l.deskRequests} ${requests.isEmpty ? '' : '· ${requests.length}'}')),
                    ButtonSegment(value: _DeskTab.upcoming, label: Text(l.deskUpcoming)),
                    ButtonSegment(value: _DeskTab.completed, label: Text(l.deskCompleted)),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                ),
                const SizedBox(height: 14),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(children: [
                      Icon(_tab == _DeskTab.requests ? Icons.inbox_outlined : Icons.event_available_outlined, size: 40, color: OlfaColors.textMuted),
                      const SizedBox(height: 8),
                      Text(switch (_tab) { _DeskTab.requests => l.noIncoming, _DeskTab.upcoming => l.noUpcoming, _DeskTab.completed => l.noCompleted }, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
                    ]),
                  ),
                for (final k in shown)
                  _DeskCard(
                    k: k,
                    onConfirm: () => _confirm(k),
                    onDecline: () async {
                      final ok = await showConfirmation(context, title: l.declineBooking, body: l.declineBookingBody, confirmLabel: l.declineBooking, destructive: true);
                      if (ok) await _act(() => ref.read(consultationsRepositoryProvider).decline(k.id));
                    },
                    onComplete: () => _act(() => ref.read(consultationsRepositoryProvider).complete(k.id)),
                  ),
                const SizedBox(height: 8),
                Text(l.deskFootnote, style: t.caption),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _hoursSummary(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context);
  final s = ref.watch(myScheduleProvider).valueOrNull;
  if (s == null) return '…';
  if (!s.published) return l.hoursNotSet;
  if (!s.settings.accepting) return l.bookingsPaused;
  return l.hoursDaysCount(s.windows.map((w) => w.weekday).toSet().length);
}

class _DeskShortcut extends StatelessWidget {
  const _DeskShortcut({required this.icon, required this.label, required this.sub, required this.onTap});
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: OlfaColors.white,
        shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(OlfaRadius.card), side: const BorderSide(color: OlfaColors.gray)),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: OlfaRadius.all(OlfaRadius.card)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: OlfaColors.primary),
              const SizedBox(height: 8),
              Text(label, style: context.type.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
              Text(sub, style: context.type.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
}

class _DeskStat extends StatelessWidget {
  const _DeskStat({required this.value, required this.label, this.highlight = false});
  final String value;
  final String label;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: context.type.h2.copyWith(color: highlight ? OlfaColors.white : OlfaColors.white.withValues(alpha: 0.92))),
          ),
          Text(label, maxLines: 2, style: context.type.caption.copyWith(color: OlfaColors.white.withValues(alpha: 0.65))),
        ]),
      );
}

class _PricesStrip extends StatelessWidget {
  const _PricesStrip({required this.counselor, required this.onEdit});
  final Counselor counselor;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return OlfaCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(children: [
        const Icon(Icons.sell_outlined, color: OlfaColors.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final o in counselor.offerings)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: OlfaTag('${serviceLabel(l, o.service)} · ${l.minutesShort(o.durationMinutes)} · ${money(context, o.priceMinor, o.currency)}'),
                ),
            ]),
          ),
        ),
        TextButton(onPressed: onEdit, child: Text(l.edit)),
      ]),
    );
  }
}

class _DeskCard extends StatelessWidget {
  const _DeskCard({required this.k, required this.onConfirm, required this.onDecline, required this.onComplete});
  final Consultation k;
  final VoidCallback onConfirm;
  final VoidCallback onDecline;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final initials = (k.clientName ?? '?').trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w.characters.first).join();
    final when = k.scheduledAt ?? k.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OlfaCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: OlfaColors.primaryTint(), shape: BoxShape.circle),
              child: Text(initials, style: t.bodyMedium.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k.clientName ?? '', style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                Text('${serviceLabel(l, k.service)} · ${l.minutesShort(k.durationMinutes)} · ${languageName(context, k.language)}', style: t.caption),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(context, k.priceMinor, k.currency), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              StatusPill(k.status),
            ]),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Icon(k.scheduledAt != null ? Icons.event_rounded : Icons.payments_outlined, size: 16, color: OlfaColors.primary),
            const SizedBox(width: 6),
            Text(
              k.scheduledAt != null ? DateFormat.yMMMEd(langOf(context)).add_Hm().format(when) : '${l.paidOn} ${DateFormat.MMMd(langOf(context)).add_Hm().format(when)}',
              style: t.bodySmall,
            ),
          ]),
          if (k.scheduledAt == null && k.preferredTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Icon(Icons.schedule_rounded, size: 16, color: OlfaColors.primary),
                const SizedBox(width: 6),
                Text('${l.clientPicked}: ${DateFormat.yMMMEd(langOf(context)).add_Hm().format(k.preferredTime!)}', style: t.bodySmall.copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
          // escrow: the fee waits for the client's confirmation + rating
          if (k.status == ConsultationStatus.completed && k.escrow != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OlfaTag(
                switch (k.escrow) { 'RELEASED' => l.escrowReleasedTag, 'DISPUTED' => l.escrowDisputedTag, 'REFUNDED' => l.escrowRefundedTag, _ => l.escrowHeldTag },
                style: k.escrow == 'RELEASED' ? OlfaTagStyle.accent : OlfaTagStyle.neutral,
                icon: k.escrow == 'RELEASED' ? Icons.check_rounded : Icons.lock_clock_outlined,
              ),
            ),
          // what the counselor receives: price − 15% platform commission
          Builder(builder: (_) {
            final fee = (k.priceMinor * kPlatformFeePercent + 50) ~/ 100;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.deskYouReceive(money(context, k.priceMinor - fee, k.currency), kPlatformFeePercent), style: t.caption.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w600)),
            );
          }),
          if (k.note != null && k.note!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(12)),
              child: Text(k.note!, style: t.bodySmall),
            ),
          const SizedBox(height: 12),
          if (k.status == ConsultationStatus.paid)
            Row(children: [
              Expanded(child: SecondaryButton(label: l.declineBooking, onPressed: onDecline)),
              const SizedBox(width: 10),
              Expanded(child: PrimaryButton(label: l.confirmAndSchedule, icon: Icons.event_available_rounded, onPressed: onConfirm)),
            ])
          else if (k.status == ConsultationStatus.confirmed)
            Row(children: [
              Expanded(child: SecondaryButton(label: l.markCompleted, onPressed: onComplete)),
              const SizedBox(width: 10),
              if (k.conversationId != null)
                Expanded(child: PrimaryButton(label: l.openChat, icon: Icons.chat_bubble_outline_rounded, onPressed: () => context.pushOnce(Routes.chatWith(k.conversationId!)))),
            ])
          else if (k.conversationId != null)
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => context.pushOnce(Routes.chatWith(k.conversationId!)), child: Text(l.openChat))),
        ]),
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


/// Platform commission shown to counselors (server setting consultations.platformFeePercent;
/// the exact split is fixed on each booking when the client pays).
const kPlatformFeePercent = 15;

/// Integrity review notice on the counselor desk: what happened, the deadline,
/// and a way to respond before any decision. Never says who reported what.
class IntegrityBanner extends ConsumerStatefulWidget {
  const IntegrityBanner({super.key, required this.c});
  final IntegrityCase c;
  @override
  ConsumerState<IntegrityBanner> createState() => _IntegrityBannerState();
}

class _IntegrityBannerState extends ConsumerState<IntegrityBanner> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _respond() async {
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.integrityRespondTitle, style: ctx.type.h2),
            const SizedBox(height: 6),
            Text(l.integrityRespondBody, style: ctx.type.bodySmall.copyWith(color: OlfaColors.textMuted)),
            const SizedBox(height: 14),
            OlfaTextField(label: l.yourResponse, controller: _text, maxLines: 6, maxLength: 3000, counter: true),
            PrimaryButton(
              label: l.sendResponse,
              loading: _busy,
              onPressed: () async {
                if (_text.text.trim().length < 20) {
                  showToast(ctx, l.responseTooShort);
                  return;
                }
                set(() => _busy = true);
                try {
                  await ref.read(consultationsRepositoryProvider).respondIntegrity(widget.c.id, _text.text);
                  ref.invalidate(integrityCaseProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } on Failure catch (e) {
                  if (ctx.mounted) showToast(ctx, failureMessage(ctx, e));
                } finally {
                  set(() => _busy = false);
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final c = widget.c;
    final due = c.responseDueAt == null ? '' : DateFormat.yMMMd(langOf(context)).format(c.responseDueAt!);
    return OlfaCard(
      padding: const EdgeInsets.all(14),
      color: OlfaColors.primaryTint(),
      borderColor: OlfaColors.primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.policy_outlined, color: OlfaColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(c.status == IntegrityCaseStatus.warned ? l.integrityWarnedTitle : l.integrityTitle, style: t.h3)),
        ]),
        const SizedBox(height: 8),
        Text(
          switch (c.status) {
            IntegrityCaseStatus.awaitingResponse || IntegrityCaseStatus.open => l.integrityBodyRespond(due),
            IntegrityCaseStatus.underReview => l.integrityBodyReview,
            _ => c.decisionReason ?? '',
          },
          style: t.bodySmall,
        ),
        const SizedBox(height: 10),
        Row(children: [
          TextButton(onPressed: () => context.push(Routes.professionalPolicy), child: Text(l.professionalPolicy)),
          const Spacer(),
          if (c.needsResponse) PrimaryButton(label: l.respond, expand: false, onPressed: _respond),
        ]),
      ]),
    );
  }
}


/// Day chips, then the free times of that day (shown in the phone's time zone).
class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.slots, required this.day, required this.slot, required this.onDay, required this.onSlot, required this.onRetry, required this.fallback});
  final AsyncValue<SlotList> slots;
  final DateTime? day;
  final DateTime? slot;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<DateTime> onSlot;
  final VoidCallback onRetry;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final lang = langOf(context);
    return slots.when(
      loading: () => const OlfaSkeleton(height: 96),
      error: (e, _) => InfoBanner(text: failureMessage(context, e), trailing: TextButton(onPressed: onRetry, child: Text(l.retry))),
      data: (s) {
        if (!s.scheduled) return fallback;
        if (s.slots.isEmpty) return InfoBanner(text: l.noSlots, icon: Icons.event_busy_outlined, accent: true);
        final days = <DateTime>[];
        for (final x in s.slots) {
          final d = DateTime(x.year, x.month, x.day);
          if (days.isEmpty || days.last != d) days.add(d);
        }
        final selDay = day != null && days.contains(day) ? day! : days.first;
        final times = s.slots.where((x) => DateTime(x.year, x.month, x.day) == selDay).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.chooseTime, style: t.inputLabel),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = days[i];
                final on = d == selDay;
                return Semantics(
                  button: true,
                  selected: on,
                  label: DateFormat.yMMMMEEEEd(lang).format(d),
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => onDay(d),
                    borderRadius: OlfaRadius.all(14),
                    child: Container(
                      width: 58,
                      decoration: BoxDecoration(color: on ? OlfaColors.primary : OlfaColors.white, borderRadius: OlfaRadius.all(14), border: Border.all(color: on ? OlfaColors.primary : OlfaColors.gray)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(DateFormat.E(lang).format(d), style: t.caption.copyWith(color: on ? OlfaColors.white : OlfaColors.textMuted)),
                        Text(DateFormat.d(lang).format(d), style: t.h3.copyWith(color: on ? OlfaColors.white : OlfaColors.black)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in times) OlfaChoice(label: DateFormat.Hm(lang).format(x), selected: x == slot, onTap: () => onSlot(x)),
          ]),
          const SizedBox(height: 6),
          Text(l.slotsTimezoneNote, style: t.caption),
        ]);
      },
    );
  }
}

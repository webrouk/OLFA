import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../application/consultation_providers.dart';
import '../data/consultations_repository_impl.dart';
import '../domain/consultations_repository.dart';

String _hm(int minute) => '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

/// Weekday names starting Monday (ISO), in the app language.
List<String> _weekdays(BuildContext context) {
  final lang = langOf(context);
  final monday = DateTime(2026, 11, 30); // a Monday
  return [for (var i = 0; i < 7; i++) DateFormat.EEEE(lang).format(monday.add(Duration(days: i)))];
}

/// The counselor's own schedule: weekly hours, time off, and booking rules.
/// Clients can only book the times this produces; no double booking.
class CounselorScheduleScreen extends ConsumerStatefulWidget {
  const CounselorScheduleScreen({super.key});
  @override
  ConsumerState<CounselorScheduleScreen> createState() => _CounselorScheduleScreenState();
}

class _CounselorScheduleScreenState extends ConsumerState<CounselorScheduleScreen> {
  List<WeeklyWindow>? _windows; // edited copy
  ScheduleSettings? _settings;
  bool _saving = false;

  Future<void> _run(Future<void> Function() op, {String? done}) async {
    setState(() => _saving = true);
    try {
      await op();
      ref.invalidate(myScheduleProvider);
      if (mounted && done != null) showToast(context, done);
    } on Failure catch (e) {
      if (mounted) showToast(context, e is ValidationFailure ? AppLocalizations.of(context).hoursOverlap : failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addWindow(int weekday) async {
    final l = AppLocalizations.of(context);
    final start = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0), helpText: l.periodStart);
    if (start == null || !mounted) return;
    final end = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (start.hour + 3).clamp(0, 23), minute: start.minute), helpText: l.periodEnd);
    if (end == null || !mounted) return;
    final w = WeeklyWindow(weekday: weekday, startMinute: start.hour * 60 + start.minute, endMinute: end.hour * 60 + end.minute == 0 ? 1440 : end.hour * 60 + end.minute);
    if (w.endMinute <= w.startMinute) return showToast(context, l.periodEndAfterStart);
    if (_windows!.any(w.overlaps)) return showToast(context, l.hoursOverlap);
    setState(() => _windows = [..._windows!, w]..sort((a, b) => a.weekday != b.weekday ? a.weekday - b.weekday : a.startMinute - b.startMinute));
  }

  void _copyToAll(int weekday) {
    final src = _windows!.where((w) => w.weekday == weekday).toList();
    setState(() => _windows = [
          for (var d = 1; d <= 7; d++)
            for (final w in src) WeeklyWindow(weekday: d, startMinute: w.startMinute, endMinute: w.endMinute),
        ]);
  }

  Future<void> _addTimeOff() async {
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final r = await showDateRangePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), helpText: l.timeOffPick);
    if (r == null) return;
    await _run(() => ref.read(consultationsRepositoryProvider).addTimeOff(r.start, DateTime(r.end.year, r.end.month, r.end.day + 1)), done: l.saved);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final lang = langOf(context);
    final days = _weekdays(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.myHours)),
      body: AsyncView<CounselorSchedule>(
        value: ref.watch(myScheduleProvider),
        onRetry: () => ref.invalidate(myScheduleProvider),
        data: (sch) {
          _windows ??= List.of(sch.windows);
          _settings ??= sch.settings;
          final st = _settings!;
          final dirty = _windows!.length != sch.windows.length || [for (var i = 0; i < _windows!.length; i++) _windows![i]].any((w) => !sch.windows.any((x) => x.weekday == w.weekday && x.startMinute == w.startMinute && x.endMinute == w.endMinute));
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
                OlfaCard(
                  child: SwitchListTile.adaptive(
                    value: st.accepting,
                    onChanged: _saving
                        ? null
                        : (v) {
                            setState(() => _settings = st.copyWith(accepting: v));
                            _run(() => ref.read(consultationsRepositoryProvider).saveSchedule(_settings!), done: v ? l.bookingsOpened : l.bookingsPausedToast);
                          },
                    title: Text(l.acceptingBookings, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(st.accepting ? l.acceptingBookingsOn : l.acceptingBookingsOff, style: t.caption),
                  ),
                ),
                SectionLabel(l.weeklyHours, trailing: Text(l.timezoneLabel(st.timezone), style: t.caption)),
                OlfaCard(
                  child: Column(children: [
                    for (var d = 1; d <= 7; d++) ...[
                      if (d > 1) const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 92, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(days[d - 1], style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)))),
                          Expanded(
                            child: Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final w in _windows!.where((w) => w.weekday == d))
                                InputChip(
                                  label: Text('${_hm(w.startMinute)} – ${_hm(w.endMinute)}', textDirection: TextDirection.ltr),
                                  onDeleted: () => setState(() => _windows = _windows!.where((x) => x != w).toList()),
                                  deleteButtonTooltipMessage: l.remove,
                                ),
                              if (!_windows!.any((w) => w.weekday == d)) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.unavailable, style: t.caption)),
                            ]),
                          ),
                          PopupMenuButton<String>(
                            tooltip: l.more,
                            onSelected: (v) => v == 'add' ? _addWindow(d) : _copyToAll(d),
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'add', child: Text(l.addPeriod)),
                              if (_windows!.any((w) => w.weekday == d)) PopupMenuItem(value: 'copy', child: Text(l.copyToAllDays)),
                            ],
                            icon: const Icon(Icons.add_circle_outline_rounded, color: OlfaColors.primary),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),
                if (dirty) ...[
                  const SizedBox(height: 10),
                  PrimaryButton(label: l.saveHours, loading: _saving, onPressed: () => _run(() async => ref.read(consultationsRepositoryProvider).saveAvailability(_windows!), done: l.saved)),
                ],
                SectionLabel(l.bookingRules),
                OlfaCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    _RuleRow(label: l.ruleBuffer, value: l.minutesShort(st.bufferMinutes), options: const [0, 5, 10, 15, 30], format: (v) => l.minutesShort(v), onPick: (v) => setState(() => _settings = st.copyWith(bufferMinutes: v))),
                    _RuleRow(label: l.ruleNotice, value: l.hoursShort(st.minNoticeHours), options: const [1, 3, 6, 12, 24, 48], format: (v) => l.hoursShort(v), onPick: (v) => setState(() => _settings = st.copyWith(minNoticeHours: v))),
                    _RuleRow(label: l.ruleHorizon, value: l.daysShort(st.maxDaysAhead), options: const [7, 14, 30, 60, 90], format: (v) => l.daysShort(v), onPick: (v) => setState(() => _settings = st.copyWith(maxDaysAhead: v))),
                    if (st != sch.settings && (st.bufferMinutes != sch.settings.bufferMinutes || st.minNoticeHours != sch.settings.minNoticeHours || st.maxDaysAhead != sch.settings.maxDaysAhead)) ...[
                      const SizedBox(height: 8),
                      PrimaryButton(label: l.saveRules, loading: _saving, onPressed: () => _run(() async => ref.read(consultationsRepositoryProvider).saveSchedule(_settings!), done: l.saved)),
                    ],
                  ]),
                ),
                SectionLabel(l.timeOff, trailing: TextButton.icon(onPressed: _saving ? null : _addTimeOff, icon: const Icon(Icons.add_rounded, size: 18), label: Text(l.add))),
                if (sch.timeOff.isEmpty)
                  Text(l.noTimeOff, style: t.caption)
                else
                  TileGroup(children: [
                    for (final o in sch.timeOff)
                      OlfaListTile(
                        icon: Icons.beach_access_outlined,
                        title: '${DateFormat.yMMMd(lang).format(o.startsAt)} – ${DateFormat.yMMMd(lang).format(o.endsAt.subtract(const Duration(minutes: 1)))}',
                        subtitle: o.note,
                        showChevron: false,
                        trailing: IconButton(tooltip: l.remove, icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _run(() => ref.read(consultationsRepositoryProvider).removeTimeOff(o.id))),
                      ),
                  ]),
                const SizedBox(height: 16),
                InfoBanner(text: l.scheduleNote, icon: Icons.info_outline_rounded),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.value, required this.options, required this.format, required this.onPick});
  final String label;
  final String value;
  final List<int> options;
  final String Function(int) format;
  final ValueChanged<int> onPick;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: context.type.bodyMedium)),
          PopupMenuButton<int>(
            onSelected: onPick,
            itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o, child: Text(format(o)))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(value, style: context.type.bodyMedium.copyWith(fontWeight: FontWeight.w700, color: OlfaColors.primary)),
                const Icon(Icons.expand_more_rounded, color: OlfaColors.primary),
              ]),
            ),
          ),
        ]),
      );
}

/// The counselor's ratings: averages per question, star distribution, and the
/// reviews with a public reply (contact details are refused by the server).
class CounselorReviewsScreen extends ConsumerWidget {
  const CounselorReviewsScreen({super.key});

  Future<void> _reply(BuildContext context, WidgetRef ref, CounselorReview r) async {
    final l = AppLocalizations.of(context);
    final c = TextEditingController(text: r.reply);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsetsDirectional.fromSTEB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.replyToReview, style: ctx.type.h3),
          const SizedBox(height: 4),
          Text(l.replyToReviewHint, style: ctx.type.caption),
          const SizedBox(height: 12),
          OlfaTextField(label: l.yourReply, controller: c, maxLines: 4, maxLength: 1000),
          PrimaryButton(label: l.publishReply, onPressed: () => Navigator.pop(ctx, c.text.trim())),
        ]),
      ),
    );
    c.dispose();
    if (text == null || text.length < 2) return;
    try {
      await ref.read(consultationsRepositoryProvider).replyToReview(r.consultationId, text);
      ref.invalidate(myReviewsProvider);
    } on Failure catch (e) {
      if (context.mounted) showToast(context, failureMessage(context, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final lang = langOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.ratingsAndReviews)),
      body: AsyncView<MyReviews>(
        value: ref.watch(myReviewsProvider),
        onRetry: () => ref.invalidate(myReviewsProvider),
        data: (m) {
          final r = m.ratings;
          if (r.count == 0) return EmptyState(icon: Icons.star_outline_rounded, title: l.noRatingsYet, body: l.noRatingsBody);
          final maxN = r.distribution.values.fold<int>(1, (a, b) => b > a ? b : a);
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
            OlfaCard(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  Text((r.average ?? 0).toStringAsFixed(1), style: t.h1.copyWith(fontSize: 40, color: OlfaColors.primary)),
                  Row(children: [for (var i = 1; i <= 5; i++) Icon(i <= (r.average ?? 0).round() ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: OlfaColors.primary)]),
                  const SizedBox(height: 4),
                  Text(l.reviewsCount(r.count), style: t.caption),
                ]),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(children: [
                    for (var s = 5; s >= 1; s--)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          SizedBox(width: 14, child: Text('$s', style: t.caption)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: OlfaRadius.all(4),
                              child: LinearProgressIndicator(value: (r.distribution[s] ?? 0) / maxN, minHeight: 7, backgroundColor: OlfaColors.gray, color: OlfaColors.primary),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(width: 22, child: Text('${r.distribution[s] ?? 0}', style: t.caption, textAlign: TextAlign.end)),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            OlfaCard(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                for (final (label, v) in [(l.qQuality, r.quality), (l.qCommitment, r.commitment), (l.qEffectiveness, r.effectiveness), (l.qOutcome, r.outcome)])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(child: Text(label, style: t.bodySmall)),
                      Text(v == null ? '—' : v.toStringAsFixed(1), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
            SectionLabel(l.latestReviews),
            for (final rv in m.reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OlfaCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      for (var i = 1; i <= 5; i++) Icon(i <= rv.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: OlfaColors.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${rv.by ?? ''} · ${DateFormat.yMMMd(lang).format(rv.createdAt)}', style: t.caption)),
                    ]),
                    if (rv.comment != null && rv.comment!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(rv.comment!, style: t.bodyMedium)),
                    if (rv.reply != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.yourReply, style: t.caption.copyWith(fontWeight: FontWeight.w600)),
                          Text(rv.reply!, style: t.bodySmall),
                        ]),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(onPressed: () => _reply(context, ref, rv), child: Text(rv.reply == null ? l.reply : l.editReply)),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

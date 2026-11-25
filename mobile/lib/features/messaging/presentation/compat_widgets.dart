import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../application/chat_controller.dart';

String compatDomainLabel(AppLocalizations l, CompatDomain d) => switch (d) {
      CompatDomain.finance => l.compatDomainFinance,
      CompatDomain.future => l.compatDomainFuture,
      CompatDomain.familyRoles => l.compatDomainFamily,
      CompatDomain.lifestyle => l.compatDomainLifestyle,
      CompatDomain.marriage => l.compatDomainMarriage,
    };

IconData compatDomainIcon(CompatDomain d) => switch (d) {
      CompatDomain.finance => Icons.account_balance_wallet_outlined,
      CompatDomain.future => Icons.flag_outlined,
      CompatDomain.familyRoles => Icons.diversity_3_outlined,
      CompatDomain.lifestyle => Icons.local_cafe_outlined,
      CompatDomain.marriage => Icons.favorite_border_rounded,
    };

/// One slim line under the chat header: start, my progress and the other
/// person's progress (never their answers). Hidden once the result is out —
/// the result card is in the thread itself.
class CompatStrip extends ConsumerWidget {
  const CompatStrip({super.key, required this.conversationId, required this.peerName});
  final String conversationId;
  final String peerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final s = ref.watch(compatControllerProvider(conversationId)).valueOrNull;
    if (s == null || !s.enabled || s.status == CompatStatus.result) return const SizedBox.shrink();
    final started = s.status == CompatStatus.inProgress;
    final peer = s.peerCompleted ? l.compatPeerDone(peerName) : (s.peerStarted ? l.compatPeerAnswering(peerName) : l.compatPeerNotStarted(peerName));
    return Material(
      color: OlfaColors.white,
      child: InkWell(
        onTap: () => showCompatSheet(context, conversationId: conversationId, peerName: peerName),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 10, 6),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: OlfaColors.gray))),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: OlfaColors.primaryTint(), shape: BoxShape.circle),
              child: const Icon(Icons.join_inner_rounded, size: 17, color: OlfaColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(l.compatTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  started ? '${l.compatMyProgress(s.myAnswered, s.myTotal)} · $peer' : (s.peerStarted ? peer : l.compatPrivate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption,
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Text(
              s.iCompleted ? l.compatView : (started ? l.compatContinue : l.compatStart),
              style: t.bodySmall.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w700),
            ),
            const Icon(Icons.chevron_right_rounded, color: OlfaColors.primary, size: 20), // mirrors in RTL
          ]),
        ),
      ),
    );
  }
}

/// The questionnaire, inside the chat (a sheet over the conversation, which
/// stays loaded underneath). Every answer is saved as it is chosen.
Future<void> showCompatSheet(BuildContext context, {required String conversationId, required String peerName}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: OlfaColors.white,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scroll) => _CompatSheetBody(conversationId: conversationId, peerName: peerName, scroll: scroll),
      ),
    );

class _CompatSheetBody extends ConsumerStatefulWidget {
  const _CompatSheetBody({required this.conversationId, required this.peerName, required this.scroll});
  final String conversationId;
  final String peerName;
  final ScrollController scroll;
  @override
  ConsumerState<_CompatSheetBody> createState() => _CompatSheetBodyState();
}

class _CompatSheetBodyState extends ConsumerState<_CompatSheetBody> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await ref.read(compatControllerProvider(widget.conversationId).notifier).start();
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _answer(String q, String o) async {
    HapticFeedback.selectionClick();
    try {
      await ref.read(compatControllerProvider(widget.conversationId).notifier).answer(q, o);
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final lang = Localizations.localeOf(context).languageCode;
    final async = ref.watch(compatControllerProvider(widget.conversationId));
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator(color: OlfaColors.primary)),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(compatControllerProvider(widget.conversationId))),
      data: (s) {
        if (!s.enabled) return Padding(padding: const EdgeInsets.all(24), child: Text(l.compatOff, style: t.bodyMedium));
        if (s.status == CompatStatus.notStarted) {
          return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
            Text(l.compatTitle, style: t.h2),
            const SizedBox(height: 10),
            Text(l.compatIntro, style: t.bodyMedium),
            const SizedBox(height: 18),
            for (final d in CompatDomain.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Icon(compatDomainIcon(d), size: 20, color: OlfaColors.primary),
                  const SizedBox(width: 12),
                  Text(compatDomainLabel(l, d), style: t.bodyMedium),
                ]),
              ),
            const SizedBox(height: 8),
            InfoBanner(icon: Icons.lock_outline_rounded, text: l.compatPrivate),
            const SizedBox(height: 20),
            PrimaryButton(label: l.compatStart, loading: _starting, onPressed: _starting ? null : _start),
          ]);
        }
        // grouped by domain, in the order the server gave
        final groups = <CompatDomain, List<CompatQuestionItem>>{};
        for (final q in s.questions) {
          groups.putIfAbsent(q.domain, () => []).add(q);
        }
        var index = 0;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.compatTitle, style: t.h3),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: OlfaRadius.all(4),
                    child: LinearProgressIndicator(
                      value: s.myTotal == 0 ? 0 : s.myAnswered / s.myTotal,
                      minHeight: 6,
                      color: OlfaColors.primary,
                      backgroundColor: OlfaColors.gray,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(l.compatMyProgress(s.myAnswered, s.myTotal), style: t.caption),
              ]),
              const SizedBox(height: 4),
              Text(
                s.peerCompleted ? l.compatPeerDone(widget.peerName) : (s.peerStarted ? l.compatPeerAnswering(widget.peerName) : l.compatPeerNotStarted(widget.peerName)),
                style: t.caption,
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: widget.scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                if (s.iCompleted && s.status != CompatStatus.result)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: InfoBanner(accent: true, icon: Icons.hourglass_top_rounded, text: l.compatWaiting(widget.peerName))),
                for (final g in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                    child: Row(children: [
                      Icon(compatDomainIcon(g.key), size: 18, color: OlfaColors.primary),
                      const SizedBox(width: 8),
                      Text(compatDomainLabel(l, g.key), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  for (final q in g.value)
                    _QuestionCard(
                      number: ++index,
                      total: s.myTotal,
                      question: q,
                      lang: lang,
                      locked: s.status == CompatStatus.result,
                      onPick: (key) => _answer(q.id, key),
                    ),
                ],
                const SizedBox(height: 8),
                Text(l.compatPrivate, textAlign: TextAlign.center, style: t.caption),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.number, required this.total, required this.question, required this.lang, required this.locked, required this.onPick});
  final int number;
  final int total;
  final CompatQuestionItem question;
  final String lang;
  final bool locked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OlfaCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        borderColor: question.answer == null ? OlfaColors.gray : OlfaColors.primaryTint(0.6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.compatQuestionOf(number, total), style: t.caption),
          const SizedBox(height: 4),
          Text(question.text(lang), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in question.options)
              OlfaChoice(label: o.text(lang), selected: question.answer == o.key, small: true, onTap: locked ? () {} : () => onPick(o.key)),
          ]),
        ]),
      ),
    );
  }
}

/// The result, as its own card in the middle of the conversation — not a
/// message bubble: score, the five areas, and what is worth talking about.
class CompatResultCard extends StatelessWidget {
  const CompatResultCard({super.key, required this.result});
  final CompatResult result;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(color: OlfaColors.white, borderRadius: OlfaRadius.all(20), border: Border.all(color: OlfaColors.primary, width: 1.2)),
          child: Semantics(
            container: true,
            label: '${l.compatResultTitle}: ${result.score}%',
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.join_inner_rounded, size: 18, color: OlfaColors.primary),
                const SizedBox(width: 6),
                Text(l.compatResultTitle, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(child: CircularProgressIndicator(value: result.score / 100, strokeWidth: 7, color: OlfaColors.primary, backgroundColor: OlfaColors.gray)),
                  Text('${result.score}%', style: t.number(26)),
                ]),
              ),
              const SizedBox(height: 14),
              for (final d in result.domains)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(compatDomainIcon(d.domain), size: 16, color: OlfaColors.textMuted),
                    const SizedBox(width: 8),
                    SizedBox(width: 118, child: Text(compatDomainLabel(l, d.domain), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: OlfaRadius.all(3),
                        child: LinearProgressIndicator(value: d.score / 100, minHeight: 6, color: OlfaColors.primary, backgroundColor: OlfaColors.gray),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 36, child: Text('${d.score}%', textAlign: TextAlign.end, style: t.caption.copyWith(fontWeight: FontWeight.w600))),
                  ]),
                ),
              const Divider(height: 18),
              Text(l.compatAgreed(result.agreed), style: t.bodySmall),
              if (result.talkAbout.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(l.compatTalkAbout(result.talkAbout.length), style: t.bodySmall.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

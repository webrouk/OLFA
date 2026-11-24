import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../application/consultation_providers.dart';
import '../data/consultations_repository_impl.dart';

/// Mandatory questionnaire after every completed consultation.
///
/// Five quality ratings, then direct and indirect questions about whether the
/// counselor tried to continue outside OLFA. The client must answer before
/// booking again; answers are confidential — counselors see only the overall
/// stars and the comment, never who answered the other questions or how.
class ConsultationReviewScreen extends ConsumerStatefulWidget {
  const ConsultationReviewScreen({super.key, required this.consultationId, this.counselorName});
  final String consultationId;
  final String? counselorName;
  @override
  ConsumerState<ConsultationReviewScreen> createState() => _ConsultationReviewScreenState();
}

class _ConsultationReviewScreenState extends ConsumerState<ConsultationReviewScreen> {
  ReviewAnswers _a = const ReviewAnswers();
  final _comment = TextEditingController();
  bool _busy = false, _submitted = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_a.complete) {
      showToast(context, AppLocalizations.of(context).answerAllQuestions);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(consultationsRepositoryProvider).review(widget.consultationId, _a.copyWith(comment: _comment.text));
      ref.invalidate(myConsultationsProvider);
      ref.invalidate(pendingReviewsProvider);
      if (!mounted) return;
      showToast(context, AppLocalizations.of(context).ratingThanks);
      context.pop();
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
    Widget stars(String label, int value, ValueChanged<int> on) {
      final missing = _submitted && value == 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: missing ? OlfaColors.primary : null)),
          const SizedBox(height: 4),
          Row(children: [
            for (var i = 1; i <= 5; i++)
              Semantics(
                button: true,
                selected: i <= value,
                label: l.ratingOutOf5('$i'),
                child: InkResponse(
                  onTap: () => on(i),
                  radius: 24,
                  child: Padding(padding: const EdgeInsets.all(4), child: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, size: 34, color: OlfaColors.primary)),
                ),
              ),
          ]),
        ]),
      );
    }

    Widget choice<T>(String question, List<T> options, String Function(T) label, T? value, ValueChanged<T> on, {String? hint}) {
      final missing = _submitted && value == null;
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(question, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: missing ? OlfaColors.primary : null)),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint, style: t.caption)),
          const SizedBox(height: 8),
          ChoiceWrap<T>(options: options, label: label, isSelected: (o) => o == value, onTap: on),
        ]),
      );
    }

    String yn(YesNoUnsure v) => switch (v) { YesNoUnsure.no => l.answerNo, YesNoUnsure.yes => l.answerYes, YesNoUnsure.unsure => l.answerUnsure };

    return PopScope(
      canPop: true,
      child: FormPage(
        title: l.reviewTitle,
        action: PrimaryButton(label: l.submitReview, loading: _busy, onPressed: _busy ? null : _submit),
        children: [
          PageHeading(widget.counselorName == null ? l.reviewHeading : l.reviewHeadingNamed(widget.counselorName!), body: l.reviewIntro),
          OlfaCard(
            padding: const EdgeInsets.all(14),
            color: OlfaColors.primaryTint(),
            borderColor: OlfaColors.primaryTint(0.2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lock_outline_rounded, color: OlfaColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(l.reviewConfidential, style: t.bodySmall)),
            ]),
          ),
          SectionLabel(l.reviewSessionQuality),
          stars(l.qOverall, _a.rating, (v) => setState(() => _a = _a.copyWith(rating: v))),
          stars(l.qQuality, _a.quality, (v) => setState(() => _a = _a.copyWith(quality: v))),
          stars(l.qCommitment, _a.commitment, (v) => setState(() => _a = _a.copyWith(commitment: v))),
          stars(l.qEffectiveness, _a.effectiveness, (v) => setState(() => _a = _a.copyWith(effectiveness: v))),
          stars(l.qOutcome, _a.outcome, (v) => setState(() => _a = _a.copyWith(outcome: v))),
          SectionLabel(l.reviewNextSteps),
          choice<NextSession>(
            l.qNextSession,
            NextSession.values,
            (v) => switch (v) {
              NextSession.bookedInApp => l.nsBookedInApp,
              NextSession.planInApp => l.nsPlanInApp,
              NextSession.agreedOutside => l.nsAgreedOutside,
              NextSession.notDiscussed => l.nsNotDiscussed,
              NextSession.no => l.nsNo,
            },
            _a.nextSession,
            (v) => setState(() => _a = _a.copyWith(nextSession: v)),
          ),
          choice<NextChannel>(
            l.qNextChannel,
            NextChannel.values,
            (v) => switch (v) { NextChannel.olfa => l.ncOlfa, NextChannel.direct => l.ncDirect, NextChannel.otherApp => l.ncOtherApp, NextChannel.undecided => l.ncUndecided },
            _a.nextChannel,
            (v) => setState(() => _a = _a.copyWith(nextChannel: v)),
          ),
          SectionLabel(l.reviewSafety),
          choice<YesNoUnsure>(l.qContactShared, YesNoUnsure.values, yn, _a.contactShared, (v) => setState(() => _a = _a.copyWith(contactShared: v)), hint: l.qContactSharedHint),
          choice<YesNoUnsure>(l.qOffPlatformPayment, YesNoUnsure.values, yn, _a.offPlatformPayment, (v) => setState(() => _a = _a.copyWith(offPlatformPayment: v))),
          choice<YesNoUnsure>(l.qExternalChannel, YesNoUnsure.values, yn, _a.externalChannel, (v) => setState(() => _a = _a.copyWith(externalChannel: v)), hint: l.qExternalChannelHint),
          OlfaTextField(label: l.reviewComment, hint: l.reviewCommentHint, controller: _comment, maxLines: 3, maxLength: 1000),
          InfoBanner(text: l.reviewWhyOlfa, icon: Icons.shield_outlined),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Shown once per session to members who have a completed consultation to review.
Future<void> promptPendingReview(BuildContext context, PendingReview p) async {
  final l = AppLocalizations.of(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(18)),
          child: const Icon(Icons.rate_review_outlined, color: OlfaColors.primary),
        ),
        const SizedBox(height: 14),
        Text(l.reviewPromptTitle(p.counselorName), style: ctx.type.h2),
        const SizedBox(height: 6),
        Text(l.reviewPromptBody, style: ctx.type.bodyMedium.copyWith(color: OlfaColors.textMuted)),
        const SizedBox(height: 18),
        PrimaryButton(
          label: l.startReview,
          onPressed: () {
            Navigator.pop(ctx);
            context.push('/consultations/${p.consultationId}/review', extra: p.counselorName);
          },
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.later)),
      ]),
    ),
  );
}

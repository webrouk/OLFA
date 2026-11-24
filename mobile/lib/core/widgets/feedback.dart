import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/failure.dart';
import '../localization/generated/app_localizations.dart';
import '../theme/olfa_colors.dart';
import '../theme/olfa_spacing.dart';
import '../theme/olfa_typography.dart';
import 'buttons.dart';
import 'motion.dart';

/// Skeleton block with a gentle opacity pulse (no gradients — brand rule).
class OlfaSkeleton extends StatefulWidget {
  const OlfaSkeleton({super.key, this.width, this.height = 12, this.radius = 10, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  State<OlfaSkeleton> createState() => _OlfaSkeletonState();
}

class _OlfaSkeletonState extends State<OlfaSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.45).animate(_c),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: OlfaColors.gray,
          shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.circle ? null : OlfaRadius.all(widget.radius),
        ),
      ),
    );
  }
}

/// List-shaped loading skeleton (avatar + two lines) used by list screens.
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key, this.rows = 6, this.avatar = 48});
  final int rows;
  final double avatar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: 18),
        itemBuilder: (_, __) => Row(
          children: [
            OlfaSkeleton(width: avatar, height: avatar, circle: true),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [OlfaSkeleton(width: 140, height: 12), SizedBox(height: 8), OlfaSkeleton(width: 220, height: 10)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(28)),
              child: Icon(icon, size: 38, color: OlfaColors.primary),
            ),
            const SizedBox(height: 18),
            Text(title, style: t.h2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Maps any error to a localised, human message.
String failureMessage(BuildContext context, Object error) {
  final l = AppLocalizations.of(context);
  if (error is! Failure) return l.errorGeneric;
  return switch (error) {
    NetworkFailure() => l.errorNetwork,
    InvalidOtpFailure(:final attemptsLeft) => l.otpError(attemptsLeft),
    OtpRateLimitedFailure() => l.errorRateLimited,
    QuotaExceededFailure(:final quota) => switch (quota) {
        'likes' => l.quotaLikes,
        'messages' => l.quotaMessages,
        'compliments' => l.quotaCompliments,
        'voice_notes' => l.quotaVoiceNotes,
        _ => l.quotaUndos,
      },
    EntitlementRequiredFailure(:final feature) => switch (feature) {
        'visibleConversations' => l.lockedConversationsBody,
        'searchOutsideCountry' => l.outsideCountryLocked,
        _ => l.errorEntitlement,
      },
    AlreadyActedFailure() => l.errorDuplicate,
    AccountRestrictedFailure(:final permanent) => permanent ? l.closedPermanentTitle : l.closedTemporaryTitle,
    SlotUnavailableFailure() => l.slotTaken,
    SelfieChecksFailure() => l.selfieFailedTitle,
    ValidationFailure() => l.errorValidation,
    UnauthorizedFailure() => l.errorUnauthorized,
    ServerFailure(:final code) => switch (code) {
        'conversation_closed' => l.chatClosedUnmatched,
        'rematch_used' => l.rematchAlreadyUsed,
        'not_paid' => l.consultPayFirst,
        'account_type_locked' => l.errAccountTypeLocked,
        'wrong_account_type' => l.errWrongAccountType,
        'account_banned' => l.errAccountBanned,
        'insufficient_balance' => l.errInsufficientBalance,
        'review_required' => l.errReviewRequired,
        'store_verification_failed' => l.errStoreVerification,
        'selfie_required' => l.selfieStatusMissing,
        _ => l.errorGeneric,
      },
  };
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final offline = error is NetworkFailure;
    return EmptyState(
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: offline ? l.offlineTitle : l.errorTitle,
      body: failureMessage(context, error),
      action: PrimaryButton(label: l.retry, onPressed: onRetry, expand: false),
    );
  }
}

/// Standard loading / error / data switch for Riverpod AsyncValues.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, required this.onRetry, this.loading});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      data: data,
      loading: () => loading ?? const LoadingSkeleton(),
      error: (e, _) => ErrorState(error: e, onRetry: onRetry),
    );
  }
}

/// Brief, non-blocking message. Never stacks: replaces the current one.
void showToast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 2200)));
}

/// Confirmation bottom sheet (used for destructive or paid actions).
Future<bool> showConfirmation(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  IconData icon = Icons.help_outline_rounded,
  bool destructive = false,
}) async {
  final l = AppLocalizations.of(context);
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(18)),
              child: Icon(icon, color: OlfaColors.primary, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title, style: context.type.h2),
            const SizedBox(height: 8),
            Text(body, style: context.type.bodyMedium.copyWith(color: OlfaColors.textMuted)),
            const SizedBox(height: 22),
            PrimaryButton(label: confirmLabel, onPressed: () => Navigator.of(context).pop(true)),
            const SizedBox(height: 8),
            SecondaryButton(label: l.cancel, onPressed: () => Navigator.of(context).pop(false)),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

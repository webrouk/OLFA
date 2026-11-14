import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../data/matching_repository_impl.dart';

/// Full-screen "It's a match" moment with a calm scale-in animation.
Future<void> showMatchDialog(BuildContext context, WidgetRef ref, MatchItem match) {
  ref.invalidate(matchesProvider);
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: OlfaColors.primary,
    transitionDuration: motion(context, const Duration(milliseconds: 380)),
    pageBuilder: (context, _, __) => _MatchView(match: match),
    transitionBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: child),
    ),
  );
}

class _MatchView extends ConsumerStatefulWidget {
  const _MatchView({required this.match});
  final MatchItem match;
  @override
  ConsumerState<_MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends ConsumerState<_MatchView> {
  bool _busy = false;

  Future<void> _startChat() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(matchingRepositoryProvider).startConversation(widget.match.id);
      await ref.read(entitlementsProvider.notifier).refresh();
      ref.invalidate(matchesProvider);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push(Routes.chatWith(id));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, failureMessage(context, e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Material(
      color: OlfaColors.primary,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const OlfaLogo(size: 56, variant: OlfaLogoVariant.symbolOnly),
                  const SizedBox(height: 14),
                  Text(l.matchTitle, style: t.display.copyWith(color: OlfaColors.white), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(l.matchBody(widget.match.peer.name), style: t.bodyLarge.copyWith(color: OlfaColors.white.withValues(alpha: 0.85)), textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ring(const OlfaAvatar(size: 96)),
                      Transform.translate(offset: const Offset(-20, 0), child: _ring(OlfaAvatar(size: 96, url: widget.match.peer.mainPhoto?.thumbUrl))),
                    ],
                  ),
                  const SizedBox(height: 32),
                  PrimaryButton(label: l.startConversation, inverted: true, loading: _busy, onPressed: _startChat),
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: OlfaColors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.keepDiscovering),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(Widget child) => Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(color: OlfaColors.white, shape: BoxShape.circle),
        child: child,
      );
}

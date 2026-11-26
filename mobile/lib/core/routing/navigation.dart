import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opening the same page twice (a double tap on a card, a tap during a
/// transition) is ignored: one tap, one page, one load.
class PushGuard {
  PushGuard._();
  static String? _last;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static const window = Duration(milliseconds: 700);

  /// Whether a push of [location] at [now] should go ahead. Pure — tested.
  static bool allow(String location, String? current, DateTime now) {
    if (current == location) return false; // already on that page
    if (_last == location && now.difference(_at) < window) return false;
    _last = location;
    _at = now;
    return true;
  }

  @visibleForTesting
  static void reset() {
    _last = null;
    _at = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

extension OlfaNavigation on BuildContext {
  /// `push`, but a repeated tap or a tap on the page already shown does nothing.
  Future<T?> pushOnce<T extends Object?>(String location, {Object? extra}) {
    String? current;
    try {
      current = GoRouter.of(this).routerDelegate.currentConfiguration.uri.toString();
    } catch (_) {
      current = null;
    }
    if (!PushGuard.allow(location, current, DateTime.now())) return Future<T?>.value();
    return push<T>(location, extra: extra);
  }
}

/// Tapping the tab that is already open: the shell pops it to its first page
/// and the page scrolls back to the top.
final tabReselectProvider = StateProvider<({int tab, int tick})?>((_) => null);

/// Root of one tab: gives the tab its own scroll controller (so "scroll to
/// top" and the iOS status-bar tap work) and keeps the page alive while other
/// tabs are shown (the shell uses an IndexedStack).
class TabRoot extends ConsumerStatefulWidget {
  const TabRoot({super.key, required this.tab, required this.child});
  final int tab;
  final Widget child;

  @override
  ConsumerState<TabRoot> createState() => _TabRootState();
}

class _TabRootState extends ConsumerState<TabRoot> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tabReselectProvider, (_, next) {
      if (next == null || next.tab != widget.tab || !_controller.hasClients) return;
      for (final p in _controller.positions.toList()) {
        if (p.pixels <= 0) continue;
        final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        if (reduce || p.pixels > 3000) {
          p.jumpTo(0);
        } else {
          p.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
        }
      }
    });
    return PrimaryScrollController(controller: _controller, child: widget.child);
  }
}

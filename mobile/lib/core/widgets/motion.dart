import 'package:flutter/material.dart';

/// Honour the OS "reduce motion" setting everywhere animations are used.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

Duration motion(BuildContext context, Duration d) => reduceMotion(context) ? Duration.zero : d;

/// Subtle press feedback (scale 0.97) for tappable surfaces.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: motion(context, const Duration(milliseconds: 120)),
        child: widget.child,
      ),
    );
  }
}

/// Android page transition: a short fade with a 4% slide in the reading
/// direction (220 ms). Lighter than the zoom transition, so opening a profile
/// or a chat never stutters on mid-range phones. With "reduce motion" on,
/// pages switch instantly. iOS keeps the native Cupertino transition and its
/// edge-swipe back gesture.
class OlfaPageTransitionsBuilder extends PageTransitionsBuilder {
  const OlfaPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (reduceMotion(context)) return child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final out = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return SlideTransition(
      position: Tween(begin: Offset(rtl ? -0.04 : 0.04, 0), end: Offset.zero).animate(curve),
      child: FadeTransition(
        opacity: curve,
        // The page underneath fades back slightly instead of moving (less to repaint).
        child: FadeTransition(opacity: Tween(begin: 1.0, end: 0.92).animate(out), child: child),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/generated/app_localizations.dart';
import '../theme/olfa_colors.dart';
import '../theme/olfa_spacing.dart';
import 'motion.dart';

class OlfaNavItem {
  const OlfaNavItem(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The two tab sets, shared by the bottom bar and the side rail so both always
/// show the same tabs, icons and labels.
abstract final class OlfaNavItems {
  static List<OlfaNavItem> member(AppLocalizations l) => [
        OlfaNavItem(Icons.explore_outlined, Icons.explore, l.navDiscover),
        OlfaNavItem(Icons.favorite_border_rounded, Icons.favorite_rounded, l.navLikes),
        OlfaNavItem(Icons.people_outline_rounded, Icons.people_rounded, l.navMatches),
        OlfaNavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, l.navMessages),
        OlfaNavItem(Icons.person_outline_rounded, Icons.person_rounded, l.navProfile),
      ];

  static List<OlfaNavItem> professional(AppLocalizations l) => [
        OlfaNavItem(Icons.dashboard_customize_outlined, Icons.dashboard_customize_rounded, l.navDesk),
        OlfaNavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, l.navWallet),
        OlfaNavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, l.navMessages),
        OlfaNavItem(Icons.person_outline_rounded, Icons.person_rounded, l.navProfile),
      ];
}

/// Floating bottom navigation (phones) in tinted "liquid" glass, as on iOS:
///  - the page shows through, blurred and slightly more saturated, under a
///    pane tinted with the brand burgundy (between clear and the brand colour);
///  - light breaks on the glass: a bright rim along the top edge, a soft
///    specular glint, and a faint burgundy rim below (solid colours, no gradients);
///  - the active tab sits on a burgundy glass pill that slides to the next tab
///    and stretches like liquid on the way, then settles with a small spring;
///  - drag along the bar to scrub between tabs (the pill follows the finger,
///    a light tick on each tab, the tab opens on release); a press squeezes the icon.
/// High contrast / "reduce transparency" → an opaque bar; reduce motion → the
/// pill jumps without stretching. Order follows the reading direction.
class FloatingNavBar extends StatefulWidget {
  const FloatingNavBar({super.key, required this.items, required this.index, required this.onTap, this.badges = const {}});

  final List<OlfaNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  /// Tab index → count (0 or missing = no badge).
  final Map<int, int> badges;

  @override
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<FloatingNavBar> with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  double _from = 0; // pill position, in tab slots (0 = first tab at the start edge)
  double _to = 0;
  int? _scrub; // tab under the finger while dragging

  @override
  void initState() {
    super.initState();
    _from = _to = widget.index.toDouble();
  }

  @override
  void didUpdateWidget(FloatingNavBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _slideTo(widget.index.toDouble());
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  double get _pos => _from + (_to - _from) * Curves.easeOutBack.transform(_move.value);

  void _slideTo(double target) {
    _from = _pos;
    _to = target;
    if (MediaQuery.disableAnimationsOf(context)) {
      _move.value = 1;
    } else {
      _move.forward(from: 0);
    }
  }

  int _slotAt(Offset local, double width) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final x = rtl ? width - local.dx : local.dx;
    return (x / (width / widget.items.length)).floor().clamp(0, widget.items.length - 1).toInt();
  }

  void _drag(Offset local, double width) {
    final i = _slotAt(local, width);
    if (i == _scrub) return;
    HapticFeedback.selectionClick();
    setState(() => _scrub = i);
    _slideTo(i.toDouble());
  }

  void _release() {
    final i = _scrub;
    setState(() => _scrub = null);
    if (i == null) return;
    if (i != widget.index) {
      widget.onTap(i);
    } else {
      _slideTo(i.toDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final opaque = MediaQuery.highContrastOf(context);
    final radius = OlfaRadius.all(OlfaRadius.navBar);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final items = widget.items;
    return Padding(
      padding: EdgeInsets.fromLTRB(OlfaSize.navBarMargin, 0, OlfaSize.navBarMargin, bottom + 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          // Comfortable on large phones / small tablets instead of stretching edge to edge.
          constraints: const BoxConstraints(maxWidth: 520),
          child: DecoratedBox(
            // depth: a soft shadow outside the clip, faintly burgundy
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(color: OlfaColors.black.withValues(alpha: 0.10), blurRadius: 30, offset: const Offset(0, 12)),
                BoxShadow(color: OlfaColors.primary.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 6)),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                // blur + a little more saturation, so colours behind the glass stay alive
                filter: opaque ? ImageFilter.blur() : ImageFilter.compose(outer: _saturate(1.7), inner: ImageFilter.blur(sigmaX: 24, sigmaY: 24)),
                child: SizedBox(
                  height: OlfaSize.navBarHeight,
                  child: Stack(children: [
                    // the tint: between clear and the brand colour
                    Positioned.fill(child: ColoredBox(color: opaque ? OlfaColors.white : OlfaColors.white.withValues(alpha: 0.52))),
                    if (!opaque) Positioned.fill(child: ColoredBox(color: OlfaColors.primary.withValues(alpha: 0.10))),
                    // light breaking on the glass: top rim + specular glint + lower rim
                    if (!opaque) ...[
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: radius,
                            border: Border.all(color: OlfaColors.white.withValues(alpha: 0.45)),
                          ),
                        ),
                      ),
                      Positioned(left: 22, right: 22, top: 0.5, height: 1.2, child: ColoredBox(color: OlfaColors.white.withValues(alpha: 0.85))),
                      Positioned(left: 26, right: 26, bottom: 0.5, height: 1, child: ColoredBox(color: OlfaColors.primary.withValues(alpha: 0.14))),
                      PositionedDirectional(
                        top: -14,
                        start: 30,
                        width: 120,
                        height: 26,
                        child: IgnorePointer(
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: DecoratedBox(decoration: BoxDecoration(color: OlfaColors.white.withValues(alpha: 0.55), borderRadius: OlfaRadius.all(20))),
                          ),
                        ),
                      ),
                    ] else
                      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: OlfaColors.gray)))),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: LayoutBuilder(builder: (context, c) {
                        final slot = c.maxWidth / items.length;
                        return GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragStart: (d) => _drag(d.localPosition, c.maxWidth),
                          onHorizontalDragUpdate: (d) => _drag(d.localPosition, c.maxWidth),
                          onHorizontalDragEnd: (_) => _release(),
                          onHorizontalDragCancel: _release,
                          child: AnimatedBuilder(
                            animation: _move,
                            builder: (context, _) {
                              // liquid: wider and a touch flatter mid-way, back to shape on arrival
                              final t = _move.isAnimating ? _move.value : 1.0;
                              final travel = (_to - _from).abs().clamp(0.0, 1.0);
                              final stretch = math.sin(math.pi * t) * 0.38 * travel;
                              final w = (slot - 4) * (1 + stretch);
                              final center = slot * _pos + slot / 2;
                              final startX = center - w / 2;
                              final left = rtl ? c.maxWidth - startX - w : startX;
                              final squash = 1 - stretch * 0.22;
                              final pressed = _scrub != null;
                              return Stack(children: [
                                Positioned(
                                  left: left,
                                  width: w,
                                  top: 0,
                                  bottom: 0,
                                  child: Transform.scale(scaleY: squash * (pressed ? 1.06 : 1), child: _GlassPill(opaque: opaque)),
                                ),
                                Row(children: [
                                  for (var i = 0; i < items.length; i++)
                                    Expanded(
                                      child: _NavButton(
                                        item: items[i],
                                        active: i == (_scrub ?? widget.index),
                                        count: widget.badges[i] ?? 0,
                                        onTap: () => widget.onTap(i),
                                        onGlass: true,
                                      ),
                                    ),
                                ]),
                              ]);
                            },
                          ),
                        );
                      }),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static ColorFilter _saturate(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final i = 1 - s;
    return ColorFilter.matrix(<double>[
      r * i + s, g * i, b * i, 0, 0,
      r * i, g * i + s, b * i, 0, 0,
      r * i, g * i, b * i + s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }
}

/// The active-tab marker: a pane of burgundy-tinted glass with a bright top
/// rim — light catching its edge — and a soft burgundy glow below.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.opaque});
  final bool opaque;
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: opaque ? OlfaColors.primaryTint(0.12) : OlfaColors.primary.withValues(alpha: 0.13),
              borderRadius: OlfaRadius.all(20),
              border: Border.all(color: opaque ? OlfaColors.primary.withValues(alpha: 0.35) : OlfaColors.white.withValues(alpha: 0.55)),
              boxShadow: opaque ? null : [BoxShadow(color: OlfaColors.primary.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
            ),
          ),
        ),
        if (!opaque) Positioned(left: 14, right: 14, top: 1, height: 1.2, child: ColoredBox(color: OlfaColors.white.withValues(alpha: 0.9))),
      ]);
}

/// The same tabs as a vertical rail at the start edge (tablets, landscape).
class OlfaSideNav extends StatelessWidget {
  const OlfaSideNav({super.key, required this.items, required this.index, required this.onTap, this.badges = const {}, this.header});
  final List<OlfaNavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  final Map<int, int> badges;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      decoration: const BoxDecoration(color: OlfaColors.white, border: BorderDirectional(end: BorderSide(color: OlfaColors.gray))),
      child: SafeArea(
        right: false,
        left: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            if (header != null) ...[header!, const SizedBox(height: 20)],
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: SizedBox(height: 62, child: _NavButton(item: items[i], active: i == index, count: badges[i] ?? 0, onTap: () => onTap(i))),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({required this.item, required this.active, required this.count, required this.onTap, this.onGlass = false});
  final OlfaNavItem item;
  final bool active;
  final int count;
  final VoidCallback onTap;

  /// On the glass bar the sliding pill marks the active tab (no own background).
  final bool onGlass;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item, active = widget.active, count = widget.count, onTap = widget.onTap, onGlass = widget.onGlass;
    final l = AppLocalizations.of(context);
    // Inactive tabs use the muted text colour (≥ 4.5:1 on white), not the disabled one.
    final color = active ? OlfaColors.primary : OlfaColors.textMuted;
    return Semantics(
      button: true,
      selected: active,
      label: count > 0 ? '${item.label}, ${l.navBadgeCount(count)}' : item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onHighlightChanged: (v) => setState(() => _down = v),
        // the glass shows the press itself (the icon squeezes): no ripple on it
        splashFactory: onGlass ? NoSplash.splashFactory : null,
        highlightColor: onGlass ? Colors.transparent : null,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        borderRadius: OlfaRadius.all(17),
        child: AnimatedContainer(
          duration: motion(context, const Duration(milliseconds: 200)),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 54, minWidth: OlfaSize.minTap),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(color: active && !onGlass ? OlfaColors.primaryTint() : Colors.transparent, borderRadius: OlfaRadius.all(17)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // a small lift as the glass arrives under the tab
                  AnimatedScale(
                    // pressed: squeeze · active: a small lift as the glass arrives
                    scale: _down ? 0.86 : (active ? 1.12 : 1),
                    duration: motion(context, Duration(milliseconds: _down ? 90 : 320)),
                    curve: _down ? Curves.easeOut : Curves.elasticOut,
                    child: AnimatedSwitcher(
                      duration: motion(context, const Duration(milliseconds: 180)),
                      child: Icon(active ? item.activeIcon : item.icon, key: ValueKey(active), size: 26, color: color),
                    ),
                  ),
                  if (count > 0) PositionedDirectional(top: -6, end: -12, child: CountBadge(count: count)),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "1"…"99", then "99+".
String badgeText(int n) => n > 99 ? '99+' : '$n';

/// The one count badge used across the app (tabs, unread chats, quotas).
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.inverted = false});
  final int count;

  /// Black badge (e.g. on a burgundy surface or for an exhausted quota).
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inverted ? OlfaColors.black : OlfaColors.primary,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: OlfaColors.white, width: 1.5),
      ),
      child: Text(
        badgeText(count),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(color: OlfaColors.white, fontSize: 10.5, height: 1.2, fontWeight: FontWeight.w700, fontFamily: 'Montserrat'),
      ),
    );
  }
}

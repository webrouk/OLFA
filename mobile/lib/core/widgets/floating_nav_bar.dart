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
        OlfaNavItem(Icons.explore_outlined, Icons.explore, l.navExplore),
        OlfaNavItem(Icons.favorite_border_rounded, Icons.favorite_rounded, l.navLikes),
        OlfaNavItem(Icons.people_outline_rounded, Icons.people_rounded, l.navMarriage),
        OlfaNavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, l.navChat),
        OlfaNavItem(Icons.person_outline_rounded, Icons.person_rounded, l.navMenu),
      ];

  /// Member phone bar: Marriage · Explore · Chat · Menu in the capsule (reading
  /// order — in Arabic, Menu … Marriage from left to right) and Likes on its own
  /// round button at the far end (far left in Arabic), icon only.
  static const memberLayout = OlfaNavLayout(bar: [2, 0, 3, 4], solo: 1);

  static List<OlfaNavItem> professional(AppLocalizations l) => [
        OlfaNavItem(Icons.dashboard_customize_outlined, Icons.dashboard_customize_rounded, l.navDesk),
        OlfaNavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, l.navWallet),
        OlfaNavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, l.navMessages),
        OlfaNavItem(Icons.person_outline_rounded, Icons.person_rounded, l.navProfile),
      ];
}

/// Where each tab sits on the phone bar. [bar] lists tab indexes in reading
/// order inside the capsule; [solo] is the tab on its own round button at the
/// far end (far left in Arabic). Indexes are the router's tab indexes, so a tab
/// keeps its page whatever its place on screen.
class OlfaNavLayout {
  const OlfaNavLayout({required this.bar, this.solo});
  final List<int> bar;
  final int? solo;

  /// Every tab in the capsule, in index order.
  factory OlfaNavLayout.plain(int count) => OlfaNavLayout(bar: [for (var i = 0; i < count; i++) i]);
}

/// Floating bottom navigation (phones) in dark frosted glass, in two pieces:
/// a fully rounded capsule with the main tabs, and — when the layout has a
/// [OlfaNavLayout.solo] tab — a separate round button beside it at the far end.
///  - both float above the home indicator (SafeArea aware) over a light blur of
///    the page (σ 18, kept light for speed) under semi-transparent brand black,
///    with a thin translucent border, a faint light rim on top and a soft shadow
///    (solid colours, no gradients);
///  - the active tab sits on a lighter glass capsule that glides to the next tab
///    (a slight stretch on the way, fast, no flicker); the icon and label
///    cross-fade to white; a press squeezes the icon. When the round button is
///    the active one it fills with the same lighter glass and the capsule's
///    marker fades out;
///  - drag along the capsule to scrub between its tabs (a light tick on each,
///    the tab opens on release).
/// High contrast → opaque black; reduce motion → no glide. Pages keep clear of
/// the bar with [OlfaSize.navBarClearance].
class FloatingNavBar extends StatefulWidget {
  const FloatingNavBar({super.key, required this.items, required this.index, required this.onTap, this.badges = const {}, this.layout});

  final List<OlfaNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  /// Tab index → count (0 or missing = no badge).
  final Map<int, int> badges;

  /// Placement of the tabs; all in the capsule when null.
  final OlfaNavLayout? layout;

  @override
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<FloatingNavBar> with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 340), value: 1);
  double _from = 0; // marker position, in capsule slots (0 = first slot at the start edge)
  double _to = 0;
  int? _scrub; // capsule slot under the finger while dragging

  // quick start, soft landing with a hint of settle — no long bounce
  static const _glide = Cubic(0.2, 0.9, 0.25, 1.06);

  OlfaNavLayout get _layout => widget.layout ?? OlfaNavLayout.plain(widget.items.length);

  int? _slotOf(int index) {
    final s = _layout.bar.indexOf(index);
    return s < 0 ? null : s;
  }

  @override
  void initState() {
    super.initState();
    _from = _to = (_slotOf(widget.index) ?? 0).toDouble();
  }

  @override
  void didUpdateWidget(FloatingNavBar old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    final to = _slotOf(widget.index);
    if (to == null) return; // the round button: the marker fades out where it is
    final wasInBar = (old.layout ?? OlfaNavLayout.plain(old.items.length)).bar.contains(old.index);
    wasInBar ? _slideTo(to.toDouble()) : _jumpTo(to.toDouble()); // from the round button: fade in in place
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  double get _pos => _from + (_to - _from) * _glide.transform(_move.value);

  void _jumpTo(double slot) {
    _move.stop();
    _from = _to = slot;
    _move.value = 1;
  }

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
    final n = _layout.bar.length;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final x = rtl ? width - local.dx : local.dx;
    return (x / (width / n)).floor().clamp(0, n - 1).toInt();
  }

  void _drag(Offset local, double width) {
    final i = _slotAt(local, width);
    if (i == _scrub) return;
    HapticFeedback.selectionClick();
    final markerShown = _scrub != null || _slotOf(widget.index) != null;
    setState(() => _scrub = i);
    markerShown ? _slideTo(i.toDouble()) : _jumpTo(i.toDouble());
  }

  void _release() {
    final i = _scrub;
    setState(() => _scrub = null);
    if (i == null) return;
    final tab = _layout.bar[i];
    if (tab != widget.index) {
      widget.onTap(tab);
    } else {
      _slideTo(i.toDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final opaque = MediaQuery.highContrastOf(context);
    const h = OlfaSize.navBarHeight;
    final round = BorderRadius.circular(h / 2);
    final layout = _layout;
    final solo = layout.solo;
    return Padding(
      padding: EdgeInsets.fromLTRB(OlfaSize.navBarMargin, 0, OlfaSize.navBarMargin, bottom + 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          // Comfortable on large phones / small tablets instead of stretching edge to edge.
          constraints: const BoxConstraints(maxWidth: 560),
          child: SizedBox(
            height: h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Glass(radius: round, opaque: opaque, child: _capsule(layout, opaque))),
                if (solo != null) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: h,
                    child: _Glass(
                      radius: round,
                      opaque: opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Stack(fit: StackFit.expand, children: [
                          AnimatedOpacity(
                            opacity: widget.index == solo && _scrub == null ? 1 : 0,
                            duration: motion(context, const Duration(milliseconds: 180)),
                            child: _GlassPill(opaque: opaque, radius: h / 2),
                          ),
                          _NavButton(
                            item: widget.items[solo],
                            active: widget.index == solo && _scrub == null,
                            count: widget.badges[solo] ?? 0,
                            onTap: () => widget.onTap(solo),
                            onGlass: true,
                            showLabel: false,
                            radius: h / 2,
                          ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _capsule(OlfaNavLayout layout, bool opaque) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final bar = layout.bar;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(builder: (context, c) {
        final slot = c.maxWidth / bar.length;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) => _drag(d.localPosition, c.maxWidth),
          onHorizontalDragUpdate: (d) => _drag(d.localPosition, c.maxWidth),
          onHorizontalDragEnd: (_) => _release(),
          onHorizontalDragCancel: _release,
          child: AnimatedBuilder(
            animation: _move,
            builder: (context, _) {
              // a slight stretch mid-way, back to shape on arrival
              final t = _move.isAnimating ? _move.value : 1.0;
              final travel = (_to - _from).abs().clamp(0.0, 1.0);
              final stretch = math.sin(math.pi * t.clamp(0.0, 1.0)) * 0.22 * travel;
              final w = (slot - 4) * (1 + stretch);
              final center = slot * _pos + slot / 2;
              final startX = center - w / 2;
              final left = rtl ? c.maxWidth - startX - w : startX;
              final squash = 1 - stretch * 0.18;
              final pressed = _scrub != null;
              final current = pressed ? bar[_scrub!] : widget.index;
              final shown = pressed || bar.contains(widget.index);
              return Stack(children: [
                Positioned(
                  left: left,
                  width: w,
                  top: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: shown ? 1 : 0,
                    duration: motion(context, const Duration(milliseconds: 180)),
                    child: Transform.scale(scaleY: squash * (pressed ? 1.05 : 1), child: _GlassPill(opaque: opaque)),
                  ),
                ),
                Row(children: [
                  for (final tab in bar)
                    Expanded(
                      child: _NavButton(
                        item: widget.items[tab],
                        active: tab == current,
                        count: widget.badges[tab] ?? 0,
                        onTap: () => widget.onTap(tab),
                        onGlass: true,
                      ),
                    ),
                ]),
              ]);
            },
          ),
        );
      }),
    );
  }
}

/// A pane of dark frosted glass in the given shape: blur + a little saturation
/// behind, semi-transparent brand black, a thin translucent border, a faint
/// light rim on top and a soft shadow outside.
class _Glass extends StatelessWidget {
  const _Glass({required this.radius, required this.opaque, required this.child});
  final BorderRadius radius;
  final bool opaque;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: OlfaColors.black.withValues(alpha: 0.22), blurRadius: 26, offset: const Offset(0, 10)),
          BoxShadow(color: OlfaColors.black.withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // a light blur + a little saturation, so colours behind the glass stay alive
          filter: opaque ? ImageFilter.blur() : ImageFilter.compose(outer: _saturate(1.4), inner: ImageFilter.blur(sigmaX: 18, sigmaY: 18)),
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: opaque ? OlfaColors.black : OlfaColors.black.withValues(alpha: 0.70)),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: OlfaColors.white.withValues(alpha: opaque ? 0.30 : 0.14))),
              ),
            ),
            if (!opaque)
              Align(
                alignment: Alignment.topCenter,
                child: FractionallySizedBox(
                  widthFactor: 0.6,
                  child: Padding(padding: const EdgeInsets.only(top: 0.5), child: SizedBox(height: 1, child: ColoredBox(color: OlfaColors.white.withValues(alpha: 0.22)))),
                ),
              ),
            child,
          ]),
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

/// The active-tab marker: a lighter pane of glass inside the dark bar, with a
/// soft border, a faint light rim on top and a light shadow.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.opaque, this.radius = 20});
  final bool opaque;
  final double radius;
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: OlfaColors.white.withValues(alpha: opaque ? 0.22 : 0.15),
              borderRadius: OlfaRadius.all(radius),
              border: Border.all(color: OlfaColors.white.withValues(alpha: opaque ? 0.55 : 0.20)),
              boxShadow: opaque ? null : [BoxShadow(color: OlfaColors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))],
            ),
          ),
        ),
        if (!opaque)
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(widthFactor: 0.55, child: Padding(padding: const EdgeInsets.only(top: 1), child: SizedBox(height: 1, child: ColoredBox(color: OlfaColors.white.withValues(alpha: 0.30))))),
          ),
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
  const _NavButton({required this.item, required this.active, required this.count, required this.onTap, this.onGlass = false, this.showLabel = true, this.radius = 17});
  final OlfaNavItem item;
  final bool active;
  final int count;
  final VoidCallback onTap;

  /// On the glass bar the sliding pill marks the active tab (no own background).
  final bool onGlass;

  /// The round button shows its icon alone (the label stays for screen readers).
  final bool showLabel;
  final double radius;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item, active = widget.active, count = widget.count, onTap = widget.onTap, onGlass = widget.onGlass;
    final l = AppLocalizations.of(context);
    // On the dark glass: white for the active tab, 72 % white otherwise (≥ 4.5:1
    // on the bar). On the white side rail: burgundy / the muted text colour.
    final color = onGlass
        ? (active ? OlfaColors.white : OlfaColors.white.withValues(alpha: 0.72))
        : (active ? OlfaColors.primary : OlfaColors.textMuted);
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
        borderRadius: OlfaRadius.all(widget.radius),
        child: AnimatedContainer(
          duration: motion(context, const Duration(milliseconds: 200)),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 54, minWidth: OlfaSize.minTap),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(color: active && !onGlass ? OlfaColors.primaryTint() : Colors.transparent, borderRadius: OlfaRadius.all(widget.radius)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // a small lift as the glass arrives under the tab
                  AnimatedScale(
                    // pressed: squeeze · active: a small lift as the glass arrives
                    scale: _down ? 0.88 : (active ? 1.08 : 1),
                    duration: motion(context, Duration(milliseconds: _down ? 90 : 260)),
                    curve: _down ? Curves.easeOut : Curves.easeOutBack,
                    child: AnimatedSwitcher(
                      duration: motion(context, const Duration(milliseconds: 160)),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: Icon(active ? item.activeIcon : item.icon, key: ValueKey(active), size: 26, color: color),
                    ),
                  ),
                  // over the icon's top corner, outside it; never takes taps (the whole tab does)
                  if (count > 0) PositionedDirectional(top: -6, end: -12, child: IgnorePointer(child: CountBadge(count: count, ring: onGlass ? OlfaColors.black : OlfaColors.white))),
                ],
              ),
              if (widget.showLabel) const SizedBox(height: 3),
              if (widget.showLabel)
                Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color, height: 1.15),
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
  const CountBadge({super.key, required this.count, this.inverted = false, this.ring = OlfaColors.white});
  final int count;

  /// Black badge (e.g. on a burgundy surface or for an exhausted quota).
  final bool inverted;

  /// Colour of the thin ring that separates the badge from what is under it.
  final Color ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inverted ? OlfaColors.black : OlfaColors.primary,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: ring, width: 1.5),
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

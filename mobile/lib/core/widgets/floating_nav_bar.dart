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

/// Floating, rounded bottom navigation (phones). Order follows the reading
/// direction (RTL/LTR). Badges show real counts only.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.items, required this.index, required this.onTap, this.badges = const {}});

  final List<OlfaNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  /// Tab index → count (0 or missing = no badge).
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(OlfaSize.navBarMargin, 0, OlfaSize.navBarMargin, bottom + 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          // Comfortable on large phones / small tablets instead of stretching edge to edge.
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            height: OlfaSize.navBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: OlfaColors.white,
              borderRadius: OlfaRadius.all(OlfaRadius.navBar),
              border: Border.all(color: OlfaColors.gray),
              boxShadow: [BoxShadow(color: OlfaColors.black.withValues(alpha: 0.10), blurRadius: 30, offset: const Offset(0, 10))],
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(child: _NavButton(item: items[i], active: i == index, count: badges[i] ?? 0, onTap: () => onTap(i))),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.count, required this.onTap});
  final OlfaNavItem item;
  final bool active;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        borderRadius: OlfaRadius.all(17),
        child: AnimatedContainer(
          duration: motion(context, const Duration(milliseconds: 200)),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 54, minWidth: OlfaSize.minTap),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(color: active ? OlfaColors.primaryTint() : Colors.transparent, borderRadius: OlfaRadius.all(17)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(active ? item.activeIcon : item.icon, size: 23, color: color),
                  if (count > 0) PositionedDirectional(top: -6, end: -12, child: CountBadge(count: count)),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                style: TextStyle(fontSize: 10.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color),
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

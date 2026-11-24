import 'package:flutter/material.dart';

import '../localization/generated/app_localizations.dart';
import '../theme/olfa_colors.dart';
import '../theme/olfa_spacing.dart';

class OlfaNavItem {
  const OlfaNavItem(this.icon, this.activeIcon, this.label, {this.badge = false});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool badge;
}

/// Floating, rounded bottom navigation with external margins and SafeArea
/// support. Order follows reading direction automatically (RTL/LTR).
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.index, required this.onTap, this.badges = const {}, this.professional = false});

  final int index;
  final ValueChanged<int> onTap;
  final Set<int> badges;

  /// Professional accounts get their own tabs: desk, wallet, messages, profile.
  final bool professional;

  static List<OlfaNavItem> professionalItems(AppLocalizations l) => [
        OlfaNavItem(Icons.dashboard_customize_outlined, Icons.dashboard_customize_rounded, l.navDesk),
        OlfaNavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, l.navWallet),
        OlfaNavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, l.navMessages),
        OlfaNavItem(Icons.person_outline_rounded, Icons.person_rounded, l.navProfile),
      ];

  static List<OlfaNavItem> items(AppLocalizations l) => [
        OlfaNavItem(Icons.explore_outlined, Icons.explore, l.navDiscover),
        OlfaNavItem(Icons.favorite_border_rounded, Icons.favorite_rounded, l.navLikes),
        OlfaNavItem(Icons.people_outline_rounded, Icons.people_rounded, l.navMatches),
        OlfaNavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, l.navMessages),
        OlfaNavItem(Icons.person_outline_rounded, Icons.person_rounded, l.navProfile),
      ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final list = professional ? professionalItems(l) : items(l);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, c) {
        // Keep the bar comfortable on tablets instead of stretching edge to edge.
        final maxW = c.maxWidth > 600 ? 520.0 : double.infinity;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            OlfaSize.navBarMargin,
            0,
            OlfaSize.navBarMargin,
            bottom + 12,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Container(
                height: OlfaSize.navBarHeight,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: OlfaColors.white,
                  borderRadius: OlfaRadius.all(OlfaRadius.navBar),
                  border: Border.all(color: OlfaColors.gray),
                  boxShadow: [
                    BoxShadow(color: OlfaColors.black.withValues(alpha: 0.10), blurRadius: 30, offset: const Offset(0, 10)),
                  ],
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < list.length; i++)
                      Expanded(child: _NavButton(item: list[i], active: i == index, badge: badges.contains(i), onTap: () => onTap(i))),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.badge, required this.onTap});
  final OlfaNavItem item;
  final bool active;
  final bool badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? OlfaColors.primary : OlfaColors.textDisabled;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 54,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active ? OlfaColors.primaryTint() : Colors.transparent,
            borderRadius: OlfaRadius.all(17),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(active ? item.activeIcon : item.icon, size: 23, color: color),
                  if (badge)
                    PositionedDirectional(
                      top: -1,
                      end: -3,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: OlfaColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: OlfaColors.white, width: 2),
                        ),
                      ),
                    ),
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

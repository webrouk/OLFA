import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_logo.dart';
import '../../../core/widgets/olfa_widgets.dart';

/// Lightweight view model for a discovery card. Replaced by the API model
/// (freezed) when the discovery endpoint lands in Phase 3.
class DiscoverCardVm {
  const DiscoverCardVm({
    required this.id,
    required this.name,
    required this.age,
    required this.place,
    required this.bio,
    required this.interests,
    required this.compatibility,
    required this.photosReviewed,
  });
  final String id;
  final String name;
  final int age;
  final String place;
  final String bio;
  final List<String> interests;
  final int compatibility;
  final bool photosReviewed;
}

/// Clearly-labelled demo content for the UI phase only.
List<DiscoverCardVm> demoCards(bool ar) => [
      DiscoverCardVm(id: 'demo-1', name: ar ? 'سارة' : 'Sara', age: 27, place: ar ? 'دبي، الإمارات' : 'Dubai, UAE', bio: ar ? 'أحب التصميم والقراءة، وأبحث عن شريك حياة يقدّر الأسرة والطموح.' : 'I love design and reading. Looking for a partner who values family and ambition.', interests: ar ? ['القراءة', 'السفر', 'الطبخ'] : ['Reading', 'Travel', 'Cooking'], compatibility: 92, photosReviewed: true),
      DiscoverCardVm(id: 'demo-2', name: ar ? 'مريم' : 'Mariam', age: 29, place: ar ? 'الرياض، السعودية' : 'Riyadh, KSA', bio: ar ? 'هادئة ومحبة للطبيعة. أقدّر الصدق والوضوح.' : 'Calm and nature-loving. I value honesty and clarity.', interests: ar ? ['التطوع', 'الرياضة'] : ['Volunteering', 'Fitness'], compatibility: 86, photosReviewed: true),
      DiscoverCardVm(id: 'demo-3', name: ar ? 'نور' : 'Nour', age: 25, place: ar ? 'القاهرة، مصر' : 'Cairo, Egypt', bio: ar ? 'شغوفة بالتعلم واللغات.' : 'Passionate about learning and languages.', interests: ar ? ['التقنية', 'اللغات'] : ['Technology', 'Languages'], compatibility: 81, photosReviewed: false),
    ];

/// 12 — Discover / Home
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with SingleTickerProviderStateMixin {
  int _index = 0;
  final _history = <int>[];
  Offset _drag = Offset.zero;
  int _likesLeft = 7; // server-managed quota in Phase 3
  late final AnimationController _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  Future<void> _decide(bool like, double width) async {
    final start = _drag;
    final end = Offset((like ? 1 : -1) * width * 1.4, start.dy + 40);
    final anim = Tween(begin: start, end: end).animate(CurvedAnimation(parent: _fly, curve: Curves.easeIn));
    void l() => setState(() => _drag = anim.value);
    anim.addListener(l);
    await _fly.forward(from: 0);
    anim.removeListener(l);
    setState(() {
      _history.add(_index);
      _index++;
      _drag = Offset.zero;
      if (like) _likesLeft = math.max(0, _likesLeft - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final cards = demoCards(Localizations.localeOf(context).languageCode == 'ar');
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const OlfaLogo(size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.navDiscover, style: t.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(l.likesLeftToday(_likesLeft), style: t.caption),
                      ],
                    ),
                  ),
                  _SoftIcon(icon: Icons.notifications_none_rounded, onTap: () => context.push(Routes.notifications)),
                  const SizedBox(width: 8),
                  _SoftIcon(icon: Icons.tune_rounded, onTap: () => context.push(Routes.search)),
                ],
              ),
            ),
            Expanded(
              child: _index >= cards.length
                  ? OlfaEmptyState(
                      icon: Icons.explore_outlined,
                      title: l.noMoreTitle,
                      body: l.noMoreBody,
                      action: SizedBox(width: 200, child: OlfaButton(label: l.adjustFilters, onPressed: () => context.push(Routes.search))),
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        // Swipe right = like regardless of text direction (platform convention).
                        final dx = _drag.dx;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Stack(
                            children: [
                              if (_index + 1 < cards.length)
                                Positioned.fill(child: Transform.scale(scale: 0.95, child: _ProfileCard(vm: cards[_index + 1]))),
                              Positioned.fill(
                                child: GestureDetector(
                                  onPanUpdate: (d) => setState(() => _drag += d.delta),
                                  onPanEnd: (_) {
                                    if (dx.abs() > w * 0.28) {
                                      _decide(dx > 0, w);
                                    } else {
                                      setState(() => _drag = Offset.zero);
                                    }
                                  },
                                  child: Transform.translate(
                                    offset: Offset(dx, _drag.dy * 0.2),
                                    child: Transform.rotate(
                                      angle: dx / w * 0.35,
                                      child: _ProfileCard(
                                        vm: cards[_index],
                                        likeOpacity: (dx / 90).clamp(0, 1).toDouble(),
                                        passOpacity: (-dx / 90).clamp(0, 1).toDouble(),
                                        onOpen: () => context.push(Routes.profile(cards[_index].id)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (_index < cards.length)
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Builder(
                  builder: (context) {
                    final w = MediaQuery.sizeOf(context).width;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _RoundAction(size: 48, icon: Icons.undo_rounded, label: 'Undo', onTap: _history.isEmpty ? null : () => setState(() => _index = _history.removeLast())),
                        const SizedBox(width: 16),
                        _RoundAction(size: 64, icon: Icons.close_rounded, label: l.pass, onTap: () => _decide(false, w)),
                        const SizedBox(width: 16),
                        _RoundAction(size: 64, icon: Icons.favorite_rounded, label: l.like, filled: true, onTap: _likesLeft == 0 ? null : () => _decide(true, w)),
                        const SizedBox(width: 16),
                        _RoundAction(size: 48, icon: Icons.info_outline_rounded, label: 'Profile', onTap: () => context.push(Routes.profile(cards[_index].id))),
                      ],
                    );
                  },
                ),
              ),
            SizedBox(height: OlfaSize.navBarClearance(context)),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.vm, this.likeOpacity = 0, this.passOpacity = 0, this.onOpen});
  final DiscoverCardVm vm;
  final double likeOpacity;
  final double passOpacity;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: OlfaColors.white,
          borderRadius: OlfaRadius.all(OlfaRadius.profileCard),
          border: Border.all(color: OlfaColors.gray),
          boxShadow: [BoxShadow(color: OlfaColors.black.withValues(alpha: 0.08), blurRadius: 28, offset: const Offset(0, 8))],
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const PhotoPlaceholder(),
                  PositionedDirectional(
                    bottom: 12,
                    end: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: OlfaColors.white, borderRadius: OlfaRadius.all(12)),
                      child: Text(l.compatibility(vm.compatibility), style: t.caption.copyWith(color: OlfaColors.black, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  PositionedDirectional(top: 34, start: 20, child: _Stamp(text: l.like, color: OlfaColors.primary, opacity: likeOpacity, angle: -0.2)),
                  PositionedDirectional(top: 34, end: 20, child: _Stamp(text: l.pass, color: OlfaColors.black, opacity: passOpacity, angle: 0.2)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text('${vm.name}  ${vm.age}', style: t.h2, overflow: TextOverflow.ellipsis)),
                      if (vm.photosReviewed) ...[const SizedBox(width: 8), const VerifiedBadge(size: 22)],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(vm.place, style: t.caption),
                  const SizedBox(height: 8),
                  Text(vm.bio, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final i in vm.interests)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(border: Border.all(color: OlfaColors.gray, width: 1.5), borderRadius: OlfaRadius.all(15)),
                          child: Text(i, style: t.bodySmall),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.text, required this.color, required this.opacity, required this.angle});
  final String text;
  final Color color;
  final double opacity;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: OlfaColors.white, border: Border.all(color: color, width: 3), borderRadius: OlfaRadius.all(12)),
          child: Text(text, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _SoftIcon extends StatelessWidget {
  const _SoftIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: OlfaColors.gray,
        borderRadius: OlfaRadius.all(14),
        child: InkWell(
          borderRadius: OlfaRadius.all(14),
          onTap: onTap,
          child: SizedBox.square(dimension: 44, child: Icon(icon, size: 21)),
        ),
      );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.size, required this.icon, required this.label, required this.onTap, this.filled = false});
  final double size;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: Material(
          color: filled ? OlfaColors.primary : OlfaColors.white,
          shape: CircleBorder(side: filled ? BorderSide.none : const BorderSide(color: OlfaColors.gray)),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, size: size * 0.44, color: filled ? OlfaColors.white : OlfaColors.black),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/profile_card.dart';
import '../../matching/presentation/match_dialog.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../application/discover_controller.dart';
import '../domain/swipe_use_cases.dart';

/// 12 — Discover / Home
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> with SingleTickerProviderStateMixin {
  Offset _drag = Offset.zero;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Animation<Offset>? _flight;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final f = _flight;
      if (f != null) setState(() => _drag = f.value);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _animateTo(Offset target) async {
    _flight = Tween(begin: _drag, end: target).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.duration = motion(context, const Duration(milliseconds: 260));
    await _anim.forward(from: 0);
    _flight = null;
  }

  /// Swipe right = like, left = pass (platform convention, same in RTL).
  Future<void> _decide(SwipeKind kind) async {
    if (_animating) return; // double-submission guard (UI side)
    final ent = ref.read(entitlementsProvider).valueOrNull;
    if (kind == SwipeKind.like && ent != null && ent.likesLeft <= 0) {
      await _animateTo(Offset.zero);
      if (mounted) showToast(context, AppLocalizations.of(context).quotaLikes);
      return;
    }
    _animating = true;
    final w = MediaQuery.sizeOf(context).width;
    await _animateTo(Offset((kind == SwipeKind.like ? 1 : -1) * w * 1.3, _drag.dy + 30));
    await ref.read(discoverControllerProvider.notifier).swipe(kind);
    if (mounted) setState(() => _drag = Offset.zero);
    _animating = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final state = ref.watch(discoverControllerProvider);
    final ent = ref.watch(entitlementsProvider).valueOrNull;

    ref.listen(discoverControllerProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      if (s.lastFailure != null) {
        showToast(context, failureMessage(context, s.lastFailure!));
        ref.read(discoverControllerProvider.notifier).clearEvents();
      }
      if (s.lastMatch != null) {
        final m = s.lastMatch!;
        ref.read(discoverControllerProvider.notifier).clearEvents();
        showMatchDialog(context, ref, m);
      }
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ContentWidth(
          max: 520,
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
                          if (ent != null)
                            Text(
                              ent.resetsAt == null
                                  ? l.likesLeftToday(ent.likesLeft)
                                  : '${l.likesLeftToday(ent.likesLeft)} · ${l.quotaResetsAt(MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(ent.resetsAt!)))}',
                              style: t.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    OlfaIconButton(icon: Icons.notifications_none_rounded, tooltip: l.screenNotifications, style: OlfaIconStyle.soft, onPressed: () => context.push(Routes.notifications)),
                    const SizedBox(width: 8),
                    OlfaIconButton(icon: Icons.tune_rounded, tooltip: l.screenSearch, style: OlfaIconStyle.soft, onPressed: () => context.push(Routes.search)),
                  ],
                ),
              ),
              Expanded(
                child: state.when(
                  skipLoadingOnReload: true,
                  loading: () => const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: OlfaSkeleton(height: double.infinity, radius: OlfaRadius.profileCard)),
                  error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(discoverControllerProvider)),
                  data: (s) {
                    final cur = s.current;
                    if (cur == null) {
                      return EmptyState(
                        icon: Icons.explore_outlined,
                        title: l.noMoreTitle,
                        body: l.noMoreBody,
                        action: PrimaryButton(label: l.adjustFilters, expand: false, onPressed: () => context.push(Routes.search)),
                      );
                    }
                    return LayoutBuilder(
                      builder: (context, c) {
                        final dx = _drag.dx;
                        final w = c.maxWidth;
                        final progress = (dx.abs() / (w * 0.3)).clamp(0.0, 1.0).toDouble();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Stack(
                            children: [
                              if (s.next != null)
                                Positioned.fill(
                                  child: Transform.scale(
                                    scale: 0.95 + 0.05 * progress,
                                    child: ExcludeSemantics(child: ProfileCard(key: ValueKey('next-${s.next!.id}'), profile: s.next!)),
                                  ),
                                ),
                              Positioned.fill(
                                child: GestureDetector(
                                  onPanUpdate: _animating ? null : (d) => setState(() => _drag += d.delta),
                                  onPanEnd: _animating
                                      ? null
                                      : (d) {
                                          final fling = d.velocity.pixelsPerSecond.dx;
                                          if (dx.abs() > w * 0.28 || fling.abs() > 900) {
                                            _decide((dx + fling / 10) > 0 ? SwipeKind.like : SwipeKind.pass);
                                          } else {
                                            _animateTo(Offset.zero);
                                          }
                                        },
                                  child: Transform.translate(
                                    offset: Offset(dx, _drag.dy * 0.15),
                                    child: Transform.rotate(
                                      angle: reduceMotion(context) ? 0 : dx / w * 0.3,
                                      child: ProfileCard(
                                        key: ValueKey(cur.id),
                                        profile: cur,
                                        likeOpacity: dx / 90,
                                        passOpacity: -dx / 90,
                                        onOpen: () => context.push(Routes.profile(cur.id)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (state.valueOrNull?.current != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OlfaIconButton(
                        icon: Icons.undo_rounded,
                        tooltip: l.undo,
                        style: OlfaIconStyle.elevated,
                        circle: true,
                        size: 48,
                        onPressed: (state.valueOrNull?.history.isEmpty ?? true)
                            ? null
                            : () {
                                if ((ent?.undosLeft ?? 0) <= 0) {
                                  showToast(context, l.quotaUndos);
                                  return;
                                }
                                ref.read(discoverControllerProvider.notifier).undo();
                              },
                      ),
                      const SizedBox(width: 16),
                      OlfaIconButton(icon: Icons.close_rounded, tooltip: l.pass, style: OlfaIconStyle.elevated, circle: true, size: 64, onPressed: () => _decide(SwipeKind.pass)),
                      const SizedBox(width: 16),
                      OlfaIconButton(icon: Icons.favorite_rounded, tooltip: l.like, style: OlfaIconStyle.filled, circle: true, size: 64, onPressed: () => _decide(SwipeKind.like)),
                      const SizedBox(width: 16),
                      OlfaIconButton(
                        icon: Icons.info_outline_rounded,
                        tooltip: l.viewProfile,
                        style: OlfaIconStyle.elevated,
                        circle: true,
                        size: 48,
                        onPressed: () => context.push(Routes.profile(state.valueOrNull!.current!.id)),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: OlfaSize.navBarClearance(context)),
            ],
          ),
        ),
      ),
    );
  }
}

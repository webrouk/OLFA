import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/profile_card.dart';
import '../../ads/application/discovery_ads_controller.dart';
import '../../ads/presentation/discovery_ad_card.dart';
import '../../matching/presentation/match_dialog.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../application/discover_controller.dart';
import '../domain/swipe_use_cases.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../shared/models/models.dart';
import '../../../core/routing/navigation.dart';

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
  /// Accounts under review browse only (the server refuses likes and profiles too).
  bool _blockedWhilePending() {
    final ent = ref.read(entitlementsProvider).valueOrNull;
    if (ent == null || ent.accountActive) return false;
    showToast(context, AppLocalizations.of(context).pendingReadOnly);
    return true;
  }

  void _open(UserProfile p) {
    if (_blockedWhilePending()) return;
    context.pushOnce(Routes.profile(p.id), extra: p);
  }

  Future<void> _compliment(UserProfile p) async {
    if (_blockedWhilePending()) return;
    final text = await showComplimentSheet(context, ref, p);
    if (text == null || !mounted) return;
    if (_animating) return;
    _animating = true;
    final w = MediaQuery.sizeOf(context).width;
    await _animateTo(Offset(w * 1.3, _drag.dy + 30));
    await _swipeAndCount(SwipeKind.like, compliment: text);
    if (mounted) setState(() => _drag = Offset.zero);
    _animating = false;
  }

  Future<void> _decide(SwipeKind kind) async {
    if (_animating) return; // double-submission guard (UI side)
    if (kind == SwipeKind.like && _blockedWhilePending()) {
      await _animateTo(Offset.zero);
      return;
    }
    final ent = ref.read(entitlementsProvider).valueOrNull;
    if (kind == SwipeKind.like && ent != null && ent.likesLeft <= 0) {
      await _animateTo(Offset.zero);
      if (mounted) showToast(context, AppLocalizations.of(context).quotaLikes);
      return;
    }
    _animating = true;
    final w = MediaQuery.sizeOf(context).width;
    await _animateTo(Offset((kind == SwipeKind.like ? 1 : -1) * w * 1.3, _drag.dy + 30));
    await _swipeAndCount(kind);
    if (mounted) setState(() => _drag = Offset.zero);
    _animating = false;
  }

  final _prefetched = <String>{};

  /// Downloads the next cards' photos while the member looks at this one, so
  /// the next card appears with its photo, not a placeholder.
  void _prefetch(List<UserProfile> queue) {
    for (final p in queue.skip(1).take(3)) {
      final url = p.mainPhoto?.cardUrl;
      if (url == null || !_prefetched.add(url)) continue;
      precacheImage(CachedNetworkImageProvider(url), context).ignore();
    }
    if (_prefetched.length > 200) _prefetched.clear();
  }

  /// Swipes, and counts the profile towards the next ad slot only if the swipe went through.
  Future<void> _swipeAndCount(SwipeKind kind, {String? compliment}) async {
    final before = ref.read(discoverControllerProvider).valueOrNull?.current?.id;
    await ref.read(discoverControllerProvider.notifier).swipe(kind, compliment: compliment);
    if (!mounted) return;
    final after = ref.read(discoverControllerProvider).valueOrNull?.current?.id;
    if (before != null && after != before) ref.read(discoveryAdsProvider.notifier).onProfileDecided();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final state = ref.watch(discoverControllerProvider);
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    // Free plan only: a native ad card takes the place of the next profile now and then.
    final ads = ref.watch(discoveryAdsProvider);
    final adOnScreen = ads.showing && ads.ad != null && state.valueOrNull?.current != null;

    ref.listen(discoverControllerProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      _prefetch(s.queue);
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
                    Consumer(builder: (context, ref, _) {
                      final n = ref.watch(filtersProvider.select((f) => f.activeCount));
                      return Stack(clipBehavior: Clip.none, children: [
                        OlfaIconButton(icon: Icons.tune_rounded, tooltip: n == 0 ? l.screenSearch : '${l.screenSearch} · ${l.filtersCount(n)}', style: OlfaIconStyle.soft, onPressed: () => context.pushOnce(Routes.search)),
                        if (n > 0) PositionedDirectional(top: -4, end: -4, child: CountBadge(count: n)),
                      ]);
                    }),
                  ],
                ),
              ),
              if (ent != null && !ent.accountActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: InfoBanner(accent: true, icon: Icons.hourglass_top_rounded, text: l.pendingDiscoverBanner),
                ),
              Expanded(
                child: state.when(
                  skipLoadingOnReload: true,
                  loading: () => const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: OlfaSkeleton(height: double.infinity, radius: OlfaRadius.profileCard)),
                  error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(discoverControllerProvider)),
                  data: (s) {
                    final cur = s.current;
                    if (cur == null && s.fetchingMore) {
                      return const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: OlfaSkeleton(height: double.infinity, radius: OlfaRadius.profileCard));
                    }
                    if (cur == null) {
                      return EmptyState(
                        icon: Icons.explore_outlined,
                        title: l.noMoreTitle,
                        body: l.noMoreBody,
                        action: PrimaryButton(label: l.adjustFilters, expand: false, onPressed: () => context.push(Routes.search)),
                      );
                    }
                    if (adOnScreen) {
                      // The ad card has no swipe: its touches belong to the ad only.
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ExcludeSemantics(
                                  child: Transform.scale(scale: 0.95, child: ProfileCard(key: ValueKey('next-${cur.id}'), profile: cur)),
                                ),
                              ),
                            ),
                            Positioned.fill(child: DiscoveryAdCard(key: ObjectKey(ads.ad), ad: ads.ad!)),
                          ],
                        ),
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
                                        onOpen: () => _open(cur),
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
              if (adOnScreen)
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: SizedBox(
                    height: 64,
                    child: Center(
                      child: PrimaryButton(
                        label: l.adContinue,
                        icon: Icons.arrow_forward_rounded,
                        expand: false,
                        onPressed: () => ref.read(discoveryAdsProvider.notifier).dismiss(),
                      ),
                    ),
                  ),
                )
              else if (state.valueOrNull?.current != null)
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
                      // Compliment: a short message that arrives with the like and is shown first.
                      _ComplimentButton(left: ent?.complimentsLeft, onPressed: () => _compliment(state.valueOrNull!.current!)),
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

class _ComplimentButton extends StatelessWidget {
  const _ComplimentButton({required this.left, required this.onPressed});
  final int? left;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Stack(clipBehavior: Clip.none, children: [
      OlfaIconButton(icon: Icons.auto_awesome_rounded, tooltip: l.sendCompliment, style: OlfaIconStyle.elevated, circle: true, size: 48, onPressed: onPressed),
      if (left != null)
        PositionedDirectional(
          top: -4,
          end: -4,
          child: CountBadge(count: left!, inverted: left! == 0),
        ),
    ]);
  }
}

/// Compose a compliment (2–300 characters, no contact details). Returns the text.
Future<String?> showComplimentSheet(BuildContext context, WidgetRef ref, UserProfile p) {
  final l = AppLocalizations.of(context);
  final ent = ref.read(entitlementsProvider).valueOrNull;
  final ctrl = TextEditingController();
  final contact = RegExp(r'(\+?\d[\d\s-]{7,})|@|https?://|www\.', caseSensitive: false);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
      final text = ctrl.text.trim();
      final err = contact.hasMatch(text) ? l.complimentNoContact : null;
      final left = ent?.complimentsLeft ?? 0;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.auto_awesome_rounded, color: OlfaColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l.complimentTitle(p.name), style: sheet.type.h3)),
          ]),
          const SizedBox(height: 10),
          Text(l.complimentBody, style: sheet.type.bodySmall.copyWith(color: OlfaColors.textMuted)),
          const SizedBox(height: 14),
          OlfaTextField(label: l.yourCompliment, hint: l.complimentHint, controller: ctrl, maxLines: 3, maxLength: 300, counter: true, error: err, onChanged: (_) => set(() {})),
          Text(
            ent == null ? '' : l.complimentsLeftMonth(left, ent.monthlyCompliments),
            style: sheet.type.caption.copyWith(color: left == 0 ? OlfaColors.primary : null),
          ),
          const SizedBox(height: 12),
          if (left == 0)
            PrimaryButton(label: l.upgradeForCompliments, icon: Icons.workspace_premium_outlined, onPressed: () {
              Navigator.of(sheet).pop();
              context.push(Routes.plans);
            })
          else
            PrimaryButton(label: l.sendWithLike, icon: Icons.favorite_rounded, onPressed: text.length < 2 || err != null ? null : () => Navigator.of(sheet).pop(text)),
        ]),
      );
    }),
  ).whenComplete(ctrl.dispose);
}

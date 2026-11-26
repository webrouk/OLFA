import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/bidi_text.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/components/verification_ticks.dart';
import '../../../shared/models/models.dart';
import '../../discovery/data/discovery_repository_impl.dart';
import '../../matching/data/matching_repository_impl.dart';
import '../../matching/presentation/match_dialog.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../../../core/routing/navigation.dart';

enum _LikesFilter { all, compliments, nearby, verified }

/// 15 — Likes received. Compliments always arrive with the sender and come
/// first; other likes show identities only on Plus/Premium (Free receives
/// the count from the server, no identities). Like back or pass in place.
class LikesScreen extends ConsumerStatefulWidget {
  const LikesScreen({super.key});
  @override
  ConsumerState<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends ConsumerState<LikesScreen> {
  _LikesFilter _filter = _LikesFilter.all;
  final _done = <String>{}; // acted on in this session (hidden optimistically)
  String? _busy;

  Future<void> _act(UserProfile p, {required bool like}) async {
    if (_busy != null) return;
    setState(() => _busy = p.id);
    final repo = ref.read(discoveryRepositoryProvider);
    try {
      if (like) {
        final m = await repo.like(p.id);
        ref.invalidate(matchesProvider);
        if (m != null && mounted) showMatchDialog(context, ref, m);
      } else {
        await repo.pass(p.id);
      }
      setState(() => _done.add(p.id));
      // the Likes badge and count follow the server (the card is already hidden)
      ref.invalidate(likesReceivedProvider);
      ref.read(entitlementsProvider.notifier).refresh();
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenLikes), automaticallyImplyLeading: false),
      body: AsyncView<LikesInbox>(
        value: ref.watch(likesReceivedProvider),
        onRetry: () => ref.invalidate(likesReceivedProvider),
        loading: const _GridSkeleton(),
        data: (data) {
          if (data.count == 0 && data.compliments.isEmpty) {
            return EmptyState(icon: Icons.favorite_border_rounded, title: l.noLikesTitle, body: l.noLikesBody, action: PrimaryButton(label: l.navDiscover, expand: false, onPressed: () => context.go(Routes.discover)));
          }
          final compliments = data.compliments.where((x) => !_done.contains(x.profile.id)).toList();
          var items = data.items.where((x) => !_done.contains(x.profile.id)).toList();
          items = switch (_filter) {
            _LikesFilter.all => items,
            _LikesFilter.compliments => const [],
            _LikesFilter.nearby => (items.where((x) => x.profile.distanceKm != null).toList()..sort((a, b) => a.profile.distanceKm!.compareTo(b.profile.distanceKm!))),
            _LikesFilter.verified => items.where((x) => x.profile.verificationLevel != VerificationLevel.none).toList(),
          };
          return RefreshIndicator(
            color: OlfaColors.primary,
            onRefresh: () async {
              _done.clear();
              await ref.refresh(likesReceivedProvider.future);
            },
            child: CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                sliver: SliverList.list(children: [
                  _Summary(count: data.count, compliments: data.compliments.length),
                  const SizedBox(height: 12),
                  if (!data.locked)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final f in _LikesFilter.values)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: OlfaChoice(
                              small: true,
                              label: switch (f) { _LikesFilter.all => l.all, _LikesFilter.compliments => l.complimentsTab, _LikesFilter.nearby => l.scopeNearby, _LikesFilter.verified => l.verifiedOnly },
                              selected: _filter == f,
                              onTap: () => setState(() => _filter = f),
                            ),
                          ),
                      ]),
                    ),
                  if (compliments.isNotEmpty && (_filter == _LikesFilter.all || _filter == _LikesFilter.compliments)) ...[
                    SectionLabel(l.complimentsTab, top: 16),
                    for (final c in compliments) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ComplimentCard(like: c, busy: _busy == c.profile.id, onLike: () => _act(c.profile, like: true), onPass: () => _act(c.profile, like: false))),
                  ],
                  if (data.locked) ...[
                    const SizedBox(height: 14),
                    _Upsell(count: data.count),
                  ] else if (items.isNotEmpty)
                    SectionLabel(l.likedYou, top: 16)
                  // a filter with no result says so (instead of an empty page)
                  else if (_filter != _LikesFilter.all && !(_filter == _LikesFilter.compliments && compliments.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Column(children: [
                        Icon(Icons.filter_alt_off_outlined, color: OlfaColors.textMuted, size: 32),
                        const SizedBox(height: 8),
                        Text(l.noResults, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
                        TextButton(onPressed: () => setState(() => _filter = _LikesFilter.all), child: Text(l.all)),
                      ]),
                    ),
                ]),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, OlfaSize.navBarClearance(context)),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.66),
                  itemCount: data.locked ? 6 : items.length,
                  itemBuilder: (context, i) => data.locked
                      ? const _LockedTile()
                      : _LikeTile(like: items[i], busy: _busy == items[i].profile.id, onLike: () => _act(items[i].profile, like: true), onPass: () => _act(items[i].profile, like: false)),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.compliments});
  final int count, compliments;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return OlfaCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: OlfaColors.primary, borderRadius: OlfaRadius.all(14)), child: const Icon(Icons.favorite_rounded, color: OlfaColors.white)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.likesCount(count), style: t.h3),
            if (compliments > 0) Text(l.complimentsCount(compliments), style: t.caption.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

class _ComplimentCard extends StatelessWidget {
  const _ComplimentCard({required this.like, required this.busy, required this.onLike, required this.onPass});
  final ReceivedLike like;
  final bool busy;
  final VoidCallback onLike, onPass;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final p = like.profile;
    return OlfaCard(
      borderColor: OlfaColors.primary,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => context.pushOnce(Routes.profile(p.id), extra: p),
          child: Row(children: [
            OlfaAvatar(size: 52, url: p.mainPhoto?.thumbUrl, online: p.online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Text(nameAge(context, p.name, p.age), style: t.h3, overflow: TextOverflow.ellipsis)), const SizedBox(width: 6), VerificationMark(profile: p, size: 16)]),
                Text([if (p.showLocation) p.city, if (p.distanceKm != null) l.kmAway(p.distanceKm!), shortTime(context, like.at)].join(' · '), style: t.caption),
              ]),
            ),
            const OlfaTag('✦', style: OlfaTagStyle.accent),
          ]),
        ),
        const SizedBox(height: 12),
        // the compliment, shown like a highlighted message
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: const BorderRadiusDirectional.only(topStart: Radius.circular(6), topEnd: Radius.circular(18), bottomStart: Radius.circular(18), bottomEnd: Radius.circular(18))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.auto_awesome_rounded, size: 18, color: OlfaColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(like.compliment ?? '', style: t.bodyMedium)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: SecondaryButton(label: l.pass, onPressed: busy ? null : onPass)),
          const SizedBox(width: 10),
          Expanded(child: PrimaryButton(label: l.likeBack, icon: Icons.favorite_rounded, loading: busy, onPressed: busy ? null : onLike)),
        ]),
      ]),
    );
  }
}

class _LikeTile extends StatelessWidget {
  const _LikeTile({required this.like, required this.busy, required this.onLike, required this.onPass});
  final ReceivedLike like;
  final bool busy;
  final VoidCallback onLike, onPass;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final p = like.profile;
    return ClipRRect(
      borderRadius: OlfaRadius.all(20),
      child: Container(
        decoration: BoxDecoration(color: OlfaColors.white, border: Border.all(color: OlfaColors.gray), borderRadius: OlfaRadius.all(20)),
        child: Column(children: [
          Expanded(
            child: InkWell(
              onTap: () => context.pushOnce(Routes.profile(p.id), extra: p),
              child: Stack(fit: StackFit.expand, children: [
                OlfaImage(url: p.mainPhoto?.cardUrl ?? p.mainPhoto?.thumbUrl, blur: p.photosBlurred),
                if (p.distanceKm != null) PositionedDirectional(top: 8, start: 8, child: OlfaTag(l.kmAway(p.distanceKm!), style: OlfaTagStyle.onImage, icon: Icons.near_me_outlined)),
                if (p.online) const PositionedDirectional(top: 10, end: 10, child: _OnlineDot()),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(children: [
              Expanded(child: Text(nameAge(context, p.name, p.age), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              VerificationMark(profile: p, size: 15),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              OlfaIconButton(icon: Icons.close_rounded, tooltip: l.pass, style: OlfaIconStyle.soft, circle: true, size: 40, onPressed: busy ? null : onPass),
              OlfaIconButton(icon: Icons.favorite_rounded, tooltip: l.likeBack, style: OlfaIconStyle.filled, circle: true, size: 40, onPressed: busy ? null : onLike),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();
  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle, border: Border.all(color: OlfaColors.white, width: 2)),
      );
}

class _Upsell extends StatelessWidget {
  const _Upsell({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return OlfaCard(
      color: OlfaColors.black,
      borderColor: OlfaColors.black,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: OlfaColors.primary, borderRadius: OlfaRadius.all(16)), child: const Icon(Icons.visibility_outlined, color: OlfaColors.white)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l.seeWhoLikes, style: t.h3.copyWith(color: OlfaColors.white)), Text(l.seeWhoLikesBody, style: t.caption.copyWith(color: OlfaColors.white.withValues(alpha: 0.75)))])),
        ]),
        const SizedBox(height: 14),
        PrimaryButton(label: l.upgrade, onPressed: () => context.push(Routes.plans)),
      ]),
    );
  }
}

class _LockedTile extends StatelessWidget {
  const _LockedTile();
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l.seeWhoLikes,
      child: InkWell(
        borderRadius: OlfaRadius.all(20),
        onTap: () => context.push(Routes.plans),
        child: ClipRRect(
          borderRadius: OlfaRadius.all(20),
          child: Stack(fit: StackFit.expand, children: [
            const OlfaImage(url: null, blur: true),
            Center(
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.lock_outline_rounded, color: OlfaColors.white),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();
  @override
  Widget build(BuildContext context) => GridView.count(
        padding: const EdgeInsets.all(20),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66,
        children: List.generate(6, (_) => const OlfaSkeleton(height: double.infinity, radius: 20)),
      );
}

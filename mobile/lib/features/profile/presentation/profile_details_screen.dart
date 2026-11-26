import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/bidi_text.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../settings/presentation/report_sheet.dart';
import '../../../shared/models/models.dart';
import '../../discovery/application/discover_controller.dart';
import '../../discovery/domain/swipe_use_cases.dart';
import '../application/profile_controllers.dart';
import '../../discovery/data/discovery_repository_impl.dart';
import '../../matching/data/matching_repository_impl.dart';
import '../../matching/presentation/match_actions.dart';
import '../../matching/presentation/match_dialog.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../../../shared/components/reference_pickers.dart';
import '../../../shared/components/verification_ticks.dart';

/// 13 — Profile details with a paginated, lazily loaded photo gallery.
///
/// Opens instantly: the card the member tapped ([initial], already on screen
/// with its photos cached) is shown at once and replaced in place by the full
/// profile when it arrives — no spinner, no second page.
class ProfileDetailsScreen extends ConsumerWidget {
  const ProfileDetailsScreen({super.key, required this.userId, this.initial});
  final String userId;
  final UserProfile? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // My own profile ("see it as others do"): from my profile, never the public endpoint.
    final me = ref.watch(myProfileProvider).valueOrNull;
    if (me != null && me.id == userId) {
      return Scaffold(body: _Details(key: ValueKey(userId), profile: me, complete: true, own: true));
    }
    final value = ref.watch(profileByIdProvider(userId));
    final seed = initial != null && initial!.id == userId ? initial : null;
    final full = value.valueOrNull;
    final shown = full ?? (value.hasError ? null : seed);
    return Scaffold(
      body: shown != null
          ? _Details(key: ValueKey(userId), profile: shown, complete: full != null)
          : AsyncView<UserProfile>(
              value: value,
              onRetry: () => ref.invalidate(profileByIdProvider(userId)),
              data: (p) => _Details(key: ValueKey(userId), profile: p, complete: true),
            ),
    );
  }
}

class _Details extends ConsumerStatefulWidget {
  const _Details({super.key, required this.profile, required this.complete, this.own = false});
  final UserProfile profile;

  /// False while only the tapped card's data is known: the photo, name and age
  /// show at once; the other sections show placeholders (never half-filled data).
  final bool complete;

  /// Viewing my own profile: no actions, no report.
  final bool own;
  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  final _pager = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  bool _busy = false;

  Future<void> _act(SwipeKind kind) async {
    final ctrl = ref.read(discoverControllerProvider.notifier);
    final s = ref.read(discoverControllerProvider).valueOrNull;
    // Only act if this profile is the visible discovery card; otherwise just go back.
    if (s?.current?.id == widget.profile.id) await ctrl.swipe(kind);
    if (mounted) context.pop();
  }

  /// Answer a like received (from the Likes tab).
  Future<void> _answerLike({required bool like}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(discoveryRepositoryProvider);
    try {
      final m = like ? await repo.like(widget.profile.id) : null;
      if (!like) await repo.pass(widget.profile.id);
      ref
        ..invalidate(likesReceivedProvider)
        ..invalidate(matchesProvider);
      ref.read(entitlementsProvider.notifier).refresh();
      if (!mounted) return;
      if (m != null) await showMatchDialog(context, ref, m); // may open the chat
      // Leave the profile unless the dialog already took the member to the chat.
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) context.pop();
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chat(MatchItem m) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await openMatchChat(context, ref, m);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The right actions for where the member came from.
  Widget? _actions(AppLocalizations l) {
    if (widget.own) return null;
    final id = widget.profile.id;
    if (ref.watch(discoverControllerProvider.select((s) => s.valueOrNull?.current?.id)) == id) {
      return Row(children: [
        Expanded(child: SecondaryButton(label: l.pass, icon: Icons.close_rounded, onPressed: () => _act(SwipeKind.pass))),
        const SizedBox(width: 12),
        Expanded(child: PrimaryButton(label: l.like, icon: Icons.favorite_rounded, onPressed: () => _act(SwipeKind.like))),
      ]);
    }
    final match = ref.watch(matchesProvider.select((v) => v.valueOrNull?.where((m) => m.peer.id == id).firstOrNull));
    if (match != null) {
      return PrimaryButton(
        label: match.conversationId != null ? l.openChat : l.startConversation,
        icon: Icons.chat_bubble_outline_rounded,
        loading: _busy,
        onPressed: () => _chat(match),
      );
    }
    final likedMe = ref.watch(likesReceivedProvider.select((v) => v.valueOrNull == null ? false : [...v.valueOrNull!.items, ...v.valueOrNull!.compliments].any((x) => x.profile.id == id)));
    if (likedMe) {
      return Row(children: [
        Expanded(child: SecondaryButton(label: l.pass, icon: Icons.close_rounded, onPressed: _busy ? null : () => _answerLike(like: false))),
        const SizedBox(width: 12),
        Expanded(child: PrimaryButton(label: l.likeBack, icon: Icons.favorite_rounded, loading: _busy, onPressed: () => _answerLike(like: true))),
      ]);
    }
    return null;
  }

  // Section jump bar: Photos · About · Basics · Background · Marriage · Interests · Trust
  final _keys = {for (final k in _Section.values) k: GlobalKey()};
  _Section _current = _Section.photos;

  void _jump(_Section s) {
    setState(() => _current = s);
    final ctx = _keys[s]!.currentContext;
    // land just under the pinned jump bar (status bar + 52 px)
    final under = ((MediaQuery.paddingOf(context).top + 60) / MediaQuery.sizeOf(context).height).clamp(0.0, 0.4).toDouble();
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: motion(context, const Duration(milliseconds: 280)), curve: Curves.easeOut, alignmentPolicy: ScrollPositionAlignmentPolicy.explicit, alignment: s == _Section.photos ? 0 : under);
  }

  void _photo(int delta) {
    final n = widget.profile.photos.length;
    if (n < 2) return;
    final next = (_page + delta).clamp(0, n - 1).toInt();
    if (next != _page) _pager.animateToPage(next, duration: motion(context, const Duration(milliseconds: 220)), curve: Curves.easeOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheAround(0);
  }

  /// The next photos are fetched before they are swiped to (no blank frame).
  void _precacheAround(int i) {
    final photos = widget.profile.photos;
    for (final j in [i + 1, i + 2]) {
      final u = j < photos.length ? photos[j].fullUrl : null;
      if (u != null) precacheImage(CachedNetworkImageProvider(u), context).ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final p = widget.profile;
    final top = MediaQuery.paddingOf(context).top;
    final photos = p.photos;
    final actions = _actions(l);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final lang = langOf(context);
    final sections = <_Section, String>{
      _Section.photos: l.profileSectionPhotos,
      _Section.about: l.profileSectionAbout,
      _Section.basics: l.profileSectionBasics,
      _Section.background: l.profileSectionBackground,
      _Section.marriage: l.profileSectionMarriage,
      if (p.interests.isNotEmpty) _Section.interests: l.profileSectionInterests,
      _Section.trust: l.profileSectionTrust,
    };

    Widget card(_Section s, List<Widget> children) => Padding(
          key: _keys[s],
          padding: const EdgeInsets.only(top: 14),
          child: OlfaCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sections[s]!, style: t.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ...children,
            ]),
          ),
        );

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: AspectRatio(
                  key: _keys[_Section.photos],
                  aspectRatio: 4 / 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // PageView builds pages lazily; each uses the full-size
                      // variant only here, and the cache keeps it for re-entry.
                      PageView.builder(
                        controller: _pager,
                        itemCount: photos.isEmpty ? 1 : photos.length,
                        onPageChanged: (i) {
                          setState(() => _page = i);
                          _precacheAround(i);
                        },
                        // The card-size photo (already cached from Discovery) shows until the full one loads.
                        itemBuilder: (_, i) => OlfaImage(url: photos.isEmpty ? null : photos[i].fullUrl, placeholderUrl: photos.isEmpty ? null : photos[i].cardUrl),
                      ),
                      // tap the sides to move between photos (like swiping)
                      if (photos.length > 1)
                        Row(children: [
                          Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _photo(rtl ? 1 : -1))),
                          Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _photo(rtl ? -1 : 1))),
                        ]),
                      PositionedDirectional(
                        top: top + 6,
                        start: 12,
                        end: 12,
                        child: Row(
                          children: [
                            OlfaIconButton(icon: Icons.arrow_back_rounded, tooltip: MaterialLocalizations.of(context).backButtonTooltip, style: OlfaIconStyle.elevated, onPressed: () => context.pop()),
                            const Spacer(),
                            if (!widget.own) OlfaIconButton(icon: Icons.more_horiz_rounded, tooltip: l.reportOrBlock, style: OlfaIconStyle.elevated, onPressed: () => showReportSheet(context, ref, p)),
                          ],
                        ),
                      ),
                      if (photos.length > 1) ...[
                        PositionedDirectional(
                          bottom: 14,
                          start: 16,
                          end: 16,
                          child: Row(
                            children: [
                              for (var i = 0; i < photos.length; i++)
                                Expanded(
                                  child: Container(
                                    height: 3,
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    decoration: BoxDecoration(color: OlfaColors.white.withValues(alpha: i == _page ? 1 : 0.55), borderRadius: OlfaRadius.all(2)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        PositionedDirectional(
                          bottom: 26,
                          end: 16,
                          child: Semantics(
                            label: l.photoOf(_page + 1, photos.length),
                            excludeSemantics: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: OlfaColors.black.withValues(alpha: 0.55), borderRadius: OlfaRadius.all(10)),
                              child: Text('${_page + 1}/${photos.length}', textDirection: TextDirection.ltr, style: const TextStyle(color: OlfaColors.white, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Montserrat')),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // header: who, where, how compatible
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(nameAge(context, p.name, p.age), style: t.h1)),
                      const SizedBox(width: 8),
                      VerificationMark(profile: p, size: 22),
                    ]),
                    const SizedBox(height: 4),
                    Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (p.showLocation)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.place_outlined, size: 16, color: OlfaColors.textMuted),
                          const SizedBox(width: 4),
                          Text('${p.city} · ${countryLabel(context, p.countryIso)}', style: t.caption),
                          if (p.distanceKm != null) Text(' · ${l.kmAway(p.distanceKm!)}', style: t.caption),
                        ]),
                      if (p.online && !widget.own)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(l.onlineNow, style: t.caption),
                        ]),
                    ]),
                    if (widget.complete) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (!widget.own && p.compatibility > 0) OlfaTag(l.compatibility(p.compatibility), style: OlfaTagStyle.accent, icon: Icons.people_alt_outlined),
                        OlfaTag(l.timelineLabel(p.timeline), icon: Icons.event_outlined),
                      ]),
                      if (p.managedBy != null) ...[
                        const SizedBox(height: 12),
                        InfoBanner(icon: Icons.family_restroom_rounded, text: '${l.managedBy(relationLabel(l, p.managedBy!))}. ${l.managedByBody}'),
                      ],
                    ],
                  ]),
                ),
              ),
              if (widget.complete)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _JumpBar(
                    top: top,
                    items: sections,
                    current: _current,
                    onTap: _jump,
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverList.list(
                  children: [
                    if (!widget.complete) ...const [
                      SizedBox(height: 18),
                      OlfaSkeleton(width: 200, height: 26, radius: 13),
                      SizedBox(height: 26),
                      OlfaSkeleton(width: 90),
                      SizedBox(height: 12),
                      OlfaSkeleton(height: 12),
                      SizedBox(height: 8),
                      OlfaSkeleton(height: 12),
                      SizedBox(height: 8),
                      OlfaSkeleton(width: 220, height: 12),
                      SizedBox(height: 26),
                      OlfaSkeleton(height: 120, radius: 14),
                    ] else ...[
                      card(_Section.about, [Text(p.bio.isEmpty ? '—' : p.bio, style: t.bodyMedium)]),
                      card(_Section.basics, [
                        _KeyValueGrid(items: [
                          (l.maritalStatus, l.maritalLabel(p.maritalStatus)),
                          if (p.showLocation) (l.city, p.city),
                          if (p.nationality != null) (l.nationality, nationalityByIso(p.nationality)?.label(lang, female: p.gender == Gender.female) ?? p.nationality!),
                          if (p.heightCm != null) (l.height, '${p.heightCm} ${l.cm}'),
                          if (p.weightKg != null) (l.weight, '${p.weightKg} ${l.kg}'),
                        ]),
                      ]),
                      card(_Section.background, [
                        _KeyValueGrid(items: [
                          (l.education, l.educationLabel(p.education)),
                          (l.occupation, occupationLabel(context, p.occupation)),
                          if (p.religion != null) (l.religion, religionLabel(context, p.religion)),
                          if (p.sect != null && sectLabel(context, p.religion, p.sect).isNotEmpty) (l.sect, sectLabel(context, p.religion, p.sect)),
                        ]),
                      ]),
                      card(_Section.marriage, [
                        _KeyValueGrid(items: [
                          (l.marriageTimeline, l.timelineLabel(p.timeline)),
                          (l.maritalStatus, l.maritalLabel(p.maritalStatus)),
                        ]),
                        if (!widget.own && p.compatibility > 0) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: OlfaRadius.all(4),
                                child: LinearProgressIndicator(value: p.compatibility / 100, minHeight: 6, color: OlfaColors.primary, backgroundColor: OlfaColors.gray),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(l.compatibility(p.compatibility), style: t.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                          ]),
                        ],
                      ]),
                      if (p.interests.isNotEmpty)
                        card(_Section.interests, [
                          Wrap(spacing: 8, runSpacing: 8, children: [for (final k in p.interests) OlfaTag(interestLabel(context, k))]),
                        ]),
                      card(_Section.trust, [
                        TileGroup(children: [
                          _VerifRow(icon: Icons.face_retouching_natural_outlined, label: l.realPerson, ok: p.livenessVerified, pendingLabel: '—'),
                          _VerifRow(icon: Icons.badge_outlined, label: p.identityVerified ? l.identityVerified : l.identityNotVerified, ok: p.identityVerified, pendingLabel: '—'),
                          _VerifRow(icon: Icons.image_outlined, label: l.photosReviewed, ok: p.photosReviewed, pendingLabel: l.statusPending),
                        ]),
                        if (p.managedBy != null) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            const Icon(Icons.family_restroom_rounded, size: 18, color: OlfaColors.primary),
                            const SizedBox(width: 8),
                            Expanded(child: Text(l.managedBy(relationLabel(l, p.managedBy!)), style: t.bodySmall.copyWith(fontWeight: FontWeight.w600))),
                          ]),
                        ],
                      ]),
                      if (!widget.own) ...[
                        const SizedBox(height: 14),
                        Center(
                          child: TextButton.icon(
                            onPressed: () => showReportSheet(context, ref, p),
                            icon: const Icon(Icons.flag_outlined, size: 18),
                            label: Text(l.reportOrBlock),
                            style: TextButton.styleFrom(foregroundColor: OlfaColors.textMuted),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (actions != null)
          DecoratedBox(
            decoration: const BoxDecoration(color: OlfaColors.white, border: Border(top: BorderSide(color: OlfaColors.gray))),
            child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), child: actions)),
          ),
      ],
    );
  }
}

enum _Section { photos, about, basics, background, marriage, interests, trust }

/// Pinned chips under the header: jump to any part of the profile.
class _JumpBar extends SliverPersistentHeaderDelegate {
  _JumpBar({required this.top, required this.items, required this.current, required this.onTap});
  final double top;
  final Map<_Section, String> items;
  final _Section current;
  final ValueChanged<_Section> onTap;

  static const double _h = 52;
  @override
  double get minExtent => _h + top;
  @override
  double get maxExtent => _h + top;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        color: OlfaColors.white,
        padding: EdgeInsets.only(top: top),
        alignment: Alignment.center,
        child: Row(children: [
          const SizedBox(width: 8),
          OlfaIconButton(icon: Icons.arrow_back_rounded, tooltip: MaterialLocalizations.of(context).backButtonTooltip, onPressed: () => Navigator.of(context).maybePop()),
          Expanded(
           child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 20, 8),
          children: [
            for (final e in items.entries) ...[
              OlfaChoice(label: e.value, selected: e.key == current, small: true, onTap: () => onTap(e.key)),
              const SizedBox(width: 8),
            ],
          ],
           ),
          ),
        ]),
      );

  @override
  bool shouldRebuild(_JumpBar old) => old.current != current || old.items.length != items.length || old.top != top;
}

class _KeyValueGrid extends StatelessWidget {
  const _KeyValueGrid({required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (k, v) in items)
              Container(
                width: w,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(k, style: t.caption), const SizedBox(height: 2), Text(v, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600))],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _VerifRow extends StatelessWidget {
  const _VerifRow({required this.icon, required this.label, required this.ok, required this.pendingLabel});
  final IconData icon;
  final String label;
  final bool ok;
  final String pendingLabel;

  @override
  Widget build(BuildContext context) => OlfaListTile(
        icon: icon,
        title: label,
        accent: ok,
        trailing: ok ? const Icon(Icons.check_rounded, color: OlfaColors.primary) : Text(pendingLabel, style: context.type.caption),
      );
}

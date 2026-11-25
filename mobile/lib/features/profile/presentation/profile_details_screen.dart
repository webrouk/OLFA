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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final p = widget.profile;
    final top = MediaQuery.paddingOf(context).top;
    final photos = p.photos;
    final actions = _actions(l);

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // PageView builds pages lazily; each uses the full-size
                      // variant only here, and the cache keeps it for re-entry.
                      PageView.builder(
                        controller: _pager,
                        itemCount: photos.isEmpty ? 1 : photos.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        // The card-size photo (already cached from Discovery) shows until the full one loads.
                        itemBuilder: (_, i) => OlfaImage(url: photos.isEmpty ? null : photos[i].fullUrl, placeholderUrl: photos.isEmpty ? null : photos[i].cardUrl),
                      ),
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
                      if (photos.length > 1)
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
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(nameAge(context, p.name, p.age), style: t.h1)),
                        ...[const SizedBox(width: 8), VerificationMark(profile: p, size: 22)],
                      ],
                    ),
                    if (p.showLocation) ...[
                      const SizedBox(height: 4),
                      Row(children: [Icon(Icons.place_outlined, size: 16, color: OlfaColors.textMuted), const SizedBox(width: 4), Text('${p.city} · ${countryLabel(context, p.countryIso)}', style: t.caption)]),
                    ],
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
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (!widget.own) OlfaTag(l.compatibility(p.compatibility), style: OlfaTagStyle.accent, icon: Icons.people_alt_outlined),
                      OlfaTag(l.timelineLabel(p.timeline)),
                    ]),
                    SectionLabel(l.about),
                    Text(p.bio, style: t.bodyMedium),
                    SectionLabel(l.basics),
                    _KeyValueGrid(items: [
                      (l.maritalStatus, l.maritalLabel(p.maritalStatus)),
                      (l.education, l.educationLabel(p.education)),
                      (l.occupation, occupationLabel(context, p.occupation)),
                      if (p.heightCm != null) (l.height, '${p.heightCm} ${l.cm}'),
                      if (p.weightKg != null) (l.weight, '${p.weightKg} ${l.kg}'),
                      if (p.nationality != null) (l.nationality, nationalityByIso(p.nationality)?.label(langOf(context), female: p.gender == Gender.female) ?? p.nationality!),
                      (l.marriageTimeline, l.timelineLabel(p.timeline)),
                    ]),
                    SectionLabel(l.interests),
                    Wrap(spacing: 8, runSpacing: 8, children: [for (final k in p.interests) OlfaTag(interestLabel(context, k))]),
                    SectionLabel(l.verification),
                    TileGroup(children: [
                      _VerifRow(icon: Icons.image_outlined, label: l.photosReviewed, ok: p.photosReviewed, pendingLabel: l.statusPending),
                      _VerifRow(icon: Icons.camera_alt_outlined, label: l.realPerson, ok: p.livenessVerified, pendingLabel: '—'),
                      _VerifRow(icon: Icons.badge_outlined, label: p.identityVerified ? l.identityVerified : l.identityNotVerified, ok: p.identityVerified, pendingLabel: '—'),
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

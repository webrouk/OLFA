import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../data/matching_repository_impl.dart';
import 'match_actions.dart';
import '../../../shared/components/verification_ticks.dart';
import '../../../core/routing/navigation.dart';

/// 16 — Matches. Starting a new conversation spends one daily credit.
class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});
  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  String? _starting;

  Future<void> _open(MatchItem m) async {
    if (_starting != null) return;
    setState(() => _starting = m.id);
    try {
      await openMatchChat(context, ref, m);
    } finally {
      if (mounted) setState(() => _starting = null);
    }
  }

  String _q = '';
  int _tab = 0; // 0 all · 1 new · 2 chatting

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenMatches), automaticallyImplyLeading: false),
      body: AsyncView<List<MatchItem>>(
        value: ref.watch(matchesProvider),
        onRetry: () => ref.invalidate(matchesProvider),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(icon: Icons.people_outline_rounded, title: l.noMatchesTitle, body: l.noMatchesBody, action: PrimaryButton(label: l.navDiscover, expand: false, onPressed: () => context.go(Routes.discover)));
          }
          final q = _q.toLowerCase();
          final list = all.where((m) => q.isEmpty || m.peer.name.toLowerCase().contains(q)).toList();
          final fresh = list.where((m) => m.conversationId == null).toList();
          final chatting = list.where((m) => m.conversationId != null).toList();
          final shown = switch (_tab) { 1 => fresh, 2 => chatting, _ => list };
          return RefreshIndicator(
            color: OlfaColors.primary,
            onRefresh: () => ref.refresh(matchesProvider.future),
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, OlfaSize.navBarClearance(context)),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _q = v.trim()),
                  decoration: InputDecoration(hintText: l.searchMatches, prefixIcon: const Icon(Icons.search_rounded)),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  for (final (i, label) in [(0, '${l.all} · ${list.length}'), (1, '${l.newMatches} · ${fresh.length}'), (2, '${l.chatting} · ${chatting.length}')])
                    Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: OlfaChoice(small: true, label: label, selected: _tab == i, onTap: () => setState(() => _tab = i))),
                ]),
                if (ent != null) ...[
                  const SizedBox(height: 12),
                  InfoBanner(icon: Icons.chat_bubble_outline_rounded, text: '${l.startersLeft}: ${ent.messagesLeft}/${ent.dailyMessages}'),
                ],
                if (_tab != 2 && fresh.isNotEmpty) ...[
                  SectionLabel(l.newMatches),
                  SizedBox(
                    height: 204, // photo + a 44 px action row
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: fresh.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _NewMatchCard(m: fresh[i], busy: _starting == fresh[i].id, onStart: () => _open(fresh[i])),
                    ),
                  ),
                ],
                if (_tab != 1) ...[
                  SectionLabel(_tab == 2 ? l.chatting : l.allMatches),
                  if (shown.isEmpty) Text(l.noResults, style: t.bodySmall.copyWith(color: OlfaColors.textMuted)),
                  TileGroup(children: [
                    for (final m in shown)
                      InkWell(
                        // a chat opens; a match without a chat yet shows the profile first
                        onTap: () => m.conversationId != null ? _open(m) : context.pushOnce(Routes.profile(m.peer.id), extra: m.peer),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(children: [
                            InkWell(onTap: () => context.pushOnce(Routes.profile(m.peer.id), extra: m.peer), child: OlfaAvatar(size: 52, url: m.peer.mainPhoto?.thumbUrl, online: m.peer.online)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(child: Text('${m.peer.name}, ${m.peer.age}', style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                  ...[const SizedBox(width: 6), VerificationTicks(profile: m.peer, size: 16)],
                                  const SizedBox(width: 6),
                                  _MatchState(m: m),
                                ]),
                                Text(
                                  [l.compatibility(m.peer.compatibility), if (m.peer.distanceKm != null) l.kmAway(m.peer.distanceKm!), l.matchedOn(shortTime(context, m.createdAt))].join(' · '),
                                  style: t.caption,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ]),
                            ),
                            const SizedBox(width: 8),
                            m.conversationId != null
                                ? OlfaIconButton(icon: Icons.chat_bubble_outline_rounded, tooltip: l.openChat, style: OlfaIconStyle.soft, onPressed: () => _open(m))
                                : PrimaryButton(label: l.startChat, expand: false, loading: _starting == m.id, onPressed: () => _open(m)),
                          ]),
                        ),
                      ),
                  ]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NewMatchCard extends StatelessWidget {
  const _NewMatchCard({required this.m, required this.busy, required this.onStart});
  final MatchItem m;
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return SizedBox(
      width: 132,
      child: ClipRRect(
        borderRadius: OlfaRadius.all(18),
        child: Material(
          color: OlfaColors.white,
          child: InkWell(
            onTap: () => context.pushOnce(Routes.profile(m.peer.id), extra: m.peer),
            child: Column(children: [
              Expanded(
                child: Stack(fit: StackFit.expand, children: [
                  OlfaImage(url: m.peer.mainPhoto?.cardUrl ?? m.peer.mainPhoto?.thumbUrl),
                  PositionedDirectional(top: 8, start: 8, child: OlfaTag(l.compatibility(m.peer.compatibility), style: OlfaTagStyle.onImage)),
                ]),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 0, 0),
                child: Row(children: [
                  const SizedBox(width: 2),
                  Expanded(child: Text(m.peer.name, style: t.bodySmall.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                  // 44 px touch area around a 32 px button
                  Semantics(
                    button: true,
                    label: l.startChat,
                    child: InkResponse(
                      onTap: busy ? null : onStart,
                      radius: 22,
                      child: SizedBox.square(
                        dimension: 44,
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle),
                            child: busy
                                ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: OlfaColors.white))
                                : const Icon(Icons.chat_bubble_rounded, size: 15, color: OlfaColors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// New · Chatting · Paused — the same three states everywhere a match is listed.
class _MatchState extends StatelessWidget {
  const _MatchState({required this.m});
  final MatchItem m;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (label, style) = m.paused
        ? (l.matchPaused, OlfaTagStyle.dark)
        : m.conversationId == null
            ? (l.newMatches, OlfaTagStyle.primary)
            : (l.chatting, OlfaTagStyle.neutral);
    return OlfaTag(label, style: style);
  }
}

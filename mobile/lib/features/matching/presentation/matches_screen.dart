import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../data/matching_repository_impl.dart';

/// 16 — Matches. Starting a new conversation spends one daily credit.
class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});
  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  String? _starting;

  Future<void> _open(MatchItem m) async {
    if (m.conversationId != null) {
      context.push(Routes.chatWith(m.conversationId!));
      return;
    }
    if (_starting != null) return;
    final l = AppLocalizations.of(context);
    final ent = ref.read(entitlementsProvider).valueOrNull;
    if (ent != null && ent.messagesLeft <= 0) {
      showToast(context, l.quotaMessages);
      return;
    }
    final ok = await showConfirmation(
      context,
      title: l.startConversationTitle(m.peer.name),
      body: l.startConversationBody(ent?.messagesLeft ?? 0),
      confirmLabel: l.startConversation,
      icon: Icons.chat_bubble_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _starting = m.id);
    try {
      final id = await ref.read(matchingRepositoryProvider).startConversation(m.id);
      await ref.read(entitlementsProvider.notifier).refresh();
      ref.invalidate(matchesProvider);
      if (mounted) context.push(Routes.chatWith(id));
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _starting = null);
    }
  }

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
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(icon: Icons.people_outline_rounded, title: l.noMatchesTitle, body: l.noMatchesBody, action: PrimaryButton(label: l.navDiscover, expand: false, onPressed: () => context.go(Routes.discover)));
          }
          final fresh = list.where((m) => m.conversationId == null).toList();
          return RefreshIndicator(
            color: OlfaColors.primary,
            onRefresh: () => ref.refresh(matchesProvider.future),
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, OlfaSize.navBarClearance(context)),
              children: [
                if (ent != null)
                  OlfaCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Icon(Icons.chat_bubble_outline_rounded, color: OlfaColors.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text(l.startersLeft, style: t.bodySmall)),
                      Text('${ent.messagesLeft}/${ent.dailyMessages}', textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w700, fontSize: 17)),
                    ]),
                  ),
                if (fresh.isNotEmpty) ...[
                  SectionLabel(l.newMatches),
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: fresh.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (_, i) => InkWell(
                        borderRadius: OlfaRadius.all(16),
                        onTap: () => context.push(Routes.profile(fresh[i].peer.id)),
                        child: Column(children: [
                          OlfaAvatar(size: 64, ring: true, url: fresh[i].peer.mainPhoto?.thumbUrl),
                          const SizedBox(height: 6),
                          Text(fresh[i].peer.name, style: t.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ],
                SectionLabel(l.allMatches),
                TileGroup(children: [
                  for (final m in list)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        InkWell(onTap: () => context.push(Routes.profile(m.peer.id)), child: OlfaAvatar(size: 52, url: m.peer.mainPhoto?.thumbUrl, online: m.peer.online)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text('${m.peer.name}, ${m.peer.age}', style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                              if (m.peer.photosReviewed) ...[const SizedBox(width: 6), const VerifiedBadge(size: 16)],
                            ]),
                            Text('${m.peer.city} · ${l.compatibility(m.peer.compatibility)}', style: t.caption, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        m.conversationId != null
                            ? SecondaryButton(label: l.openChat, expand: false, onPressed: () => _open(m))
                            : PrimaryButton(label: l.startChat, expand: false, loading: _starting == m.id, onPressed: () => _open(m)),
                      ]),
                    ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }
}

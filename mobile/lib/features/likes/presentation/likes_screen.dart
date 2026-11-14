import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../matching/data/matching_repository_impl.dart';

/// 15 — Likes received. Free plans receive only the count from the server;
/// the blurred tiles contain no identities.
class LikesScreen extends ConsumerWidget {
  const LikesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final value = ref.watch(likesReceivedProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.screenLikes), automaticallyImplyLeading: false),
      body: AsyncView(
        value: value,
        onRetry: () => ref.invalidate(likesReceivedProvider),
        loading: const _GridSkeleton(),
        data: (data) {
          final locked = data.profiles.isEmpty && data.count > 0;
          if (data.count == 0) {
            return EmptyState(icon: Icons.favorite_border_rounded, title: l.noLikesTitle, body: l.noLikesBody);
          }
          final tiles = locked ? 6 : data.profiles.length;
          return RefreshIndicator(
            color: OlfaColors.primary,
            onRefresh: () => ref.refresh(likesReceivedProvider.future),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  sliver: SliverList.list(children: [
                    Text(l.likesCount(data.count), style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
                    if (locked) ...[
                      const SizedBox(height: 16),
                      OlfaCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(color: OlfaColors.primary, borderRadius: OlfaRadius.all(16)),
                                child: const Icon(Icons.visibility_outlined, color: OlfaColors.white),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l.seeWhoLikes, style: t.h3), Text(l.seeWhoLikesBody, style: t.caption)])),
                            ]),
                            const SizedBox(height: 14),
                            PrimaryButton(label: l.upgrade, onPressed: () => context.push(Routes.plans)),
                          ],
                        ),
                      ),
                    ],
                  ]),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, OlfaSize.navBarClearance(context)),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 3 / 4),
                    itemCount: tiles,
                    itemBuilder: (context, i) {
                      if (locked) {
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
                      final p = data.profiles[i];
                      return InkWell(
                        borderRadius: OlfaRadius.all(20),
                        onTap: () => context.push(Routes.profile(p.id)),
                        child: ClipRRect(
                          borderRadius: OlfaRadius.all(20),
                          child: Column(children: [
                            Expanded(child: OlfaImage(url: p.mainPhoto?.thumbUrl)),
                            Container(
                              color: OlfaColors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(children: [
                                Expanded(child: Text('${p.name}, ${p.age}', style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                if (p.photosReviewed) const VerifiedBadge(size: 18),
                              ]),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
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
        childAspectRatio: 3 / 4,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(4, (_) => const OlfaSkeleton(height: double.infinity, radius: 20)),
      );
}

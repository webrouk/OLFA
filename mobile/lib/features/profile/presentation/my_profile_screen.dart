import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/navigation.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../application/profile_controllers.dart';
import '../../consultations/application/consultation_providers.dart';
import '../../../shared/components/verification_ticks.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/privacy_screen.dart' show VisibilityCard;

/// 17 — My profile (hub for account & services)
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.screenMyProfile),
        automaticallyImplyLeading: false,
        actions: [OlfaIconButton(icon: Icons.settings_outlined, tooltip: l.screenSettings, onPressed: () => context.push(Routes.settings)), const SizedBox(width: 8)],
      ),
      body: AsyncView<UserProfile>(
        value: ref.watch(myProfileProvider),
        onRetry: () => ref.invalidate(myProfileProvider),
        data: (me) {
          final paid = ent != null && ent.plan != PlanCode.free;
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, OlfaSize.navBarClearance(context)),
            children: [
              Center(
                child: Stack(children: [
                  OlfaAvatar(size: 104, url: me.mainPhoto?.thumbUrl),
                  PositionedDirectional(
                    bottom: 0,
                    end: 0,
                    child: OlfaIconButton(icon: Icons.edit_outlined, tooltip: l.editProfile, style: OlfaIconStyle.filled, circle: true, size: 36, onPressed: () => _edit(context, ref, me)),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: Text('${me.name}, ${me.age}', style: t.h2)),
                ...[const SizedBox(width: 8), VerificationTicks(profile: me, size: 22)],
              ]),
              Center(child: Text('${me.city} · ${countryLabel(context, me.countryIso)}', style: t.caption)),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => context.pushOnce(Routes.profile(me.id), extra: me),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: Text(l.viewAsOthers),
                ),
              ),
              const SizedBox(height: 8),
              // Completeness: tapping it opens the editor on what is missing.
              InkWell(
                borderRadius: OlfaRadius.all(OlfaRadius.card),
                onTap: me.completeness < 100 ? () => _edit(context, ref, me) : null,
                child: OlfaCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Expanded(child: Text(l.profileCompleteness, style: t.bodySmall.copyWith(fontWeight: FontWeight.w600))), Text('${me.completeness}%', textDirection: TextDirection.ltr, style: t.number(15, color: OlfaColors.primary))]),
                    const SizedBox(height: 10),
                    ClipRRect(borderRadius: OlfaRadius.all(4), child: LinearProgressIndicator(value: me.completeness / 100, minHeight: 8, color: OlfaColors.primary, backgroundColor: OlfaColors.gray)),
                    if (me.completeness < 100) ...[const SizedBox(height: 10), Text(l.completenessTip, style: t.caption)],
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              // Who can see me — mirrors Privacy & security (server-enforced).
              Consumer(builder: (context, ref, _) {
                final priv = ref.watch(privacyProvider).valueOrNull;
                return priv == null ? const SizedBox.shrink() : VisibilityCard(settings: priv, onTap: () => context.push(Routes.privacy));
              }),
              SectionLabel(l.sectionAboutMe),
              TileGroup(children: [
                OlfaListTile(icon: Icons.edit_outlined, title: l.editProfile, onTap: () => _edit(context, ref, me)),
                OlfaListTile(icon: Icons.people_alt_outlined, title: l.prefsTitleShort, onTap: () => context.pushOnce(Routes.partnerPreferences)),
              ]),
              SectionLabel(l.sectionSubscription),
              OlfaCard(
                color: paid ? OlfaColors.black : OlfaColors.white,
                borderColor: paid ? OlfaColors.black : OlfaColors.gray,
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.workspace_premium_outlined, color: paid ? OlfaColors.white : OlfaColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.currentPlan, style: t.caption.copyWith(color: paid ? OlfaColors.white.withValues(alpha: 0.7) : null)),
                      Text(ent == null ? '—' : l.planLabel(ent.plan), style: t.h3.copyWith(color: paid ? OlfaColors.white : null)),
                    ]),
                  ),
                  PrimaryButton(label: paid ? l.manage : l.upgrade, expand: false, inverted: paid, onPressed: () => context.push(Routes.plans)),
                ]),
              ),
              const SizedBox(height: 10),
              TileGroup(children: [
                OlfaListTile(icon: Icons.receipt_long_outlined, title: l.screenPayments, onTap: () => context.push(Routes.payments)),
              ]),
              SectionLabel(l.screenConsultations),
              // Family & marital consultations — booking, and the counselor side.
              TileGroup(children: [
                OlfaListTile(icon: Icons.support_agent_rounded, title: l.screenConsultations, subtitle: l.consultTileSub, accent: true, onTap: () => context.push(Routes.consultations)),
                Consumer(builder: (context, ref, _) {
                  final pending = ref.watch(pendingReviewsProvider).valueOrNull ?? const [];
                  return OlfaListTile(
                    icon: Icons.event_note_outlined,
                    title: l.screenMyConsultations,
                    subtitle: pending.isEmpty ? null : l.reviewsWaiting(pending.length),
                    trailing: pending.isEmpty ? null : OlfaTag('${pending.length}', style: OlfaTagStyle.primary),
                    onTap: () => context.push(Routes.myConsultations),
                  );
                }),
              ]),
              SectionLabel(l.sectionAccount),
              TileGroup(children: [
                OlfaListTile(icon: Icons.shield_outlined, title: l.screenPrivacy, onTap: () => context.push(Routes.privacy)),
                OlfaListTile(icon: Icons.notifications_none_rounded, title: l.screenNotifications, onTap: () => context.push(Routes.notifications)),
                OlfaListTile(icon: Icons.help_outline_rounded, title: l.screenHelp, onTap: () => context.push(Routes.help)),
                OlfaListTile(icon: Icons.settings_outlined, title: l.screenSettings, onTap: () => context.push(Routes.settings)),
              ]),
            ],
          );
        },
      ),
    );
  }

  void _edit(BuildContext context, WidgetRef ref, UserProfile me) {
    ref.read(profileDraftProvider.notifier).loadForEditing(me);
    context.pushOnce(Routes.editProfile);
  }
}

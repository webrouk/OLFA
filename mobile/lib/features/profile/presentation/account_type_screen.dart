import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../account/account_type.dart';
import '../application/profile_controllers.dart';
import 'setup_screens.dart' show setupTotal;

/// Sign-up step 2: what the account is for. It decides the rest of sign-up
/// ("about you" fields, partner preferences only for members), the app's
/// navigation and what the account may do. It is locked once the profile is
/// created — a professional and a member are separate accounts.
class AccountTypeScreen extends ConsumerStatefulWidget {
  const AccountTypeScreen({super.key});
  @override
  ConsumerState<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends ConsumerState<AccountTypeScreen> {
  bool _busy = false;

  Future<void> _continue(AccountType t) async {
    setState(() => _busy = true);
    try {
      await ref.read(accountTypeProvider.notifier).choose(t);
      ref.read(profileDraftProvider.notifier).update((d) => d.copyWith(accountType: t));
      if (mounted) context.push(t.isProfessional ? Routes.professionalInfo : Routes.profileInfo);
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final d = ref.watch(profileDraftProvider);
    final selected = d.accountType;
    Widget option(AccountType type, IconData icon, String title, String body, List<String> points) {
      final on = selected == type;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: on ? OlfaColors.primaryTint() : OlfaColors.white,
            shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(20), side: BorderSide(color: on ? OlfaColors.primary : OlfaColors.gray, width: 1.5)),
            child: InkWell(
              borderRadius: OlfaRadius.all(20),
              onTap: () => ref.read(profileDraftProvider.notifier).update((x) => x.copyWith(accountType: type)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: on ? OlfaColors.primary : OlfaColors.gray, borderRadius: OlfaRadius.all(16)),
                    child: Icon(icon, color: on ? OlfaColors.white : OlfaColors.black),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: t.h3),
                      const SizedBox(height: 4),
                      Text(body, style: t.bodySmall.copyWith(color: OlfaColors.textMuted)),
                      const SizedBox(height: 8),
                      for (final p in points)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.check_rounded, size: 16, color: OlfaColors.primary),
                            const SizedBox(width: 6),
                            Expanded(child: Text(p, style: t.caption.copyWith(color: OlfaColors.black))),
                          ]),
                        ),
                    ]),
                  ),
                  Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: on ? OlfaColors.primary : OlfaColors.textDisabled),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return FormPage(
      header: SetupProgress(step: 2, total: setupTotal(d)),
      action: PrimaryButton(label: l.continueLabel, loading: _busy, onPressed: selected == null || _busy ? null : () => _continue(selected)),
      children: [
        PageHeading(l.accountTypeTitle, body: l.accountTypeBody),
        option(AccountType.member, Icons.favorite_border_rounded, l.typeMember, l.typeMemberBody, [l.typeMemberP1, l.typeMemberP2]),
        option(AccountType.psychologist, Icons.psychology_outlined, l.typePsychologist, l.typePsychologistBody, [l.typeProP1, l.typeProP2]),
        option(AccountType.familyCounselor, Icons.family_restroom_rounded, l.typeFamilyCounselor, l.typeFamilyCounselorBody, [l.typeProP1, l.typeProP2]),
        const SizedBox(height: 4),
        InfoBanner(text: l.accountTypeLocked, icon: Icons.lock_outline_rounded),
      ],
    );
  }
}

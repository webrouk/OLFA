import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../application/profile_controllers.dart';
import '../data/profile_repository_impl.dart';

/// The arrangement being edited (owner's consent is a separate, required tick).
class ManagerFormValue {
  const ManagerFormValue({this.name = '', this.relation, this.phoneHolder = ManagedPhoneHolder.manager, this.consent = false});
  final String name;
  final ManagedRelation? relation;
  final ManagedPhoneHolder phoneHolder;
  final bool consent;

  bool get valid => name.trim().length >= 2 && relation != null && consent;
  AccountManagerInfo toInfo() => AccountManagerInfo(managerName: name.trim(), relation: relation!, phoneHolder: phoneHolder);
  ManagerFormValue copyWith({String? name, ManagedRelation? relation, ManagedPhoneHolder? phoneHolder, bool? consent}) =>
      ManagerFormValue(name: name ?? this.name, relation: relation ?? this.relation, phoneHolder: phoneHolder ?? this.phoneHolder, consent: consent ?? this.consent);
}

/// Manager name, relation, whose phone signs in, and the owner's agreement.
/// Used at sign-up ("For a family member") and in Account management.
class ManagerFields extends StatelessWidget {
  const ManagerFields({super.key, required this.value, required this.controller, required this.onChanged});
  final ManagerFormValue value;
  final TextEditingController controller;
  final ValueChanged<ManagerFormValue> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l.managerSectionTitle, style: t.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      OlfaTextField(label: l.managerNameLabel, controller: controller, maxLength: 60, onChanged: (v) => onChanged(value.copyWith(name: v))),
      Text(l.managerRelationLabel, style: t.inputLabel),
      const SizedBox(height: 8),
      ChoiceWrap<ManagedRelation>(
        options: ManagedRelation.values,
        label: (r) => relationLabel(l, r),
        isSelected: (r) => r == value.relation,
        onTap: (r) => onChanged(value.copyWith(relation: r)),
      ),
      const SizedBox(height: 16),
      Text(l.managerPhoneQ, style: t.inputLabel),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OlfaChoice(label: l.managerPhoneManager, selected: value.phoneHolder == ManagedPhoneHolder.manager, onTap: () => onChanged(value.copyWith(phoneHolder: ManagedPhoneHolder.manager))),
        OlfaChoice(label: l.managerPhoneOwner, selected: value.phoneHolder == ManagedPhoneHolder.owner, onTap: () => onChanged(value.copyWith(phoneHolder: ManagedPhoneHolder.owner))),
      ]),
      const SizedBox(height: 12),
      CheckboxListTile(
        value: value.consent,
        onChanged: (v) => onChanged(value.copyWith(consent: v ?? false)),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: OlfaColors.primary,
        title: Text(l.managerConsent, style: t.bodySmall),
      ),
      const SizedBox(height: 4),
      InfoBanner(icon: Icons.person_outline_rounded, text: l.managerOwnerNote),
      const SizedBox(height: 8),
      InfoBanner(icon: Icons.lock_outline_rounded, text: l.managerPublicNote),
    ]);
  }
}

final accountManagerProvider = FutureProvider.autoDispose<AccountManagerInfo?>((ref) => ref.watch(profileRepositoryProvider).manager());

/// Me → Settings → Account management: who runs the account; change or end it.
class AccountManagementScreen extends ConsumerStatefulWidget {
  const AccountManagementScreen({super.key});
  @override
  ConsumerState<AccountManagementScreen> createState() => _AccountManagementScreenState();
}

class _AccountManagementScreenState extends ConsumerState<AccountManagementScreen> {
  final _name = TextEditingController();
  ManagerFormValue? _form; // null = not editing
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _edit(AccountManagerInfo? m) {
    _name.text = m?.managerName ?? '';
    setState(() => _form = ManagerFormValue(name: _name.text, relation: m?.relation, phoneHolder: m?.phoneHolder ?? ManagedPhoneHolder.manager));
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final f = _form!;
    if (!f.consent) return showToast(context, l.managerConsentRequired);
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).setManager(f.toInfo());
      ref
        ..invalidate(accountManagerProvider)
        ..invalidate(myProfileProvider);
      if (!mounted) return;
      setState(() => _form = null);
      showToast(context, l.saved);
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    final l = AppLocalizations.of(context);
    final ok = await showConfirmation(context, title: l.managerRevoke, body: l.managerRevokeBody, confirmLabel: l.managerRevoke, destructive: true);
    if (!ok) return;
    try {
      await ref.read(profileRepositoryProvider).revokeManager();
      ref
        ..invalidate(accountManagerProvider)
        ..invalidate(myProfileProvider);
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final form = _form;
    if (form != null) {
      return FormPage(
        title: l.accountManagement,
        action: PrimaryButton(label: l.save, loading: _busy, onPressed: !form.valid || _busy ? null : _save),
        children: [ManagerFields(value: form, controller: _name, onChanged: (v) => setState(() => _form = v))],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.accountManagement)),
      body: AsyncView<AccountManagerInfo?>(
        value: ref.watch(accountManagerProvider),
        onRetry: () => ref.invalidate(accountManagerProvider),
        data: (m) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), children: [
          if (m == null) ...[
            InfoBanner(icon: Icons.person_outline_rounded, text: l.accountManagementSelf),
            const SizedBox(height: 16),
            SecondaryButton(label: l.accountManagementAdd, icon: Icons.family_restroom_rounded, onPressed: () => _edit(null)),
          ] else ...[
            OlfaCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.family_restroom_rounded, color: OlfaColors.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l.managedBy(relationLabel(l, m.relation)), style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 10),
                Text('${l.managerNameLabel}: ${m.managerName}', style: t.bodySmall),
                Text('${l.managerPhoneQ} ${m.phoneHolder == ManagedPhoneHolder.owner ? l.managerPhoneOwner : l.managerPhoneManager}', style: t.bodySmall),
              ]),
            ),
            const SizedBox(height: 12),
            InfoBanner(icon: Icons.lock_outline_rounded, text: l.managerPublicNote),
            const SizedBox(height: 16),
            SecondaryButton(label: l.edit, icon: Icons.edit_outlined, onPressed: () => _edit(m)),
            const SizedBox(height: 8),
            TextButton(onPressed: _revoke, style: TextButton.styleFrom(foregroundColor: OlfaColors.primary), child: Text(l.managerRevoke)),
          ],
        ]),
      ),
    );
  }
}

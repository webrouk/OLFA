import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/localization/generated/app_localizations.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_errors.dart';
import '../../core/routing/routes.dart';
import '../../core/security/account_restriction.dart';
import '../../core/security/secure_store.dart';
import '../../core/theme/olfa_colors.dart';
import '../../core/theme/olfa_spacing.dart';
import '../../core/theme/olfa_typography.dart';
import '../../core/widgets/olfa_widgets.dart';

/// Shown when the admin panel closed the account — same layout as the frozen-account
/// screen. Permanent: "closed permanently, cannot be reopened". Temporary: until a
/// date (it reopens by itself). Either way the person can still write to support.
class ClosedAccountScreen extends ConsumerStatefulWidget {
  const ClosedAccountScreen({super.key});
  @override
  ConsumerState<ClosedAccountScreen> createState() => _ClosedAccountScreenState();
}

class _ClosedAccountScreenState extends ConsumerState<ClosedAccountScreen> {
  bool _sent = false;

  Future<void> _appeal(AccountRestriction r) async {
    final l = AppLocalizations.of(context);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AppealSheet(),
    );
    if (text == null || !mounted) return;
    try {
      if (useApi) {
        await guard(() => ref.read(apiClientProvider).dio.post<void>(
              '/support/appeal',
              data: {'body': text},
              options: Options(extra: {'auth': false}, headers: {'Authorization': 'Bearer ${r.appealToken ?? ''}'}),
            ));
      }
      if (mounted) {
        setState(() => _sent = true);
        showToast(context, l.appealSent);
      }
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    }
  }

  Future<void> _signOut() async {
    await ref.read(secureStoreProvider).clear();
    accountRestriction.value = null;
    if (mounted) context.go(Routes.phone);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final r = accountRestriction.value ?? const AccountRestriction(permanent: true);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final body = r.permanent
        ? l.closedPermanentBody
        : r.until != null
            ? l.closedTemporaryBody(DateFormat.yMMMMd(locale).add_jm().format(r.until!))
            : l.closedOpenEndedBody;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(36)),
                child: Icon(r.permanent ? Icons.block_rounded : Icons.lock_clock_outlined, size: 52, color: OlfaColors.primary),
              ),
              const SizedBox(height: 22),
              Text(r.permanent ? l.closedPermanentTitle : l.closedTemporaryTitle, style: t.h1, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(body, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted), textAlign: TextAlign.center),
              if (r.reason != null && r.reason!.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                OlfaCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline_rounded, size: 19, color: OlfaColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.closedReason, style: t.caption),
                        const SizedBox(height: 2),
                        Text(r.reason!, style: t.bodyMedium),
                      ]),
                    ),
                  ]),
                ),
              ],
              const Spacer(),
              PrimaryButton(
                label: _sent ? l.appealSent : l.contactSupport,
                icon: Icons.support_agent_rounded,
                onPressed: _sent ? null : () => _appeal(r),
              ),
              const SizedBox(height: 8),
              SecondaryButton(label: l.communityPolicy, onPressed: () => context.push(Routes.terms)),
              const SizedBox(height: 4),
              TextButton(onPressed: _signOut, child: Text(l.signOut)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AppealSheet extends StatefulWidget {
  const _AppealSheet();
  @override
  State<_AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends State<_AppealSheet> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.appealTitle, style: context.type.h3),
        const SizedBox(height: 4),
        Text(l.appealHint, style: context.type.caption),
        const SizedBox(height: 14),
        OlfaTextField(label: l.message, controller: _c, maxLines: 5, maxLength: 2000, error: _error),
        PrimaryButton(
          label: l.send,
          onPressed: () {
            if (_c.text.trim().length < 10) return setState(() => _error = l.errorMessageShort);
            Navigator.pop(context, _c.text.trim());
          },
        ),
      ]),
    );
  }
}

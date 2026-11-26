import 'dart:async';

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
import '../../profile/application/profile_controllers.dart';
import '../application/auth_controller.dart';

/// 4 — Phone registration
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});
  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  late final _phone = TextEditingController(text: ref.read(authControllerProvider).nationalNumber);
  bool _terms = false;
  bool _touched = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _touched = true);
    final ctrl = ref.read(authControllerProvider.notifier);
    if (!ctrl.phoneValid || !_terms) return;
    final ok = await ctrl.requestOtp();
    if (ok && mounted) context.push(Routes.otp);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);
    final phoneError = _touched && !ctrl.phoneValid ? l.errorPhone : (s.failure == null ? null : failureMessage(context, s.failure!));
    return FormPage(
      action: PrimaryButton(
        label: l.sendCode,
        loading: s.busy,
        onPressed: ctrl.phoneValid && _terms ? _submit : null,
      ),
      children: [
        PageHeading(l.phoneTitle, body: l.phoneBody),
        PhoneInput(
          label: l.phoneLabel,
          pickerTitle: l.chooseCountry,
          country: s.country,
          onCountry: ctrl.setCountry,
          controller: _phone,
          onChanged: ctrl.setNumber,
          error: phoneError,
        ),
        const SizedBox(height: 22),
        OlfaCheck(value: _terms, onChanged: (v) => setState(() => _terms = v), label: l.agreeTerms),
        // Apple 1.2 / Play: the terms and privacy policy are readable before accepting.
        Wrap(spacing: 4, children: [
          TextButton(onPressed: () => context.push(Routes.terms), child: Text(l.terms)),
          TextButton(onPressed: () => context.push(Routes.privacyPolicy), child: Text(l.privacyPolicy)),
        ]),
        const SizedBox(height: 8),
        Text(l.phonePrivacyNote, style: context.type.caption),
      ],
    );
  }
}

/// 5 — OTP verification
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  String _code = '';
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    final ok = await ref.read(authControllerProvider.notifier).verify(_code);
    if (!ok || !mounted) return;
    final r = ref.read(authControllerProvider).result;
    // Returning users skip setup; new users continue to age confirmation.
    if (r != null && r.profileComplete) {
      final pro = r.accountType?.isProfessional ?? false;
      context.go(r.accountStatus == 'ACTIVE' ? (pro ? Routes.counselorDesk : Routes.discover) : Routes.verification);
    } else {
      context.push(Routes.age);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(authControllerProvider);
    final remaining = s.resendAt == null ? Duration.zero : s.resendAt!.difference(DateTime.now());
    final canResend = remaining <= Duration.zero && !s.busy;
    final mmss = '00:${remaining.inSeconds.clamp(0, 59).toString().padLeft(2, '0')}';
    final locked = s.attemptsLeft <= 0;

    return FormPage(
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(label: l.verify, loading: s.busy, onPressed: _code.length == 6 && !locked ? _verify : null),
          TextButton(onPressed: () => context.pop(), child: Text(l.changeNumber)),
        ],
      ),
      children: [
        PageHeading(l.otpTitle, body: l.otpBody(s.masked)),
        OtpInput(
          enabled: !locked,
          hasError: s.failure is InvalidOtpFailure,
          onChanged: (v) {
            setState(() => _code = v);
            if (v.length == 6) _verify();
          },
        ),
        if (s.failure != null) ...[
          const SizedBox(height: 12),
          Center(child: Text(locked ? l.otpLocked : failureMessage(context, s.failure!), style: context.type.bodySmall.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
        ],
        const SizedBox(height: 24),
        Center(
          child: canResend
              ? TextButton(onPressed: () => ref.read(authControllerProvider.notifier).requestOtp(), child: Text(l.resend))
              : Text(l.resendIn(mmss), style: context.type.caption),
        ),
        const SizedBox(height: 20),
        InfoBanner(text: l.otpDemoHint),
      ],
    );
  }
}

/// 6 — Age confirmation (18+)
class AgeScreen extends ConsumerStatefulWidget {
  const AgeScreen({super.key});
  @override
  ConsumerState<AgeScreen> createState() => _AgeScreenState();
}

class _AgeScreenState extends ConsumerState<AgeScreen> {
  DateTime? _dob;
  bool _c1 = false, _c2 = false;

  static int ageOn(DateTime dob, DateTime now) {
    var a = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) a--;
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final age = _dob == null ? null : ageOn(_dob!, DateTime.now());
    final under = age != null && age < 18;
    final ok = _c1 && _c2 && age != null && !under;
    return FormPage(
      action: PrimaryButton(
        label: l.continueLabel,
        onPressed: ok
            ? () {
                ref.read(profileDraftProvider.notifier).update((d) => d.copyWith(birthDate: _dob));
                context.go(Routes.gender);
              }
            : null,
      ),
      children: [
        Container(
          width: 64,
          height: 64,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(20)),
          child: const Icon(Icons.verified_user_outlined, color: OlfaColors.primary, size: 30),
        ),
        PageHeading(l.ageTitle, body: l.ageBody),
        Text(l.dateOfBirth, style: context.type.inputLabel),
        const SizedBox(height: 8),
        InkWell(
          key: const Key('dobPicker'),
          borderRadius: OlfaRadius.all(OlfaRadius.input),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
              firstDate: DateTime(now.year - 90),
              lastDate: now,
              initialEntryMode: DatePickerEntryMode.calendarOnly,
            );
            if (picked != null) setState(() => _dob = picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(errorText: under ? l.under18 : null, suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20)),
            child: Text(
              _dob == null ? l.selectDate : MaterialLocalizations.of(context).formatMediumDate(_dob!),
              style: context.type.bodyLarge.copyWith(color: _dob == null ? OlfaColors.textDisabled : null),
            ),
          ),
        ),
        const SizedBox(height: 22),
        OlfaCheck(value: _c1, onChanged: (v) => setState(() => _c1 = v), label: l.ageConfirm),
        OlfaCheck(value: _c2, onChanged: (v) => setState(() => _c2 = v), label: l.ageSerious),
      ],
    );
  }
}

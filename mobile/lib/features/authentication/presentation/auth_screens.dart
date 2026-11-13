import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';

/// Shared layout: scrollable form with a pinned bottom action.
class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.children, required this.action, this.header});
  final List<Widget> children;
  final Widget action;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (header != null) header!,
            Expanded(
              child: SingleChildScrollView(
                padding: OlfaSpace.page,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: action),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.title, this.body);
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.h1),
          const SizedBox(height: 8),
          Text(body, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
        ],
      ),
    );
  }
}

/// 4 — Phone registration
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});
  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phone = TextEditingController();
  bool _terms = false;
  String _dial = '+971';

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  bool get _valid => _phone.text.replaceAll(RegExp(r'\D'), '').length >= 8 && _terms;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FormPage(
      action: OlfaButton(
        label: l.sendCode,
        // Phase 2: POST /v1/auth/otp/request
        onPressed: _valid ? () => context.push(Routes.otp, extra: '$_dial ${_phone.text}') : null,
      ),
      children: [
        _Title(l.phoneTitle, l.phoneBody),
        Text(l.phoneLabel, style: context.type.inputLabel),
        const SizedBox(height: 8),
        // Phone numbers are always entered left-to-right, even in Arabic.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              DropdownButtonHideUnderline(
                child: Container(
                  height: OlfaSize.inputHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(OlfaRadius.input)),
                  child: DropdownButton<String>(
                    value: _dial,
                    items: const ['+971', '+966', '+20', '+965', '+974', '+973', '+968', '+962', '+212', '+44', '+1']
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) => setState(() => _dial = v!),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const Key('phoneField'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(15)],
                  decoration: const InputDecoration(hintText: '50 123 4567'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        OlfaCheck(value: _terms, onChanged: (v) => setState(() => _terms = v), label: l.agreeTerms),
      ],
    );
  }
}

/// 5 — OTP verification
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phone});
  final String phone;
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FormPage(
      action: Column(
        children: [
          OlfaButton(
            label: l.verify,
            onPressed: _code.text.length == 6
                ? () {
                    // Phase 2: POST /v1/auth/otp/verify. Demo: 000000 = error.
                    if (_code.text == '000000') {
                      setState(() => _error = true);
                    } else {
                      context.push(Routes.age);
                    }
                  }
                : null,
          ),
          TextButton(onPressed: () => context.pop(), child: Text(l.changeNumber)),
        ],
      ),
      children: [
        _Title(l.otpTitle, l.otpBody(widget.phone)),
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontFamily: 'Montserrat', fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 14),
            decoration: InputDecoration(counterText: '', errorText: _error ? l.otpError(4) : null),
            onChanged: (_) => setState(() => _error = false),
          ),
        ),
        const SizedBox(height: 20),
        Center(child: Text(l.resendIn('00:45'), style: context.type.caption)),
      ],
    );
  }
}

/// 6 — Age confirmation (18+)
class AgeScreen extends StatefulWidget {
  const AgeScreen({super.key});
  @override
  State<AgeScreen> createState() => _AgeScreenState();
}

class _AgeScreenState extends State<AgeScreen> {
  DateTime? _dob;
  bool _c1 = false, _c2 = false;

  int? get _age {
    final d = _dob;
    if (d == null) return null;
    final now = DateTime.now();
    var a = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final under = _age != null && _age! < 18;
    final ok = _c1 && _c2 && _age != null && !under;
    return FormPage(
      action: OlfaButton(label: l.continueLabel, onPressed: ok ? () => context.go(Routes.gender) : null),
      children: [
        Container(
          width: 64,
          height: 64,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(20)),
          child: const Icon(Icons.verified_user_outlined, color: OlfaColors.primary, size: 30),
        ),
        _Title(l.ageTitle, l.ageBody),
        Text(l.dateOfBirth, style: context.type.inputLabel),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: OlfaRadius.all(OlfaRadius.input),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              locale: locale,
              initialDate: DateTime(now.year - 25),
              firstDate: DateTime(now.year - 90),
              lastDate: now,
            );
            if (picked != null) setState(() => _dob = picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(errorText: under ? l.under18 : null, suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20)),
            child: Text(
              _dob == null ? '—' : MaterialLocalizations.of(context).formatMediumDate(_dob!),
              style: context.type.bodyLarge,
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

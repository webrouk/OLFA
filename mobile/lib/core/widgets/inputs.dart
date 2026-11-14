import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/models/models.dart';
import '../theme/olfa_colors.dart';
import '../theme/olfa_spacing.dart';
import '../theme/olfa_typography.dart';

/// Label + field + field-level error, consistent across every form.
class OlfaTextField extends StatelessWidget {
  const OlfaTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.error,
    this.onChanged,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.suffix,
    this.counter = false,
    this.autofillHints,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? error;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffix;
  final bool counter;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.inputLabel),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            initialValue: controller == null ? initialValue : null,
            onChanged: onChanged,
            maxLines: maxLines,
            minLines: maxLines > 1 ? 3 : 1,
            maxLength: maxLength,
            keyboardType: keyboardType ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            style: context.type.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              errorText: error,
              suffixIcon: suffix,
              counterText: counter ? null : '',
            ),
          ),
        ],
      ),
    );
  }
}

/// Country picker + national number. Always LTR, even in Arabic.
class PhoneInput extends StatelessWidget {
  const PhoneInput({
    super.key,
    required this.label,
    required this.country,
    required this.onCountry,
    required this.controller,
    required this.onChanged,
    required this.pickerTitle,
    this.error,
  });

  final String label;
  final Country country;
  final ValueChanged<Country> onCountry;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String pickerTitle;
  final String? error;

  Future<void> _pick(BuildContext context) async {
    final lang = Localizations.localeOf(context).languageCode;
    final picked = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(pickerTitle, style: context.type.h3)),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in kCountries)
                      ListTile(
                        leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                        title: Text(c.label(lang)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(c.dial, textDirection: TextDirection.ltr, style: context.type.caption),
                            if (c.iso == country.iso) ...[const SizedBox(width: 8), const Icon(Icons.check_rounded, color: OlfaColors.primary)],
                          ],
                        ),
                        onTap: () => Navigator.of(context).pop(c),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onCountry(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.type.inputLabel),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: OlfaColors.gray,
                borderRadius: OlfaRadius.all(OlfaRadius.input),
                child: InkWell(
                  borderRadius: OlfaRadius.all(OlfaRadius.input),
                  onTap: () => _pick(context),
                  child: SizedBox(
                    height: OlfaSize.inputHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Text(country.flag, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 6),
                          Text(country.dial, style: const TextStyle(fontFamily: 'Montserrat', fontSize: 15, fontWeight: FontWeight.w500)),
                          const Icon(Icons.expand_more_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const Key('phoneField'),
                  controller: controller,
                  onChanged: onChanged,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(15)],
                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 16, letterSpacing: 0.5),
                  decoration: InputDecoration(hintText: '50 123 4567', errorText: error),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Six-box OTP input backed by a single hidden field (supports SMS autofill
/// and paste). Always LTR.
class OtpInput extends StatefulWidget {
  const OtpInput({super.key, required this.onChanged, this.hasError = false, this.enabled = true, this.length = 6});
  final ValueChanged<String> onChanged;
  final bool hasError;
  final bool enabled;
  final int length;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _c = TextEditingController();
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.text;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          // Invisible real input
          Opacity(
            opacity: 0,
            child: TextField(
              key: const Key('otpField'),
              controller: _c,
              focusNode: _f,
              autofocus: true,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(widget.length)],
              onChanged: (s) {
                setState(() {});
                widget.onChanged(s);
              },
            ),
          ),
          GestureDetector(
            onTap: () => _f.requestFocus(),
            child: LayoutBuilder(
              builder: (context, c) {
                const gap = 8.0;
                final box = ((c.maxWidth - gap * (widget.length - 1)) / widget.length).clamp(36.0, 56.0).toDouble();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      Container(
                        width: box,
                        height: box * 1.18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.hasError ? OlfaColors.primaryTint() : (_f.hasFocus && i == v.length ? OlfaColors.white : OlfaColors.gray),
                          borderRadius: OlfaRadius.all(14),
                          border: Border.all(
                            width: 1.5,
                            color: widget.hasError || (_f.hasFocus && i == v.length) ? OlfaColors.primary : Colors.transparent,
                          ),
                        ),
                        child: Text(i < v.length ? v[i] : '', style: const TextStyle(fontFamily: 'Montserrat', fontSize: 22, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Large consent checkbox row.
class OlfaCheck extends StatelessWidget {
  const OlfaCheck({super.key, required this.value, required this.onChanged, required this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      child: InkWell(
        borderRadius: OlfaRadius.all(8),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: value ? OlfaColors.primary : OlfaColors.white,
                  borderRadius: OlfaRadius.all(7),
                  border: Border.all(color: value ? OlfaColors.primary : OlfaColors.textDisabled, width: 1.5),
                ),
                child: value ? const Icon(Icons.check_rounded, size: 16, color: OlfaColors.white) : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: context.type.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable pill. [locked] shows a lock (paid filter) and routes taps to [onLockedTap].
class OlfaChoice extends StatelessWidget {
  const OlfaChoice({super.key, required this.label, required this.selected, required this.onTap, this.locked = false, this.small = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool locked;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final on = selected && !locked;
    return Semantics(
      selected: on,
      button: true,
      child: Opacity(
        opacity: locked ? 0.5 : 1,
        child: Material(
          color: on ? OlfaColors.primaryTint() : OlfaColors.white,
          shape: StadiumBorder(side: BorderSide(color: on ? OlfaColors.primary : OlfaColors.gray, width: 1.5)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14, vertical: small ? 6 : 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (locked) ...[const Icon(Icons.lock_outline_rounded, size: 14), const SizedBox(width: 4)],
                  Text(
                    label,
                    style: (small ? context.type.bodySmall : context.type.bodyMedium).copyWith(
                      color: on ? OlfaColors.primary : OlfaColors.black,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrap of single- or multi-select choices.
class ChoiceWrap<T> extends StatelessWidget {
  const ChoiceWrap({super.key, required this.options, required this.label, required this.isSelected, required this.onTap, this.locked = false});
  final List<T> options;
  final String Function(T) label;
  final bool Function(T) isSelected;
  final ValueChanged<T> onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final o in options) OlfaChoice(label: label(o), selected: isSelected(o), locked: locked, onTap: () => onTap(o))],
    );
  }
}

/// −  value  + stepper used for age ranges.
class OlfaStepper extends StatelessWidget {
  const OlfaStepper({super.key, required this.value, required this.onChanged, this.min = 18, this.max = 80, required this.semanticLabel});
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, int d) => Material(
          color: OlfaColors.white,
          borderRadius: OlfaRadius.all(11),
          child: InkWell(
            borderRadius: OlfaRadius.all(11),
            onTap: (value + d < min || value + d > max) ? null : () => onChanged(value + d),
            child: SizedBox.square(dimension: 40, child: Icon(i, size: 20)),
          ),
        );
    return Semantics(
      label: semanticLabel,
      value: '$value',
      child: Container(
        height: OlfaSize.inputHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(OlfaRadius.input)),
        child: Row(
          children: [
            btn(Icons.remove_rounded, -1),
            Expanded(child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Montserrat', fontSize: 17, fontWeight: FontWeight.w700))),
            btn(Icons.add_rounded, 1),
          ],
        ),
      ),
    );
  }
}

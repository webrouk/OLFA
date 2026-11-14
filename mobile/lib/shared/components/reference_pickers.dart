import 'package:flutter/material.dart';

import '../../core/localization/generated/app_localizations.dart';
import '../../core/theme/olfa_colors.dart';
import '../../core/theme/olfa_spacing.dart';
import '../../core/theme/olfa_typography.dart';
import '../models/models.dart';
import 'labels.dart';

/// Searchable dropdowns over the shared reference lists
/// (shared/reference/*.tsv → generate.py): every country, every nationality
/// and the occupation catalogue. Values are ISO codes / occupation keys —
/// never display text — so the server can validate them.

class _Option {
  const _Option(this.value, this.label, {this.leading, this.group});
  final String? value;
  final String label;
  final String? leading;
  final String? group;
}

Future<String?> _pick(BuildContext context, {required String title, required List<_Option> options, String? selected}) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PickerSheet(title: title, options: options, selected: selected),
  );
}

/// Arabic letter variants and case folded so "اماراات" finds "الإمارات".
String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp('[ً-ْ]'), '');

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.options, this.selected});
  final String title;
  final List<_Option> options;
  final String? selected;
  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final q = _fold(_q.trim());
    final list = q.isEmpty ? widget.options : widget.options.where((o) => _fold(o.label).contains(q) || (o.value?.toLowerCase() == q)).toList();
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: context.type.h3),
            const SizedBox(height: 10),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(hintText: l.searchList, prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(l.noResults, style: context.type.bodyMedium.copyWith(color: OlfaColors.textMuted)))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final o = list[i];
                    final prevGroup = i == 0 ? null : list[i - 1].group;
                    final sel = o.value == widget.selected;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (q.isEmpty && o.group != null && o.group != prevGroup)
                        Padding(padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 6), child: Text(o.group!, style: context.type.caption.copyWith(fontWeight: FontWeight.w700))),
                      ListTile(
                        leading: o.leading == null ? null : Text(o.leading!, style: const TextStyle(fontSize: 22)),
                        title: Text(o.label, style: context.type.bodyMedium.copyWith(fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                        trailing: sel ? const Icon(Icons.check_rounded, color: OlfaColors.primary) : null,
                        onTap: () => Navigator.of(context).pop(o.value ?? ''),
                      ),
                    ]);
                  },
                ),
        ),
      ]),
    );
  }
}

/// Field-shaped trigger that opens the searchable sheet.
class _PickerField extends StatelessWidget {
  const _PickerField({required this.label, required this.text, required this.onTap, this.leading, this.error, this.locked = false});
  final String label;
  final String? text;
  final String? leading;
  final String? error;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: context.type.inputLabel),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: '$label: ${text ?? l.select}',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: OlfaRadius.all(16),
            onTap: onTap,
            child: InputDecorator(
              isEmpty: text == null,
              decoration: InputDecoration(
                errorText: error,
                suffixIcon: Icon(locked ? Icons.lock_outline_rounded : Icons.expand_more_rounded, color: locked ? OlfaColors.primary : null),
              ),
              child: Row(children: [
                if (leading != null) ...[Text(leading!, style: const TextStyle(fontSize: 18)), const SizedBox(width: 8)],
                Expanded(child: Text(text ?? l.select, overflow: TextOverflow.ellipsis, style: context.type.bodyMedium.copyWith(color: text == null ? OlfaColors.textMuted : null))),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class CountryField extends StatelessWidget {
  const CountryField({super.key, required this.label, required this.value, required this.onChanged, this.allowAny = false, this.locked = false, this.onLockedTap});
  final String label;
  final String? value;
  final bool allowAny;
  final bool locked;
  final VoidCallback? onLockedTap;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = langOf(context);
    final c = countryOrNull(value);
    final sorted = [...kCountries]..sort((a, b) => a.label(lang).compareTo(b.label(lang)));
    return _PickerField(
      label: label,
      text: c?.label(lang) ?? (allowAny ? l.anyCountry : null),
      leading: c?.flag,
      locked: locked,
      onTap: () async {
        if (locked) return onLockedTap?.call();
        final v = await _pick(context, title: label, selected: value, options: [
          if (allowAny) _Option(null, l.anyCountry),
          for (final x in sorted) _Option(x.iso, x.label(lang), leading: x.flag),
        ]);
        if (v != null) onChanged(v.isEmpty ? null : v);
      },
    );
  }
}

class NationalityField extends StatelessWidget {
  const NationalityField({super.key, required this.label, required this.value, required this.onChanged, this.allowAny = false, this.female = false, this.locked = false, this.onLockedTap, this.helper});
  final String label;
  final String? value;
  final bool allowAny;
  final bool female;
  final bool locked;
  final VoidCallback? onLockedTap;
  final String? helper;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = langOf(context);
    final n = nationalityByIso(value);
    final sorted = [...kNationalities]..sort((a, b) => a.label(lang).compareTo(b.label(lang)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _PickerField(
        label: label,
        text: n?.label(lang, female: female) ?? (allowAny ? l.anyNationality : null),
        leading: countryOrNull(n?.iso)?.flag,
        locked: locked,
        onTap: () async {
          if (locked) return onLockedTap?.call();
          final v = await _pick(context, title: label, selected: value, options: [
            if (allowAny) _Option(null, l.anyNationality),
            for (final x in sorted) _Option(x.iso, x.label(lang, female: female), leading: countryOrNull(x.iso)?.flag),
          ]);
          if (v != null) onChanged(v.isEmpty ? null : v);
        },
      ),
      if (helper != null) Padding(padding: const EdgeInsets.only(top: 0, bottom: 14), child: Text(helper!, style: context.type.caption)),
    ]);
  }
}

class OccupationField extends StatelessWidget {
  const OccupationField({super.key, required this.label, required this.value, required this.onChanged, this.allowAny = false, this.error, this.locked = false, this.onLockedTap});
  final String label;
  final String? value;
  final bool allowAny;
  final String? error;
  final bool locked;
  final VoidCallback? onLockedTap;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = langOf(context);
    final o = occupationByKey(value);
    final byCat = [...kOccupations]..sort((a, b) {
        final c = a.category.compareTo(b.category);
        return c != 0 ? c : a.label(lang).compareTo(b.label(lang));
      });
    return _PickerField(
      label: label,
      text: o?.label(lang) ?? (allowAny ? l.anyOccupation : null),
      error: error,
      locked: locked,
      onTap: () async {
        if (locked) return onLockedTap?.call();
        final v = await _pick(context, title: label, selected: value, options: [
          if (allowAny) _Option(null, l.anyOccupation),
          for (final x in byCat) _Option(x.key, x.label(lang), group: occupationCategoryLabel(l, x.category)),
        ]);
        if (v != null) onChanged(v.isEmpty ? null : v);
      },
    );
  }
}

String occupationCategoryLabel(AppLocalizations l, String c) => switch (c) {
      'health' => l.occHealth,
      'tech' => l.occTech,
      'engineering' => l.occEngineering,
      'education' => l.occEducation,
      'business' => l.occBusiness,
      'law' => l.occLaw,
      'government' => l.occGovernment,
      'religion' => l.occReligion,
      'media' => l.occMedia,
      'hospitality' => l.occHospitality,
      'transport' => l.occTransport,
      'trades' => l.occTrades,
      'agriculture' => l.occAgriculture,
      'science' => l.occScience,
      'social' => l.occSocial,
      'sports' => l.occSports,
      'retail' => l.occRetail,
      _ => l.occOther,
    };

/// Display label for a stored occupation key (falls back to legacy free text).
String occupationLabel(BuildContext context, String keyOrText) => occupationByKey(keyOrText)?.label(langOf(context)) ?? keyOrText;

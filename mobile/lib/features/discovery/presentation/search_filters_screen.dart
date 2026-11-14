import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../application/discover_controller.dart';

/// 14 — Search & filters. Paid sections follow server entitlements; the
/// server also rejects paid filters for free plans, so hiding is not the only
/// protection.
class SearchFiltersScreen extends ConsumerStatefulWidget {
  const SearchFiltersScreen({super.key});
  @override
  ConsumerState<SearchFiltersScreen> createState() => _SearchFiltersScreenState();
}

class _SearchFiltersScreenState extends ConsumerState<SearchFiltersScreen> {
  late DiscoverFilters _f = ref.read(filtersProvider);
  late final _city = TextEditingController(text: _f.city);
  late final _profession = TextEditingController(text: _f.profession);

  @override
  void dispose() {
    _city.dispose();
    _profession.dispose();
    super.dispose();
  }

  void _upsell() => context.push(Routes.plans);

  void _apply() {
    ref.read(filtersProvider.notifier).set(_f.copyWith(city: _city.text.trim(), profession: _profession.text.trim()));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    final paid = ent?.advancedFilters ?? false;
    final lang = langOf(context);

    Set<T> toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

    return FormPage(
      title: l.screenSearch,
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _f = const DiscoverFilters();
            _city.clear();
            _profession.clear();
          }),
          child: Text(l.reset),
        ),
      ],
      action: PrimaryButton(label: l.showResults, onPressed: _apply),
      children: [
        SectionLabel(l.basicFilters, top: 8),
        Text(l.ageRange, style: context.type.inputLabel),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: OlfaStepper(semanticLabel: l.ageMin, value: _f.ageMin, max: _f.ageMax, onChanged: (v) => setState(() => _f = _f.copyWith(ageMin: v)))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(l.to, style: context.type.caption)),
            Expanded(child: OlfaStepper(semanticLabel: l.ageMax, value: _f.ageMax, min: _f.ageMin, onChanged: (v) => setState(() => _f = _f.copyWith(ageMax: v)))),
          ],
        ),
        const SizedBox(height: 18),
        Text(l.country, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<String?>(
          options: const [null, 'AE', 'SA', 'EG', 'KW', 'QA', 'JO'],
          label: (iso) => iso == null ? l.anyCountry : countryByIso(iso).label(lang),
          isSelected: (iso) => _f.countryIso == iso,
          onTap: (iso) => setState(() => _f = _f.copyWith(countryIso: () => iso)),
        ),
        const SizedBox(height: 18),
        OlfaTextField(label: l.city, hint: l.allCities, controller: _city),
        Text(l.interests, style: context.type.inputLabel),
        const SizedBox(height: 4),
        Text(paid ? l.multiInterests : l.oneBasicInterest, style: context.type.caption),
        const SizedBox(height: 8),
        ChoiceWrap<Interest>(
          options: paid ? kInterests : kInterests.where((i) => i.basic).toList(),
          label: (i) => i.label(lang),
          isSelected: (i) => _f.interests.contains(i.key),
          onTap: (i) => setState(() {
            if (!paid) {
              // Free: a single basic interest.
              _f = _f.copyWith(interests: _f.interests.contains(i.key) ? <String>{} : {i.key});
            } else {
              _f = _f.copyWith(interests: toggle(_f.interests, i.key));
            }
          }),
        ),
        SectionLabel(
          l.advancedFilters,
          trailing: paid ? OlfaTag(l.planLabel(ent!.plan), style: OlfaTagStyle.accent) : OlfaTag('Plus', style: OlfaTagStyle.dark, icon: Icons.lock_outline_rounded),
        ),
        if (!paid) ...[
          InfoBanner(
            text: l.paidFiltersNote,
            icon: Icons.workspace_premium_outlined,
            accent: true,
            trailing: PrimaryButton(label: l.upgrade, expand: false, onPressed: _upsell),
          ),
          const SizedBox(height: 18),
        ],
        Text(l.maritalStatus, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<MaritalStatus>(
          options: MaritalStatus.values,
          locked: !paid,
          label: l.maritalLabel,
          isSelected: _f.maritalStatuses.contains,
          onTap: (m) => paid ? setState(() => _f = _f.copyWith(maritalStatuses: toggle(_f.maritalStatuses, m))) : _upsell(),
        ),
        const SizedBox(height: 18),
        Text(l.education, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<Education>(
          options: Education.values,
          locked: !paid,
          label: l.educationLabel,
          isSelected: _f.educations.contains,
          onTap: (e) => paid ? setState(() => _f = _f.copyWith(educations: toggle(_f.educations, e))) : _upsell(),
        ),
        const SizedBox(height: 18),
        if (paid)
          OlfaTextField(label: l.occupation, hint: l.occupationHint, controller: _profession)
        else ...[
          Text(l.occupation, style: context.type.inputLabel),
          const SizedBox(height: 8),
          OlfaChoice(label: l.occupationHint, selected: false, locked: true, onTap: _upsell),
          const SizedBox(height: 18),
        ],
        Text(l.minCompatibility, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<int?>(
          options: const [null, 70, 80, 90],
          locked: !paid,
          label: (v) => v == null ? l.any : '$v%',
          isSelected: (v) => _f.minCompatibility == v,
          onTap: (v) => paid ? setState(() => _f = _f.copyWith(minCompatibility: () => v)) : _upsell(),
        ),
      ],
    );
  }
}

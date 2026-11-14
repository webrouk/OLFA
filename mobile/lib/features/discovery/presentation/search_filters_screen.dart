import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/components/reference_pickers.dart';
import '../../../shared/models/models.dart';
import '../../location/data/location_service.dart';
import '../../profile/application/profile_controllers.dart';
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

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  void _upsell() => context.push(Routes.plans);

  void _apply() {
    ref.read(filtersProvider.notifier).set(_f.copyWith(city: _city.text.trim()));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    final paid = ent?.advancedFilters ?? false;
    final lang = langOf(context);
    final outside = ent?.searchOutsideCountry ?? false;
    final me = ref.watch(myProfileProvider).valueOrNull;
    final home = ref.watch(detectedLocationProvider)?.countryIso ?? me?.countryIso;

    Set<T> toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

    return FormPage(
      title: l.screenSearch,
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _f = const DiscoverFilters();
            _city.clear();
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
        Text(l.searchWhere, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<DiscoveryScope>(
          options: DiscoveryScope.values,
          locked: false,
          label: (s) => switch (s) {
            DiscoveryScope.nearby => l.scopeNearby,
            DiscoveryScope.myCountry => home == null ? l.scopeMyCountry : '${l.scopeMyCountry} · ${countryByIso(home).label(lang)}',
            DiscoveryScope.otherCountry => outside ? l.scopeOtherCountry : '${l.scopeOtherCountry} 🔒',
          },
          isSelected: (s) => _f.scope == s,
          onTap: (s) {
            if (s == DiscoveryScope.otherCountry && !outside) return _upsell();
            setState(() => _f = _f.copyWith(
                  scope: s,
                  countryIso: () => switch (s) {
                    DiscoveryScope.nearby => null,
                    DiscoveryScope.myCountry => home,
                    DiscoveryScope.otherCountry => _f.countryIso != home ? _f.countryIso : null,
                  },
                ));
          },
        ),
        const SizedBox(height: 6),
        Text(outside ? l.scopeNoteOutside : l.scopeNoteFree, style: context.type.caption),
        const SizedBox(height: 14),
        if (_f.scope == DiscoveryScope.otherCountry)
          CountryField(label: l.country, value: _f.countryIso, onChanged: (v) => setState(() => _f = _f.copyWith(countryIso: () => v))),
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
        OccupationField(
          label: l.occupation,
          value: _f.profession.isEmpty ? null : _f.profession,
          allowAny: true,
          locked: !paid,
          onLockedTap: _upsell,
          onChanged: (v) => setState(() => _f = _f.copyWith(profession: v ?? '')),
        ),
        NationalityField(
          label: l.nationality,
          value: _f.nationality,
          allowAny: true,
          locked: !paid,
          onLockedTap: _upsell,
          onChanged: (v) => setState(() => _f = _f.copyWith(nationality: () => v)),
        ),
        // Height and weight are available on every plan.
        RangeFilter(label: l.height, unit: l.cm, min: 140, max: 220, defaultRange: (155, 185), value: _f.height, onChanged: (v) => setState(() => _f = _f.copyWith(height: () => v))),
        RangeFilter(label: l.weight, unit: l.kg, min: 40, max: 160, defaultRange: (50, 90), value: _f.weight, onChanged: (v) => setState(() => _f = _f.copyWith(weight: () => v))),
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

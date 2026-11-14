import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../../profile/application/profile_controllers.dart';
import '../data/location_service.dart';

/// Setup step — approximate location so discovery can show the nearest
/// people first, then the user's own country. Optional ("Later").
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});
  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  bool _busy = false;
  LocationOutcome? _outcome;

  Future<void> _allow() async {
    setState(() => _busy = true);
    try {
      final svc = ref.read(locationServiceProvider);
      final (outcome, loc) = await svc.detect();
      if (!mounted) return;
      setState(() => _outcome = outcome);
      if (loc != null) {
        ref.read(detectedLocationProvider.notifier).set(loc);
        // Prefill residence (and nationality, unless the user changed it) when it is still the default.
        final draft = ref.read(profileDraftProvider);
        if (loc.countryIso != null && countryOrNull(loc.countryIso) != null) {
          ref.read(profileDraftProvider.notifier).update((d) {
            final x = draft.city.isEmpty && loc.city != null ? d.copyWith(city: loc.city) : d;
            return x.withCountry(loc.countryIso!);
          });
        }
        await svc.save(loc);
      }
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } catch (_) {
      if (mounted) setState(() => _outcome = LocationOutcome.denied);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() => context.push(Routes.photos);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final loc = ref.watch(detectedLocationProvider);
    final lang = langOf(context);
    final c = countryOrNull(loc?.countryIso);
    return FormPage(
      header: const SetupProgress(step: 3),
      action: loc != null
          ? PrimaryButton(label: l.continueLabel, onPressed: _next)
          : Column(mainAxisSize: MainAxisSize.min, children: [
              PrimaryButton(label: l.locationAllow, icon: Icons.my_location_rounded, loading: _busy, onPressed: _busy ? null : _allow),
              const SizedBox(height: 8),
              SecondaryButton(label: l.later, onPressed: _next),
            ]),
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(40)),
            child: const Icon(Icons.near_me_outlined, size: 54, color: OlfaColors.primary),
          ),
        ),
        const SizedBox(height: 24),
        Text(l.locationTitle, style: t.h1, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(l.locationBody, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        if (loc != null)
          OlfaCard(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.place_outlined, color: OlfaColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.locationFound, style: t.caption),
                  Text([if (loc.city != null) loc.city!, if (c != null) '${c.flag} ${c.label(lang)}'].join('، '), style: t.h3),
                ]),
              ),
              const Icon(Icons.check_rounded, color: OlfaColors.primary),
            ]),
          ),
        if (_outcome == LocationOutcome.deniedForever || _outcome == LocationOutcome.serviceOff)
          InfoBanner(
            text: _outcome == LocationOutcome.serviceOff ? l.locationServiceOff : l.locationDeniedForever,
            trailing: TextButton(
              onPressed: () => _outcome == LocationOutcome.serviceOff ? Geolocator.openLocationSettings() : Geolocator.openAppSettings(),
              child: Text(l.openSettings),
            ),
          ),
        if (_outcome == LocationOutcome.denied) InfoBanner(text: l.locationDenied),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: OlfaColors.textMuted),
          const SizedBox(width: 6),
          Flexible(child: Text(l.locationPrivacy, style: t.caption, textAlign: TextAlign.center)),
        ]),
      ],
    );
  }
}

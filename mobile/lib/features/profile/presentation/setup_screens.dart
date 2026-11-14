import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/components/reference_pickers.dart';
import '../../../shared/models/models.dart';
import '../application/profile_controllers.dart';
import '../domain/profile_draft.dart';

String? _err(AppLocalizations l, String? key) => switch (key) {
      null => null,
      'required' => l.errorRequired,
      'nameLength' => l.errorNameLength,
      'nameChars' => l.errorNameChars,
      'bioShort' => l.errorBioShort,
      'bioLong' => l.errorBioLong,
      'bioContact' => l.errorBioContact,
      _ => l.errorValidation,
    };

/// 7 — Gender selection (step 1/4)
class GenderScreen extends ConsumerWidget {
  const GenderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final g = ref.watch(profileDraftProvider).gender;
    final ctrl = ref.read(profileDraftProvider.notifier);

    Widget card(Gender value, String label, IconData icon) {
      final on = g == value;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: Material(
            color: on ? OlfaColors.primaryTint() : OlfaColors.white,
            shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(18), side: BorderSide(color: on ? OlfaColors.primary : OlfaColors.gray, width: 1.5)),
            child: InkWell(
              borderRadius: OlfaRadius.all(18),
              onTap: () => ctrl.update((d) => d.copyWith(gender: value)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
                child: Column(
                  children: [
                    CircleAvatar(radius: 32, backgroundColor: on ? OlfaColors.primary : OlfaColors.gray, child: Icon(icon, size: 30, color: on ? OlfaColors.white : OlfaColors.black)),
                    const SizedBox(height: 14),
                    Text(label, style: context.type.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return FormPage(
      header: const SetupProgress(step: 1),
      action: PrimaryButton(label: l.continueLabel, onPressed: g == null ? null : () => context.push(Routes.profileInfo)),
      children: [
        PageHeading(l.genderTitle, body: l.genderBody),
        Row(children: [card(Gender.male, l.man, Icons.male_rounded), const SizedBox(width: 12), card(Gender.female, l.woman, Icons.female_rounded)]),
        const SizedBox(height: 22),
        InfoBanner(text: l.genderNote),
      ],
    );
  }
}

/// 8 — Profile information (step 2/4)
class ProfileInfoScreen extends ConsumerStatefulWidget {
  const ProfileInfoScreen({super.key, this.editMode = false});
  final bool editMode;
  @override
  ConsumerState<ProfileInfoScreen> createState() => _ProfileInfoScreenState();
}

class _ProfileInfoScreenState extends ConsumerState<ProfileInfoScreen> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = ref.watch(profileDraftProvider);
    final ctrl = ref.read(profileDraftProvider.notifier);
    final lang = langOf(context);

    final errors = <String, String?>{
      'name': ProfileValidators.name(d.name),
      'city': ProfileValidators.required(d.city),
      'marital': ProfileValidators.required(d.maritalStatus),
      'education': ProfileValidators.required(d.education),
      'job': ProfileValidators.required(d.occupation),
      'timeline': ProfileValidators.required(d.timeline),
      'bio': ProfileValidators.bio(d.bio),
      'interests': d.interests.isEmpty ? 'required' : null,
    };
    String? e(String k) => _submitted ? _err(l, errors[k]) : null;
    final valid = errors.values.every((v) => v == null);

    Widget fieldError(String k) {
      final msg = e(k);
      return msg == null
          ? const SizedBox(height: 18)
          : Padding(padding: const EdgeInsets.only(top: 6, bottom: 12), child: Text(msg, style: context.type.bodySmall.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w500)));
    }

    return FormPage(
      header: const SetupProgress(step: 2),
      action: PrimaryButton(
        label: l.continueLabel,
        onPressed: () {
          setState(() => _submitted = true);
          if (valid) context.push(Routes.preferences);
        },
      ),
      children: [
        PageHeading(l.infoTitle),
        OlfaTextField(label: l.displayName, hint: l.displayNameHint, initialValue: d.name, error: e('name'), autofillHints: const [AutofillHints.givenName], onChanged: (v) => ctrl.update((x) => x.copyWith(name: v))),
        CountryField(label: l.countryOfResidence, value: d.countryIso, onChanged: (v) => ctrl.update((x) => v == null ? x : x.withCountry(v))),
        NationalityField(
          label: l.nationality,
          value: d.nationality,
          female: d.gender == Gender.female,
          helper: d.nationalityEdited ? null : l.nationalityAutoHint,
          onChanged: (v) => ctrl.update((x) => x.copyWith(nationality: v, nationalityEdited: true)),
        ),
        OlfaTextField(label: l.city, initialValue: d.city, error: e('city'), onChanged: (v) => ctrl.update((x) => x.copyWith(city: v))),
        Text(l.maritalStatus, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<MaritalStatus>(options: MaritalStatus.values, label: l.maritalLabel, isSelected: (m) => d.maritalStatus == m, onTap: (m) => ctrl.update((x) => x.copyWith(maritalStatus: m))),
        fieldError('marital'),
        Text(l.education, style: context.type.inputLabel),
        const SizedBox(height: 8),
        DropdownButtonFormField<Education>(
          value: d.education,
          isExpanded: true,
          hint: Text(l.select),
          decoration: InputDecoration(errorText: e('education')),
          items: [for (final x in Education.values) DropdownMenuItem(value: x, child: Text(l.educationLabel(x)))],
          onChanged: (v) => ctrl.update((x) => x.copyWith(education: v)),
        ),
        const SizedBox(height: 18),
        OccupationField(label: l.occupation, value: d.occupation.isEmpty ? null : d.occupation, error: e('job'), onChanged: (v) => ctrl.update((x) => x.copyWith(occupation: v ?? ''))),
        BodyMetricsFields(
          heightCm: d.heightCm,
          weightKg: d.weightKg,
          onHeight: (v) => ctrl.update((x) => x.copyWith(heightCm: () => v)),
          onWeight: (v) => ctrl.update((x) => x.copyWith(weightKg: () => v)),
        ),
        Text(l.marriageTimeline, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<MarriageTimeline>(options: MarriageTimeline.values, label: l.timelineLabel, isSelected: (t) => d.timeline == t, onTap: (t) => ctrl.update((x) => x.copyWith(timeline: t))),
        fieldError('timeline'),
        OlfaTextField(label: l.bio, hint: l.bioHint, initialValue: d.bio, maxLines: 4, maxLength: ProfileDraft.bioMax, counter: true, error: e('bio'), onChanged: (v) => ctrl.update((x) => x.copyWith(bio: v))),
        Row(
          children: [
            Expanded(child: Text(l.interests, style: context.type.inputLabel)),
            Text(l.interestsCount(d.interests.length, ProfileDraft.maxInterests), style: context.type.caption),
          ],
        ),
        const SizedBox(height: 8),
        ChoiceWrap<Interest>(options: kInterests, label: (i) => i.label(lang), isSelected: (i) => d.interests.contains(i.key), onTap: (i) => ctrl.toggleInterest(i.key)),
        fieldError('interests'),
      ],
    );
  }
}

/// 9 — Partner preferences (step 3/4)
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final d = ref.watch(profileDraftProvider);
    final ctrl = ref.read(profileDraftProvider.notifier);
    return FormPage(
      header: const SetupProgress(step: 3),
      action: PrimaryButton(label: l.continueLabel, onPressed: () => context.push(Routes.location)),
      children: [
        PageHeading(l.prefsTitle, body: l.prefsBody),
        Text(l.ageRange, style: context.type.inputLabel),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: OlfaStepper(semanticLabel: l.ageMin, value: d.prefAgeMin, max: d.prefAgeMax, onChanged: (v) => ctrl.update((x) => x.copyWith(prefAgeMin: v)))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(l.to, style: context.type.caption)),
            Expanded(child: OlfaStepper(semanticLabel: l.ageMax, value: d.prefAgeMax, min: d.prefAgeMin, onChanged: (v) => ctrl.update((x) => x.copyWith(prefAgeMax: v)))),
          ],
        ),
        const SizedBox(height: 22),
        Text(l.country, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<bool>(options: const [true, false], label: (b) => b ? l.sameCountry : l.anyCountry, isSelected: (b) => d.prefSameCountry == b, onTap: (b) => ctrl.update((x) => x.copyWith(prefSameCountry: b))),
        const SizedBox(height: 22),
        Text(l.acceptedMarital, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<MaritalStatus>(options: MaritalStatus.values, label: l.maritalLabel, isSelected: d.prefMarital.contains, onTap: ctrl.togglePrefMarital),
        const SizedBox(height: 22),
        Text(l.children, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<bool?>(
          options: const [true, null],
          label: (b) => b == true ? l.wantsChildren : l.noPreference,
          isSelected: (b) => d.prefWantsChildren == b,
          onTap: (b) => ctrl.update((x) => x.copyWith(prefWantsChildren: () => b)),
        ),
        const SizedBox(height: 24),
        InfoBanner(text: l.mutualNote, icon: Icons.people_alt_outlined, accent: true),
      ],
    );
  }
}

/// 10 — Photo upload (step 4/4)
class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});
  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(profileDraftProvider.notifier).submit();
      if (mounted) context.go(Routes.verification);
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = ref.watch(profileDraftProvider);
    final ctrl = ref.read(profileDraftProvider.notifier);
    return FormPage(
      header: const SetupProgress(step: 4),
      action: PrimaryButton(label: l.submitForReview, loading: _busy, onPressed: d.photosReady ? _submit : null),
      children: [
        PageHeading(l.photosTitle, body: l.photosBody),
        PhotoGrid(slots: d.photoSlots, onToggle: ctrl.togglePhoto),
        const SizedBox(height: 18),
        for (final tip in [l.photoTip1, l.photoTip2, l.photoTip3])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [const Icon(Icons.check_rounded, color: OlfaColors.primary, size: 18), const SizedBox(width: 10), Expanded(child: Text(tip, style: context.type.bodyMedium))]),
          ),
        const SizedBox(height: 10),
        TileGroup(children: [
          OlfaListTile(
            icon: Icons.camera_alt_outlined,
            accent: true,
            title: l.selfieTitle,
            subtitle: l.selfieBody,
            trailing: OlfaTag(l.optional),
            onTap: () => showToast(context, l.selfieLater),
          ),
        ]),
        const SizedBox(height: 14),
        OlfaCheck(value: d.photoRightsConfirmed, onChanged: (v) => ctrl.update((x) => x.copyWith(photoRightsConfirmed: v)), label: l.photoRights),
        OlfaCheck(value: d.policyAccepted, onChanged: (v) => ctrl.update((x) => x.copyWith(policyAccepted: v)), label: l.photoPolicy),
      ],
    );
  }
}

/// Shared 3×2 photo grid (setup + edit profile). In API mode an empty slot
/// opens the picker and uploads; a filled slot deletes the photo.
class PhotoGrid extends StatefulWidget {
  const PhotoGrid({super.key, required this.slots, required this.onToggle});
  final List<bool> slots;
  final Future<void> Function(int) onToggle;

  @override
  State<PhotoGrid> createState() => _PhotoGridState();
}

class _PhotoGridState extends State<PhotoGrid> {
  int? _busy;

  Future<void> _tap(int i) async {
    if (_busy != null) return;
    setState(() => _busy = i);
    try {
      await widget.onToggle(i);
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final slots = widget.slots;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3 / 4,
      children: [
        for (var i = 0; i < slots.length; i++)
          _busy == i
              ? const OlfaSkeleton(height: double.infinity, radius: 18)
              : slots[i]
                  ? ClipRRect(
                      borderRadius: OlfaRadius.all(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const PhotoPlaceholder(),
                          if (i == 0) PositionedDirectional(bottom: 8, start: 8, child: OlfaTag(l.mainPhoto, style: OlfaTagStyle.primary)),
                          PositionedDirectional(
                            top: 4,
                            end: 4,
                            child: OlfaIconButton(icon: Icons.close_rounded, tooltip: l.removePhoto, style: OlfaIconStyle.elevated, circle: true, size: 30, onPressed: () => _tap(i)),
                          ),
                        ],
                      ),
                    )
                  : Semantics(
                      button: true,
                      label: l.addPhoto,
                      child: InkWell(
                        borderRadius: OlfaRadius.all(18),
                        onTap: () => _tap(i),
                        child: DottedSlot(label: l.add),
                      ),
                    ),
      ],
    );
  }
}

class DottedSlot extends StatelessWidget {
  const DottedSlot({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(borderRadius: OlfaRadius.all(18), border: Border.all(color: OlfaColors.textDisabled, width: 1.5)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(Icons.add_rounded, color: OlfaColors.textMuted), Text(label, style: context.type.caption)],
        ),
      );
}

/// 11 — Verification status (pending / rejected / approved)
class VerificationScreen extends ConsumerWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final info = ref.watch(verificationProvider);
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: AsyncView<VerificationInfo>(
            value: info,
            onRetry: () => ref.invalidate(verificationProvider),
            data: (v) {
              final (icon, title, body) = switch (v.status) {
                VerificationStatus.pending => (Icons.hourglass_top_rounded, l.verifPendingTitle, l.verifPendingBody),
                VerificationStatus.rejected => (Icons.error_outline_rounded, l.verifRejectedTitle, l.verifRejectedBody),
                VerificationStatus.approved => (Icons.check_rounded, l.verifApprovedTitle, l.verifApprovedBody),
              };
              final approved = v.status == VerificationStatus.approved;
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Demo-only switcher so reviewers can see all three states.
                        Text(l.previewStates, style: t.caption),
                        const SizedBox(height: 8),
                        SegmentedButton<VerificationStatus>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(value: VerificationStatus.pending, label: Text(l.statusPending)),
                            ButtonSegment(value: VerificationStatus.rejected, label: Text(l.statusRejected)),
                            ButtonSegment(value: VerificationStatus.approved, label: Text(l.statusApproved)),
                          ],
                          selected: {v.status},
                          onSelectionChanged: (s) => setDemoVerification(ref, s.first),
                        ),
                        const SizedBox(height: 34),
                        Center(
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: approved ? OlfaColors.primary : (v.status == VerificationStatus.rejected ? OlfaColors.primaryTint() : OlfaColors.gray),
                              borderRadius: OlfaRadius.all(30),
                            ),
                            child: Icon(icon, size: 40, color: approved ? OlfaColors.white : OlfaColors.primary),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(title, style: t.h2, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        Text(body, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted), textAlign: TextAlign.center),
                        const SizedBox(height: 28),
                        if (v.status == VerificationStatus.rejected)
                          OlfaCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.rejectReason, style: t.caption),
                                const SizedBox(height: 4),
                                Text(v.reason ?? '', style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 14),
                                Text(l.howToFix, style: t.caption),
                                const SizedBox(height: 8),
                                for (var i = 0; i < v.fixSteps.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [OlfaTag('${i + 1}', style: OlfaTagStyle.accent), const SizedBox(width: 10), Expanded(child: Text(v.fixSteps[i], style: t.bodyMedium))],
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else
                          _Timeline(status: v.status),
                        if (approved) ...[
                          const SizedBox(height: 8),
                          InfoBanner(text: '${l.photosReviewed} — ${l.notIdentityNote}', icon: Icons.verified_rounded),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: switch (v.status) {
                      VerificationStatus.approved => PrimaryButton(label: l.startDiscovering, onPressed: () => context.go(Routes.discover)),
                      VerificationStatus.rejected => PrimaryButton(label: l.fixAndResubmit, onPressed: () => context.push(Routes.photos)),
                      VerificationStatus.pending => SecondaryButton(label: l.editProfile, onPressed: () => context.push(Routes.editProfile)),
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.status});
  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final steps = [
      (l.stepSubmitted, true),
      (l.stepAutoCheck, true),
      (l.stepHumanReview, status == VerificationStatus.approved),
      (l.stepLive, status == VerificationStatus.approved),
    ];
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: steps[i].$2 ? OlfaColors.primary : OlfaColors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: steps[i].$2 || (i > 0 && steps[i - 1].$2) ? OlfaColors.primary : OlfaColors.gray, width: 2),
                    ),
                    child: steps[i].$2
                        ? const Icon(Icons.check_rounded, size: 16, color: OlfaColors.white)
                        : Center(child: Text('${i + 1}', style: context.type.caption.copyWith(fontWeight: FontWeight.w700))),
                  ),
                  if (i < steps.length - 1) Container(width: 2, height: 26, color: steps[i].$2 ? OlfaColors.primary : OlfaColors.gray),
                ],
              ),
              const SizedBox(width: 14),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(steps[i].$1, style: context.type.bodyMedium.copyWith(fontWeight: FontWeight.w600))),
            ],
          ),
      ],
    );
  }
}

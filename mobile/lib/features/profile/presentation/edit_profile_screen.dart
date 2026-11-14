import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../application/profile_controllers.dart';
import '../data/profile_repository_impl.dart';
import '../domain/profile_draft.dart';
import 'setup_screens.dart' show PhotoGrid;

/// 21 — Edit profile. Changing name or photos sends the profile back to review.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final ProfileDraft _original = ref.read(profileDraftProvider);
  bool _busy = false;
  bool _submitted = false;

  bool _needsReview(ProfileDraft d) => d.name.trim() != _original.name.trim() || d.photoSlots.toString() != _original.photoSlots.toString();

  Future<void> _save() async {
    setState(() => _submitted = true);
    final l = AppLocalizations.of(context);
    final d = ref.read(profileDraftProvider);
    if (ProfileValidators.name(d.name) != null || ProfileValidators.bio(d.bio) != null || d.photoCount < ProfileDraft.minPhotos) return;
    if (_needsReview(d)) {
      final ok = await showConfirmation(context, title: l.reReviewTitle, body: l.reReviewBody, confirmLabel: l.save, icon: Icons.hourglass_top_rounded);
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(d);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      showToast(context, l.saved);
      context.pop();
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
    final lang = langOf(context);
    String? nameErr = _submitted ? ProfileValidators.name(d.name) : null;
    String? bioErr = _submitted ? ProfileValidators.bio(d.bio) : null;

    return FormPage(
      title: l.editProfile,
      action: PrimaryButton(label: l.save, loading: _busy, onPressed: _save),
      children: [
        InfoBanner(text: l.reReviewNote, accent: true),
        const SizedBox(height: 18),
        PhotoGrid(slots: d.photoSlots, onToggle: ctrl.togglePhoto),
        if (_submitted && d.photoCount < ProfileDraft.minPhotos)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.errorMinPhotos, style: context.type.bodySmall.copyWith(color: OlfaColors.primary))),
        const SizedBox(height: 20),
        OlfaTextField(label: l.displayName, initialValue: d.name, error: nameErr == null ? null : l.errorNameLength, onChanged: (v) => ctrl.update((x) => x.copyWith(name: v))),
        OlfaTextField(label: l.city, initialValue: d.city, onChanged: (v) => ctrl.update((x) => x.copyWith(city: v))),
        OlfaTextField(label: l.occupation, initialValue: d.occupation, onChanged: (v) => ctrl.update((x) => x.copyWith(occupation: v))),
        OlfaTextField(
          label: l.bio,
          initialValue: d.bio,
          maxLines: 4,
          maxLength: ProfileDraft.bioMax,
          counter: true,
          error: switch (bioErr) { null => null, 'bioContact' => l.errorBioContact, 'bioShort' => l.errorBioShort, _ => l.errorBioLong },
          onChanged: (v) => ctrl.update((x) => x.copyWith(bio: v)),
        ),
        Text(l.marriageTimeline, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<MarriageTimeline>(options: MarriageTimeline.values, label: l.timelineLabel, isSelected: (t) => d.timeline == t, onTap: (t) => ctrl.update((x) => x.copyWith(timeline: t))),
        const SizedBox(height: 22),
        Text(l.interests, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<Interest>(options: kInterests, label: (i) => i.label(lang), isSelected: (i) => d.interests.contains(i.key), onTap: (i) => ctrl.toggleInterest(i.key)),
      ],
    );
  }
}

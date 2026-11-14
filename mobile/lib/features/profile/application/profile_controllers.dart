import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';
import '../data/profile_repository_impl.dart';
import '../domain/profile_draft.dart';

/// Holds the in-progress profile across setup screens 7–10.
class ProfileDraftController extends Notifier<ProfileDraft> {
  @override
  ProfileDraft build() => const ProfileDraft();

  void update(ProfileDraft Function(ProfileDraft d) f) => state = f(state);

  void toggleInterest(String key) {
    final s = {...state.interests};
    if (!s.remove(key) && s.length < ProfileDraft.maxInterests) s.add(key);
    state = state.copyWith(interests: s);
  }

  void togglePrefMarital(MaritalStatus m) {
    final s = {...state.prefMarital};
    if (s.contains(m)) {
      if (s.length > 1) s.remove(m);
    } else {
      s.add(m);
    }
    state = state.copyWith(prefMarital: s);
  }

  void togglePhoto(int i) {
    final l = [...state.photoSlots];
    l[i] = !l[i];
    state = state.copyWith(photoSlots: l);
  }

  Future<void> submit() async {
    await ref.read(profileRepositoryProvider).submitForReview(state);
    ref.invalidate(verificationProvider);
  }
}

final profileDraftProvider = NotifierProvider<ProfileDraftController, ProfileDraft>(ProfileDraftController.new);

final verificationProvider = FutureProvider<VerificationInfo>((ref) => ref.watch(profileRepositoryProvider).verification());

/// Demo-only: lets reviewers preview pending / rejected / approved states.
void setDemoVerification(WidgetRef ref, VerificationStatus s) {
  ref.read(demoBackendProvider).verification = s;
  ref.invalidate(verificationProvider);
}

final myProfileProvider = FutureProvider<UserProfile>((ref) => ref.watch(profileRepositoryProvider).me());

final profileByIdProvider = FutureProvider.family<UserProfile, String>((ref, id) => ref.watch(profileRepositoryProvider).profile(id));

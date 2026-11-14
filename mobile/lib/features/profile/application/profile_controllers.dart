import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';
import '../../../core/network/api_client.dart' show useApi;
import '../data/profile_repository_impl.dart';
import 'photo_picker.dart';
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

  /// Empty slot → pick, compress and upload. Filled slot → delete.
  /// Demo mode toggles a placeholder without picking.
  Future<void> togglePhoto(int i) async {
    final slots = [...state.photoSlots];
    final ids = [...state.photoIds];
    final repo = ref.read(photoRepositoryProvider);
    if (slots[i]) {
      if (ids[i] != null) await repo.delete(ids[i]!);
      slots[i] = false;
      ids[i] = null;
    } else {
      if (useApi) {
        final picked = await ref.read(photoPickerProvider).pick();
        if (picked == null) return;
        ids[i] = await repo.upload(position: i, bytes: picked.bytes, mimeType: picked.mimeType);
      }
      slots[i] = true;
    }
    state = state.copyWith(photoSlots: slots, photoIds: ids);
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

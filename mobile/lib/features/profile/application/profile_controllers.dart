import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/secure_store.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';
import '../../../core/network/api_client.dart' show useApi;
import '../data/profile_repository_impl.dart';
import 'photo_picker.dart';
import '../domain/profile_draft.dart';

/// Holds the in-progress profile across setup screens 7–10.
class ProfileDraftController extends Notifier<ProfileDraft> {
  Timer? _saveTimer;
  bool _touched = false;

  /// Sign-up answers are kept on the device until the profile is submitted;
  /// editing an existing profile is never written there.
  bool _persist = true;

  @override
  ProfileDraft build() {
    ref.onDispose(() => _saveTimer?.cancel());
    Future.microtask(_restore);
    return const ProfileDraft();
  }

  Future<void> _restore() async {
    try {
      final raw = await ref.read(secureStoreProvider).readSetupDraft();
      if (raw == null || _touched || !_persist) return;
      final d = ProfileDraftCodec.decode(Map<String, Object?>.from(jsonDecode(raw) as Map));
      if (d == null || _touched) return;
      super.state = d;
      ref.read(draftRestoredProvider.notifier).state++;
    } catch (_) {
      // unreadable → start fresh
    }
  }

  @override
  set state(ProfileDraft value) {
    super.state = value;
    _touched = true;
    if (!_persist) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(secureStoreProvider).writeSetupDraft(jsonEncode(ProfileDraftCodec.encode(state))).ignore();
    });
  }

  /// Opens the editor on the saved profile (not a sign-up: nothing is stored on the device).
  void loadForEditing(UserProfile me) {
    _stopPersisting();
    state = ProfileDraft.fromProfile(me);
  }

  void _stopPersisting() {
    _persist = false;
    _saveTimer?.cancel();
    ref.read(secureStoreProvider).clearSetupDraft().ignore();
  }

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
    _stopPersisting(); // submitted: the server has it now
    ref.invalidate(verificationProvider);
  }

  /// Professionals: the application went out on the "about you" step and
  /// each photo is uploaded when picked; the counselor review covers both.
  Future<void> submitProfessionalPhotos() async {
    _stopPersisting();
    ref.invalidate(verificationProvider);
  }
}

final profileDraftProvider = NotifierProvider<ProfileDraftController, ProfileDraft>(ProfileDraftController.new);

/// Bumped when unfinished sign-up answers were restored from the device, so
/// the setup forms rebuild their text fields with them and say so once.
final draftRestoredProvider = StateProvider<int>((_) => 0);

final verificationProvider = FutureProvider<VerificationInfo>((ref) => ref.watch(profileRepositoryProvider).verification());

/// Demo-only: lets reviewers preview pending / rejected / approved states.
void setDemoVerification(WidgetRef ref, VerificationStatus s) {
  ref.read(demoBackendProvider).verification = s;
  ref.invalidate(verificationProvider);
}

final myProfileProvider = FutureProvider<UserProfile>((ref) => ref.watch(profileRepositoryProvider).me());

final profileByIdProvider = FutureProvider.family<UserProfile, String>((ref, id) => ref.watch(profileRepositoryProvider).profile(id));

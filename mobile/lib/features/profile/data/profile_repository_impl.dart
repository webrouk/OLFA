import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/profile_draft.dart';
import '../domain/profile_repository.dart';

class DemoProfileRepository implements ProfileRepository {
  DemoProfileRepository(this._b);
  final DemoBackend _b;

  @override
  Future<UserProfile> me() => _b.me();

  @override
  Future<UserProfile> profile(String id) => _b.profile(id);

  @override
  Future<void> submitForReview(ProfileDraft draft) {
    if (draft.gender != null) _b.myGender = draft.gender!;
    return _b.submitForReview();
  }

  @override
  Future<VerificationInfo> verification() => _b.verificationInfo();

  @override
  Future<void> updateProfile(ProfileDraft draft) => _b.submitForReview();
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => DemoProfileRepository(ref.watch(demoBackendProvider)));

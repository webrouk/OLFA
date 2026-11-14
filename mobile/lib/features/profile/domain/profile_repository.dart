import '../../../shared/models/models.dart';
import 'profile_draft.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> me();
  Future<UserProfile> profile(String id);
  Future<void> submitForReview(ProfileDraft draft);
  Future<VerificationInfo> verification();
  Future<void> updateProfile(ProfileDraft draft);
}

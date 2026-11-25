import 'dart:typed_data';

import '../../../shared/models/models.dart';
import 'profile_draft.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> me();
  Future<UserProfile> profile(String id);

  /// Creates (or updates) the profile + preferences, then submits for review.
  Future<void> submitForReview(ProfileDraft draft);
  Future<VerificationInfo> verification();
  Future<void> updateProfile(ProfileDraft draft);

  /// The saved partner preferences, applied onto [base] (only the pref* fields change).
  Future<ProfileDraft> loadPreferences(ProfileDraft base);

  /// Saves only the partner preferences (no review needed).
  Future<void> savePreferences(ProfileDraft draft);
}

/// Photo upload: presigned upload straight to private storage, then the
/// server processes and queues it for human review.
abstract interface class PhotoRepository {
  Future<String> upload({required int position, required Uint8List bytes, required String mimeType});
  Future<void> delete(String photoId);
}

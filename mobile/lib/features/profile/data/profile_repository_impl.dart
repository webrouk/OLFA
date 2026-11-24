import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/profile_draft.dart';
import '../domain/profile_repository.dart';

/// Terms version the user accepts at sign-up (bump when the terms change).
const kTermsVersion = '2026-11';

class ApiProfileRepository implements ProfileRepository, PhotoRepository {
  ApiProfileRepository(this._api);
  final ApiClient _api;
  Dio get _dio => _api.dio;

  @override
  Future<UserProfile> me() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/me');
        final p = r.data!['profile'];
        if (p == null) throw const ServerFailure('no_profile');
        final m = Map<String, dynamic>.from(p as Map);
        // Owner view lists every photo with its review state; keep approved ones for display.
        m['photos'] = (m['photos'] as List).where((x) => (x as Map)['status'] == 'APPROVED').toList();
        return ApiMappers.profile(m);
      });

  @override
  Future<UserProfile> profile(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/profiles/$id');
        return ApiMappers.profile(r.data!);
      });

  Map<String, dynamic> _profileBody(ProfileDraft d, {required bool create}) => {
        'displayName': d.name.trim(),
        if (create) 'birthDate': d.birthDate!.toIso8601String().substring(0, 10),
        if (create) 'gender': toApiEnum(d.gender!),
        'countryCode': d.countryIso,
        if (d.nationality != null) 'nationality': d.nationality,
        'city': d.city.trim(),
        'maritalStatus': toApiEnum(d.maritalStatus!),
        'education': toApiEnum(d.education!),
        'occupation': d.occupation, // reference key
        if (d.heightCm != null) 'heightCm': d.heightCm,
        if (d.weightKg != null) 'weightKg': d.weightKg,
        'marriageTimeline': toApiEnum(d.timeline!),
        if (d.religion != null) 'religion': d.religion,
        if (d.religion != null) 'sect': d.religion == 'undisclosed' ? null : d.sect,
        if (d.religion != null && d.religion != 'undisclosed') 'religionConsent': d.religionConsent,
        'bio': d.bio.trim(),
        'interests': d.interests.toList(),
        if (create) 'ageConfirmed': true,
        if (create) 'termsVersion': kTermsVersion,
      };

  @override
  Future<void> submitForReview(ProfileDraft d) => guard(() async {
        try {
          await _dio.post<void>('/me/profile', data: _profileBody(d, create: true));
        } on DioException catch (e) {
          if (e.response?.statusCode != 409) rethrow; // already created → update instead
          await _dio.patch<void>('/me/profile', data: _profileBody(d, create: false));
        }
        await _dio.put<void>('/me/preferences', data: {
          'ageMin': d.prefAgeMin,
          'ageMax': d.prefAgeMax,
          'sameCountryOnly': d.prefSameCountry,
          'maritalStatuses': d.prefMarital.map(toApiEnum).toList(),
          'wantsChildren': d.prefWantsChildren,
          'religions': d.prefReligions.toList(),
          'sects': d.prefSects.where((s) => d.prefReligions.isEmpty || d.prefReligions.contains(s.split('.').first)).toList(),
        });
        await _dio.post<void>('/me/verification/submit');
      });

  @override
  Future<VerificationInfo> verification() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/me/verification');
        final req = r.data!['request'] as Map?;
        final status = switch (req?['status']) {
          'APPROVED' => VerificationStatus.approved,
          'REJECTED' => VerificationStatus.rejected,
          _ => VerificationStatus.pending,
        };
        final selfie = r.data!['selfie'] as Map?;
        return VerificationInfo(
          status: status,
          reason: req?['rejectReason'] as String?,
          rejectCode: req?['rejectCode'] as String?,
          selfieRequired: selfie?['required'] == true,
          selfieStatus: selfie?['status'] as String?,
          selfieRejectCode: selfie?['rejectCode'] as String?,
        );
      });

  @override
  Future<void> updateProfile(ProfileDraft d) => guard(() => _dio.patch<void>('/me/profile', data: _profileBody(d, create: false)));

  @override
  Future<String> upload({required int position, required Uint8List bytes, required String mimeType}) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/me/photos/upload-url', data: {
          'position': position,
          'mimeType': mimeType,
          'bytes': bytes.length,
          'rightsConfirmed': true,
        });
        final photoId = r.data!['photoId'] as String;
        final up = Map<String, dynamic>.from(r.data!['upload'] as Map);
        // Presigned POST: fields first, file last. Sent without our auth header.
        final form = FormData.fromMap({
          ...Map<String, dynamic>.from(up['fields'] as Map),
          'file': MultipartFile.fromBytes(bytes, filename: 'photo', contentType: DioMediaType.parse(mimeType)),
        });
        await Dio().post<void>(up['url'] as String, data: form);
        await _dio.post<void>('/me/photos/$photoId/complete');
        return photoId;
      });

  @override
  Future<void> delete(String photoId) => guard(() => _dio.delete<void>('/me/photos/$photoId'));
}

class DemoProfileRepository implements ProfileRepository, PhotoRepository {
  DemoProfileRepository(this._b);
  final DemoBackend _b;
  int _seq = 0;

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
  @override
  Future<String> upload({required int position, required Uint8List bytes, required String mimeType}) async => 'demo-photo-${_seq++}';
  @override
  Future<void> delete(String photoId) async {}
}

final _profileRepoProvider = Provider<Object>(
  (ref) => useApi ? ApiProfileRepository(ref.watch(apiClientProvider)) : DemoProfileRepository(ref.watch(demoBackendProvider)),
);
final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ref.watch(_profileRepoProvider) as ProfileRepository);
final photoRepositoryProvider = Provider<PhotoRepository>((ref) => ref.watch(_profileRepoProvider) as PhotoRepository);

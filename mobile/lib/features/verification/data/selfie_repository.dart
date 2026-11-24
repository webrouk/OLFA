import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/selfie_criteria.dart';

class SelfieChallenge {
  const SelfieChallenge({required this.id, required this.gesture, required this.expiresAt, this.upload});
  final String id;
  final SelfieGesture gesture;
  final DateTime expiresAt;
  final Map<String, dynamic>? upload;
}

abstract interface class SelfieRepository {
  Future<SelfieChallenge> challenge();
  Future<void> submit(SelfieChallenge c, Uint8List jpeg, DeviceChecks checks, {required bool preferFemaleReviewer});
}

class ApiSelfieRepository implements SelfieRepository {
  ApiSelfieRepository(this._api);
  final ApiClient _api;

  @override
  Future<SelfieChallenge> challenge() => guard(() async {
        final r = await _api.dio.post<Map<String, dynamic>>('/me/verification/selfie/challenge');
        final d = r.data!;
        return SelfieChallenge(
          id: d['challengeId'] as String,
          gesture: SelfieGesture.fromApi(d['gesture'] as String?),
          expiresAt: DateTime.parse(d['expiresAt'] as String),
          upload: Map<String, dynamic>.from(d['upload'] as Map),
        );
      });

  @override
  Future<void> submit(SelfieChallenge c, Uint8List jpeg, DeviceChecks checks, {required bool preferFemaleReviewer}) =>
      guard(() async {
        final up = c.upload!;
        // presigned POST straight to private storage (no auth header); fields first, file last
        await Dio().post<void>(
          up['url'] as String,
          data: FormData.fromMap({
            ...Map<String, dynamic>.from(up['fields'] as Map),
            'file': MultipartFile.fromBytes(jpeg, filename: 'selfie.jpg', contentType: DioMediaType('image', 'jpeg')),
          }),
        );
        await _api.dio.post<void>('/me/verification/selfie', data: {
          'challengeId': c.id,
          'deviceChecks': checks.toJson(),
          'preferFemaleReviewer': preferFemaleReviewer,
        });
      });
}

class DemoSelfieRepository implements SelfieRepository {
  DemoSelfieRepository(this._b);
  final DemoBackend _b;

  @override
  Future<SelfieChallenge> challenge() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final g = SelfieGesture.values[DateTime.now().second % SelfieGesture.values.length];
    return SelfieChallenge(id: 'demo-${DateTime.now().millisecondsSinceEpoch}', gesture: g, expiresAt: DateTime.now().add(const Duration(minutes: 10)));
  }

  @override
  Future<void> submit(SelfieChallenge c, Uint8List jpeg, DeviceChecks checks, {required bool preferFemaleReviewer}) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final failed = failedDeviceChecks(checks);
    if (failed.isNotEmpty) throw SelfieChecksFailure([for (final f in failed) f.name]);
    _b.selfieSubmitted = true;
  }
}

final selfieRepositoryProvider = Provider<SelfieRepository>(
  (ref) => useApi ? ApiSelfieRepository(ref.watch(apiClientProvider)) : DemoSelfieRepository(ref.watch(demoBackendProvider)),
);

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/errors/failure.dart';
import 'package:olfa/core/network/api_errors.dart';
import 'package:olfa/shared/models/models.dart';
import 'package:olfa/shared/services/api_mappers.dart';

DioException apiError(int status, String code, [Map<String, dynamic>? details]) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: status, data: {
      'error': {'code': code, if (details != null) 'details': details},
    }),
  );
}

void main() {
  group('enum mapping matches backend names', () {
    test('Dart → API', () {
      expect(toApiEnum(MarriageTimeline.within6Months), 'WITHIN_6_MONTHS');
      expect(toApiEnum(MarriageTimeline.within1Year), 'WITHIN_1_YEAR');
      expect(toApiEnum(MaritalStatus.neverMarried), 'NEVER_MARRIED');
      expect(toApiEnum(Education.highSchool), 'HIGH_SCHOOL');
      expect(toApiEnum(Gender.female), 'FEMALE');
      expect(toApiEnum(PlanCode.premium), 'PREMIUM');
    });
    test('API → Dart round-trips every value', () {
      for (final v in MarriageTimeline.values) {
        expect(fromApiEnum(MarriageTimeline.values, toApiEnum(v), MarriageTimeline.notSure), v);
      }
      for (final v in Education.values) {
        expect(fromApiEnum(Education.values, toApiEnum(v), Education.bachelor), v);
      }
    });
  });

  test('public profile JSON → UserProfile', () {
    final p = ApiMappers.profile({
      'id': 'u1', 'displayName': 'Sara', 'age': 27, 'gender': 'FEMALE', 'countryCode': 'AE', 'city': 'Dubai',
      'maritalStatus': 'DIVORCED', 'education': 'MASTER', 'occupation': 'Architect', 'marriageTimeline': 'WITHIN_1_YEAR',
      'bio': 'b', 'interests': ['reading'], 'isPhotosReviewed': true, 'isIdentityVerified': false, 'compatibility': 88,
      'photos': [{'id': 'p1', 'thumbUrl': 't', 'cardUrl': 'c', 'fullUrl': 'f'}],
    });
    expect(p.gender, Gender.female);
    expect(p.maritalStatus, MaritalStatus.divorced);
    expect(p.timeline, MarriageTimeline.within1Year);
    expect(p.mainPhoto!.cardUrl, 'c');
    expect(p.photosReviewed, isTrue);
    expect(p.identityVerified, isFalse);
  });

  test('entitlements JSON → Entitlements', () {
    final e = ApiMappers.entitlements({
      'plan': 'PLUS',
      'likes': {'used': 3, 'limit': 100, 'remaining': 97},
      'messages': {'used': 1, 'limit': 5, 'remaining': 4},
      'undos': {'used': 0, 'limit': 3, 'remaining': 3},
      'features': {'advancedFilters': true, 'seeWhoLikedYou': true, 'incognito': false},
    });
    expect(e.plan, PlanCode.plus);
    expect(e.likesLeft, 97);
    expect(e.messagesLeft, 4);
    expect(e.advancedFilters, isTrue);
  });

  group('API errors → failures', () {
    test('quota', () => expect(toFailure(apiError(429, 'QUOTA_EXCEEDED'), quota: 'messages'), isA<QuotaExceededFailure>().having((f) => f.quota, 'quota', 'messages')));
    test('entitlement', () => expect(toFailure(apiError(402, 'ENTITLEMENT_REQUIRED', {'feature': 'advancedFilters'})), isA<EntitlementRequiredFailure>()));
    test('otp attempts', () => expect(toFailure(apiError(400, 'OTP_INVALID', {'attemptsLeft': 2})), isA<InvalidOtpFailure>().having((f) => f.attemptsLeft, 'left', 2)));
    test('cooldown carries retryAfter', () => expect(toFailure(apiError(429, 'OTP_COOLDOWN', {'retryAfter': 30})), isA<OtpRateLimitedFailure>().having((f) => f.retryAfter.inSeconds, 's', 30)));
    test('duplicate', () => expect(toFailure(apiError(409, 'DUPLICATE')), isA<AlreadyActedFailure>()));
    test('no response = offline', () => expect(toFailure(DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.connectionError)), isA<NetworkFailure>()));
  });
}

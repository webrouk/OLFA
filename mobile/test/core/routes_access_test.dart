import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/routing/routes.dart';

void main() {
  test('counselors never reach member areas', () {
    for (final loc in [Routes.discover, '/likes', '/matches', Routes.plans, '/consultations', Routes.bookCounselor('x')]) {
      expect(Routes.memberOnly(loc), isTrue, reason: loc);
    }
  });

  test('a counselor may open their own public card', () {
    expect(Routes.memberOnly(Routes.counselorDetails('k1')), isFalse);
  });

  test('counselor pages stay professional-only', () {
    for (final loc in [Routes.counselorDesk, Routes.proPerformance, Routes.proPlans, Routes.wallet]) {
      expect(Routes.professionalOnly(loc), isTrue, reason: loc);
    }
  });
}

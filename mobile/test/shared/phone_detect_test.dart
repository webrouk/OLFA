import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/shared/utils/phone_detect.dart';

void main() {
  test('detects phone numbers in Latin and Arabic-Indic digits', () {
    for (final t in ['call me +971 50 123 4567', 'رقمي 0501234567', '00966-55-123-4567', 'رقمي ٠٥٠ ١٢٣ ٤٥٦٧']) {
      expect(containsPhoneNumber(t), isTrue, reason: t);
    }
  });
  test('ignores dates, prices and short numbers', () {
    for (final t in ['see you 2026-11-14', 'on 14/11/2026', 'it cost 1500 AED', 'code 1234', '00000000']) {
      expect(containsPhoneNumber(t), isFalse, reason: t);
    }
  });
}

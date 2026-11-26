import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/shared/utils/payout_validation.dart';

void main() {
  test('IBAN check digits and lengths (same vectors as the server)', () {
    expect(isValidIban('AE07 0331 2345 6789 0123 456'), isTrue);
    expect(isValidIban('SA03 8000 0000 6080 1016 7519'), isTrue);
    expect(isValidIban('GB82 WEST 1234 5698 7654 32'), isTrue);
    expect(isValidIban('AE07 0331 2345 6789 0123 457'), isFalse);
    expect(isValidIban('AE07 0331 2345 6789 0123 45'), isFalse);
  });

  test('BIC and email', () {
    expect(isValidBic('NBADAEAA'), isTrue);
    expect(isValidBic('nbadaeaaxxx'), isTrue);
    expect(isValidBic('NBAD-AE'), isFalse);
    expect(isValidPayoutEmail('dr.huda@example.com'), isTrue);
    expect(isValidPayoutEmail('dr.huda@'), isFalse);
  });

  test('IBAN grouping', () {
    expect(formatIban('ae070331234567890123456'), 'AE07 0331 2345 6789 0123 456');
  });
}

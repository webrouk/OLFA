import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/shared/models/models.dart';

void main() {
  test('one mark: burgundy only when selfie AND ID are verified', () {
    expect(VerificationLevel.of(selfie: true, identity: true), VerificationLevel.full);
    expect(VerificationLevel.of(selfie: true, identity: false), VerificationLevel.partial);
    expect(VerificationLevel.of(selfie: false, identity: true), VerificationLevel.partial);
    expect(VerificationLevel.of(selfie: false, identity: false), VerificationLevel.none);
  });
}

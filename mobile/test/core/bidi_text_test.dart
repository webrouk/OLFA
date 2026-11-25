import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/localization/bidi_text.dart';

void main() {
  test('phone numbers are isolated, short numbers and plain text untouched', () {
    expect(isolateNumbers('رقمي 050 123 4567'), 'رقمي ⁦050 123 4567⁩');
    expect(isolateNumbers('+971 50 123 4567'), '⁦+971 50 123 4567⁩');
    expect(isolateNumbers('عمري 32'), 'عمري 32');
    expect(isolateNumbers('hello'), 'hello');
  });
}

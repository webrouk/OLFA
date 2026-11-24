import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/shared/utils/text_fold.dart';

void main() {
  test('Arabic spelling variants match', () {
    expect(foldedContains('أحمد المنصوري', 'احمد'), isTrue);
    expect(foldedContains('رسالة جميلة', 'رساله'), isTrue);
    expect(foldedContains('مصطفى', 'مصطفي'), isTrue);
    expect(foldedContains('مُحَمَّد', 'محمد'), isTrue);
    expect(foldedContains('رقمي ٠٥٠', '050'), isTrue);
    expect(foldedContains('Sara', 'sa'), isTrue);
    expect(foldedContains('سارة', 'نور'), isFalse);
  });

  test('match range points into the original text', () {
    const t = 'مرحبا أحمد!';
    final m = foldedMatch(t, 'احمد')!;
    expect(t.substring(m.start, m.end), 'أحمد');
    const h = 'يا مُحَمَّد';
    final r = foldedMatch(h, 'محمد')!;
    expect(h.substring(r.start, r.end), 'مُحَمَّد');
    expect(foldedMatch('abc', 'x'), isNull);
  });

  test('pick lists ignore French accents and use the right list separator', () {
    expect(foldForPicker('Égypte').contains(foldForPicker('egypte')), isTrue);
    expect(foldForPicker('Médecin'), 'medecin');
    expect(foldForPicker('Cœur'), 'coeur');
    expect(foldForPicker('الإمارات'), 'الامارات');
    expect(listSeparator('ar'), '، ');
    expect(listSeparator('fr'), ', ');
  });
}

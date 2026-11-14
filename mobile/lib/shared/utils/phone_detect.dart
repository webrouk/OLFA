/// Same rules as backend/src/domain/phone-detect.ts: used to warn the sender
/// before a message with a phone number goes out. The server sets the flag
/// that the other person sees, so the two always agree.
library;

const _arabic = '٠١٢٣٤٥٦٧٨٩';
const _persian = '۰۱۲۳۴۵۶۷۸۹';

String normalizeDigits(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final a = _arabic.indexOf(ch), p = _persian.indexOf(ch);
    b.write(a >= 0 ? '$a' : (p >= 0 ? '$p' : ch));
  }
  return b.toString();
}

final _candidate = RegExp(r'(?:\+|00)?\(?\d(?:[\s\-.()‏‎]{0,2}\d){6,17}');
final _isoDate = RegExp(r'^\d{4}[-./]\d{1,2}[-./]\d{1,2}$');
final _dmyDate = RegExp(r'^\d{1,2}[-./]\d{1,2}[-./]\d{2,4}$');
final _repeated = RegExp(r'^(\d)\1+$');

List<String> findPhoneNumbers(String text) {
  final out = <String>[];
  for (final m in _candidate.allMatches(normalizeDigits(text))) {
    final raw = m.group(0)!.trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8 || digits.length > 15) continue;
    if (_isoDate.hasMatch(raw) || _dmyDate.hasMatch(raw) || _repeated.hasMatch(digits)) continue;
    out.add(digits);
  }
  return out;
}

bool containsPhoneNumber(String text) => findPhoneNumbers(text).isNotEmpty;

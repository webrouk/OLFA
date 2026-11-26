/// Client-side checks for payout destinations (the server re-validates).
/// Mirrors backend/src/domain/payout.ts.
library;

const _ibanLength = {
  'AE': 23, 'SA': 24, 'QA': 29, 'KW': 30, 'BH': 22, 'OM': 23, 'JO': 30, 'EG': 29, 'LB': 28, 'IQ': 23, 'PS': 29, 'TN': 24, 'MR': 27, 'LY': 25, 'SD': 18, 'DZ': 26, 'MA': 28, 'YE': 30,
  'TR': 26, 'GB': 22, 'DE': 22, 'FR': 27, 'NL': 18, 'BE': 16, 'ES': 24, 'IT': 27, 'IE': 22, 'SE': 24, 'NO': 15, 'DK': 18, 'FI': 18, 'AT': 20, 'CH': 21, 'PT': 25, 'PL': 28, 'GR': 27, 'CY': 28, 'PK': 24, 'AZ': 28, 'GE': 22, 'KZ': 20,
};

String normalizeIban(String s) => s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

/// ISO 7064 mod-97-10 plus the per-country length.
bool isValidIban(String raw) {
  final iban = normalizeIban(raw);
  if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$').hasMatch(iban)) return false;
  final len = _ibanLength[iban.substring(0, 2)];
  if (len != null && iban.length != len) return false;
  final moved = iban.substring(4) + iban.substring(0, 4);
  var rem = 0;
  for (final ch in moved.split('')) {
    final c = ch.codeUnitAt(0);
    final v = c >= 65 && c <= 90 ? '${c - 55}' : ch;
    for (final d in v.split('')) {
      rem = (rem * 10 + int.parse(d)) % 97;
    }
  }
  return rem == 1;
}

bool isValidBic(String s) => RegExp(r'^[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?$').hasMatch(s.trim().toUpperCase());

bool isValidPayoutEmail(String s) => RegExp(r'^[^\s@]{1,64}@[^\s@]{1,190}\.[a-zA-Z]{2,}$').hasMatch(s.trim());

/// Groups an IBAN in fours for display while typing: AE07 0331 2345 …
String formatIban(String s) {
  final n = normalizeIban(s);
  final b = StringBuffer();
  for (var i = 0; i < n.length; i++) {
    if (i > 0 && i % 4 == 0) b.write(' ');
    b.write(n[i]);
  }
  return b.toString();
}

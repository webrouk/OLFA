// Bidi helpers for mixed Arabic / Latin text.

import 'package:flutter/widgets.dart';

final RegExp _numberRun = RegExp(r'\+?\d[\d\s-]{5,}\d');

/// Wraps phone-number-like digit runs in LTR isolates (U+2066 … U+2069) so
/// "رقمي 050 123 4567" keeps its digit groups in order inside an RTL sentence.
/// Display only: copy and send the original string.
String isolateNumbers(String text) =>
    text.replaceAllMapped(_numberRun, (m) => '⁦${m[0]}⁩');

/// "Sara, 27" / "سارة، 27" — Arabic uses its own comma.
String nameAge(BuildContext context, String name, int age) =>
    Localizations.localeOf(context).languageCode == 'ar' ? '$name، $age' : '$name, $age';

/// Search folding shared with the server (`olfa_fold()` / `foldForSearch()`):
/// "احمد" matches "أحمد", "رساله" matches "رسالة", "مصطفي" matches "مصطفى",
/// "٠٥٠" matches "050"; harakat and tatweel are ignored, case too.
library;

const _map = {'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ة': 'ه', 'ى': 'ي', 'ؤ': 'و', 'ئ': 'ي'};

String _foldUnit(String c) {
  final u = c.codeUnitAt(0);
  if (u == 0x0640 || (u >= 0x064B && u <= 0x0652) || u == 0x0670) return '';
  final m = _map[c];
  if (m != null) return m;
  if (u >= 0x0660 && u <= 0x0669) return '${u - 0x0660}';
  if (u >= 0x06F0 && u <= 0x06F9) return '${u - 0x06F0}';
  return c.toLowerCase();
}

String foldForSearch(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    b.write(_foldUnit(s[i]));
  }
  return b.toString();
}

/// For pick lists (countries, nationalities, occupations): also ignores Latin
/// accents, so "egypte" finds "Égypte" and "medecin" finds "Médecin".
String foldForPicker(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final ch in foldForSearch(s).split('')) {
    final i = from.indexOf(ch);
    if (ch == 'œ') {
      b.write('oe');
    } else if (ch == 'æ') {
      b.write('ae');
    } else {
      b.write(i < 0 ? ch : to[i]);
    }
  }
  return b.toString();
}

/// The list separator of the UI language ("، " in Arabic, ", " otherwise).
String listSeparator(String lang) => lang == 'ar' ? '، ' : ', ';

bool foldedContains(String text, String query) {
  final q = foldForSearch(query.trim());
  return q.isNotEmpty && foldForSearch(text).contains(q);
}

/// Where [query] matches inside [text], as indexes into the ORIGINAL text
/// (so the highlight covers "أحمد" when the user typed "احمد"). Null if none.
({int start, int end})? foldedMatch(String text, String query) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return null;
  final folded = StringBuffer();
  final origin = <int>[]; // folded index → original index
  for (var i = 0; i < text.length; i++) {
    final f = _foldUnit(text[i]);
    folded.write(f);
    for (var k = 0; k < f.length; k++) {
      origin.add(i);
    }
  }
  final at = folded.toString().indexOf(q);
  if (at < 0) return null;
  var end = origin[at + q.length - 1] + 1;
  // keep trailing harakat attached to the last matched letter
  while (end < text.length && _foldUnit(text[end]).isEmpty) {
    end++;
  }
  return (start: origin[at], end: end);
}

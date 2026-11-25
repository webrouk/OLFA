import '../models/models.dart';
import 'demo_compat_bank.dart';

/// Same scoring as the server (backend/src/domain/compat.ts), for demo mode:
/// answers are compared per topic; agreement = 1 − |a − b| / range; the score
/// is the weight-averaged agreement, 0–100. Only topics both answered count.
CompatResult scoreDemoCompat(Map<String, String> answersA, Map<String, String> answersB) {
  final byId = {for (final q in demoCompatBank) q.id: q};
  Map<String, (DemoCompatQuestion, int)> side(Map<String, String> answers) => {
        for (final e in answers.entries)
          if (byId[e.key] case final q?)
            for (final o in q.options)
              if ('o${o.$1}' == e.value) q.topic: (q, o.$1),
      };
  final a = side(answersA), b = side(answersB);
  var totalW = 0.0, totalS = 0.0, agreed = 0;
  final perDomain = <CompatDomain, (double, double)>{};
  final gaps = <(String, double, double)>[];
  for (final MapEntry(key: topic, value: (qa, va)) in a.entries) {
    final other = b[topic];
    if (other == null) continue;
    final (qb, vb) = other;
    final values = [...qa.options.map((o) => o.$1), ...qb.options.map((o) => o.$1)];
    final min = values.reduce((x, y) => x < y ? x : y), max = values.reduce((x, y) => x > y ? x : y);
    final agreement = max <= min ? (va == vb ? 1.0 : 0.0) : 1 - (va - vb).abs() / (max - min);
    final w = (qa.weight + qb.weight) / 2;
    if (va == vb) agreed++;
    if (agreement < 0.5) gaps.add((topic, agreement, w));
    totalW += w;
    totalS += w * agreement;
    final (dw, ds) = perDomain[qa.domain] ?? (0.0, 0.0);
    perDomain[qa.domain] = (dw + w, ds + w * agreement);
  }
  int pct(double s, double w) => w > 0 ? (100 * s / w).round() : 0;
  gaps.sort((x, y) => x.$2 != y.$2 ? x.$2.compareTo(y.$2) : y.$3.compareTo(x.$3));
  return CompatResult(
    score: pct(totalS, totalW),
    agreed: agreed,
    talkAbout: gaps.take(3).map((g) => g.$1).toList(),
    domains: [
      for (final d in CompatDomain.values)
        if (perDomain[d] case (final w, final s)) CompatDomainScore(domain: d, score: pct(s, w)),
    ],
  );
}

/// The questions one person answers: shared ones plus their gender's version.
List<DemoCompatQuestion> demoQuestionsFor(Gender g) =>
    demoCompatBank.where((q) => q.audience == 'ALL' || q.audience == (g == Gender.male ? 'MALE' : 'FEMALE')).toList();

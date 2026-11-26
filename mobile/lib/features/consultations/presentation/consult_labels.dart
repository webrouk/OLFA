import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';

/// Languages a consultation can be delivered in (mirrors the server list).
const kServiceLanguages = ['ar', 'en', 'fr', 'tr', 'ur', 'fa', 'de', 'es', 'id', 'ms'];
const kDurations = [30, 45, 60, 90];
const kPriceCurrencies = ['AED', 'SAR', 'QAR', 'KWD', 'BHD', 'OMR', 'JOD', 'EGP', 'MAD', 'USD', 'EUR', 'GBP'];

/// ISO-4217 exponents — the same table as backend/src/domain/payments.ts.
const kCurrencyExponent = {'AED': 2, 'SAR': 2, 'QAR': 2, 'OMR': 3, 'KWD': 3, 'BHD': 3, 'JOD': 3, 'EGP': 2, 'MAD': 2, 'USD': 2, 'EUR': 2, 'GBP': 2};

/// Integer minor units → localized amount (never floats in storage).
String money(BuildContext context, int minor, String currency) {
  final exp = kCurrencyExponent[currency] ?? 2;
  final f = NumberFormat.currency(locale: switch (langOf(context)) { 'ar' => 'ar_AE', 'fr' => 'fr', _ => 'en' }, name: currency, symbol: '$currency ', decimalDigits: exp);
  var div = 1;
  for (var i = 0; i < exp; i++) {
    div *= 10;
  }
  return f.format(minor / div);
}

/// "250.00" typed by a counselor → minor units, or null when invalid.
int? parseMinor(String text, String currency) {
  final exp = kCurrencyExponent[currency] ?? 2;
  final t = text.trim().replaceAll(',', '.');
  final m = RegExp(r'^(\d{1,7})(?:\.(\d{0,3}))?$').firstMatch(t);
  if (m == null) return null;
  final frac = (m.group(2) ?? '').padRight(exp, '0');
  if (frac.length > exp) return null;
  final v = int.parse(m.group(1)!) * _pow10(exp) + (exp == 0 ? 0 : int.parse(frac));
  return v > 0 ? v : null;
}

int _pow10(int e) => e == 0 ? 1 : 10 * _pow10(e - 1);

String serviceLabel(AppLocalizations l, ConsultationService s) => switch (s) {
      ConsultationService.premarital => l.svcPremarital,
      ConsultationService.marital => l.svcMarital,
      ConsultationService.family => l.svcFamily,
      ConsultationService.parenting => l.svcParenting,
      ConsultationService.individual => l.svcIndividual,
      ConsultationService.divorceRecovery => l.svcDivorceRecovery,
    };

String kindLabel(AppLocalizations l, CounselorKind k) => k == CounselorKind.psychologist ? l.kindPsychologist : l.kindFamilyCounselor;

String languageName(BuildContext context, String code) {
  // (Arabic, English, French)
  const names = {
    'ar': ('العربية', 'Arabic', 'Arabe'), 'en': ('الإنجليزية', 'English', 'Anglais'), 'fr': ('الفرنسية', 'French', 'Français'),
    'tr': ('التركية', 'Turkish', 'Turc'), 'ur': ('الأردية', 'Urdu', 'Ourdou'), 'fa': ('الفارسية', 'Persian', 'Persan'),
    'de': ('الألمانية', 'German', 'Allemand'), 'es': ('الإسبانية', 'Spanish', 'Espagnol'), 'id': ('الإندونيسية', 'Indonesian', 'Indonésien'),
    'ms': ('الملايوية', 'Malay', 'Malais'),
  };
  final n = names[code];
  if (n == null) return code;
  return switch (langOf(context)) { 'ar' => n.$1, 'fr' => n.$3, _ => n.$2 };
}

(String, Color, Color) statusStyle(AppLocalizations l, ConsultationStatus s) => switch (s) {
      ConsultationStatus.awaitingPayment => (l.stAwaitingPayment, OlfaColors.gray, OlfaColors.black),
      ConsultationStatus.paid => (l.stPaid, OlfaColors.primaryTint(), OlfaColors.primary),
      ConsultationStatus.confirmed => (l.stConfirmed, OlfaColors.primary, OlfaColors.white),
      ConsultationStatus.completed => (l.stCompleted, OlfaColors.black, OlfaColors.white),
      ConsultationStatus.declined => (l.stDeclined, OlfaColors.gray, OlfaColors.black),
      ConsultationStatus.cancelled => (l.stCancelled, OlfaColors.gray, OlfaColors.black),
      ConsultationStatus.refunded => (l.stRefunded, OlfaColors.gray, OlfaColors.black),
      ConsultationStatus.expired => (l.stExpired, OlfaColors.gray, OlfaColors.black),
    };

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final ConsultationStatus status;
  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = statusStyle(AppLocalizations.of(context), status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg, fontFamily: DefaultTextStyle.of(context).style.fontFamily)),
    );
  }
}

/// Five stars; the burgundy ones are filled. Read as "4.8 out of 5".
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.value, this.size = 14});
  final double value;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        label: AppLocalizations.of(context).ratingOutOf5(value.toStringAsFixed(1)),
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++)
            Icon(value >= i - 0.25 ? Icons.star_rounded : (value >= i - 0.75 ? Icons.star_half_rounded : Icons.star_outline_rounded), size: size, color: OlfaColors.primary),
        ]),
      );
}

/// Counselors have no photo: their initials (or an icon) on the burgundy tint.
class CounselorAvatar extends StatelessWidget {
  const CounselorAvatar({super.key, this.size = 56, this.name});
  final double size;
  final String? name;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty && !RegExp(r'^(د|د\.|Dr\.?|Pr\.?)$', caseSensitive: false).hasMatch(p)).toList();
    if (parts.isEmpty) return '';
    final first = parts.first.characters.first;
    return parts.length == 1 ? first : first + parts.last.characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final text = name == null ? '' : initials(name!).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: OlfaColors.primaryTint(), shape: BoxShape.circle),
        child: text.isEmpty
            ? Icon(Icons.support_agent_rounded, color: OlfaColors.primary, size: size * 0.46)
            : Text(text, style: TextStyle(color: OlfaColors.primary, fontWeight: FontWeight.w700, fontSize: size * 0.34, height: 1)),
      ),
    );
  }
}

/// "★★★★☆ 4.6 (12)" — or "New" when there are no ratings yet.
class RatingLine extends StatelessWidget {
  const RatingLine({super.key, required this.avg, required this.count, this.size = 13});
  final double avg;
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (count == 0) {
      return Text(l.noReviewsYet, style: TextStyle(fontSize: size - 1, color: OlfaColors.textMuted));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      StarRow(value: avg, size: size),
      const SizedBox(width: 6),
      Text('${avg.toStringAsFixed(1)} (${l.reviewsCount(count)})', style: TextStyle(fontSize: size - 1, color: OlfaColors.textMuted)),
    ]);
  }
}

/// The lowest-priced active offering ("from …"), or null.
CounselorOffering? cheapestOffering(Counselor c) => c.offerings.isEmpty ? null : c.offerings.reduce((a, b) => a.priceMinor <= b.priceMinor ? a : b);

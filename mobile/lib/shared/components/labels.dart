import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../core/localization/generated/app_localizations.dart';
import '../models/models.dart';

/// Localised labels for domain enums — one place, reused by every screen.
extension DomainLabels on AppLocalizations {
  String maritalLabel(MaritalStatus m) => switch (m) {
        MaritalStatus.neverMarried => maritalNever,
        MaritalStatus.divorced => maritalDivorced,
        MaritalStatus.widowed => maritalWidowed,
      };

  String educationLabel(Education e) => switch (e) {
        Education.highSchool => eduHighSchool,
        Education.diploma => eduDiploma,
        Education.bachelor => eduBachelor,
        Education.master => eduMaster,
        Education.doctorate => eduDoctorate,
      };

  String timelineLabel(MarriageTimeline t) => switch (t) {
        MarriageTimeline.within6Months => timeline6m,
        MarriageTimeline.within1Year => timeline1y,
        MarriageTimeline.within2Years => timeline2y,
        MarriageTimeline.notSure => timelineNotSure,
      };

  String planLabel(PlanCode p) => switch (p) {
        PlanCode.free => planFree,
        PlanCode.plus => 'Plus',
        PlanCode.premium => 'Premium',
      };
}

String langOf(BuildContext context) => Localizations.localeOf(context).languageCode;

/// A language's own name (shown the same in every UI language, as iOS and
/// Android do) and its name in the current UI language.
const kNativeLanguageNames = {'ar': 'العربية', 'en': 'English', 'fr': 'Français'};
String languageNameIn(String uiLang, String code) => switch (uiLang) {
      'ar' => const {'ar': 'العربية', 'en': 'الإنجليزية', 'fr': 'الفرنسية'}[code]!,
      'fr' => const {'ar': 'Arabe', 'en': 'Anglais', 'fr': 'Français'}[code]!,
      _ => const {'ar': 'Arabic', 'en': 'English', 'fr': 'French'}[code]!,
    };

String interestLabel(BuildContext context, String key) => interestByKey(key)?.label(langOf(context)) ?? key;

String countryLabel(BuildContext context, String iso) => countryByIso(iso).label(langOf(context));

/// Relative / clock time formatted for the active locale (Latin digits).
String shortTime(BuildContext context, DateTime t) {
  final locale = langOf(context);
  final now = DateTime.now();
  final sameDay = now.year == t.year && now.month == t.month && now.day == t.day;
  if (sameDay) return DateFormat.Hm(locale).format(t);
  if (now.difference(t).inDays < 7) return DateFormat.E(locale).format(t);
  return DateFormat.yMd(locale).format(t);
}

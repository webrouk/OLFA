# OLFA — Flutter app (iOS & Android)

## التشغيل

```bash
cd mobile
flutter create . --org com.olfa --project-name olfa --platforms ios,android,web   # first time only: generates native folders
bash scripts/fetch_fonts.sh        # Tajawal + Montserrat (SIL OFL)
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
flutter run -d chrome              # Live preview with Hot Reload (press r)
flutter run                        # iOS Simulator / Android Emulator
```

## البنية (Feature-First + Clean Architecture)

```
lib/
  app/                 MaterialApp.router, theme + locale wiring
  core/
    theme/             Design tokens: colours, typography, spacing, radius, Material 3 theme
    localization/      ARB (ar, en) + locale provider
    routing/           GoRouter: 26 route ids + floating-nav tab shell
    network/           Dio client (base URL via --dart-define)
    security/          Secure token storage
    errors/            Failure types
    widgets/           Shared components (logo, buttons, nav bar, states…)
  features/<feature>/  presentation/ (later: data/, domain/)
  shared/              Cross-feature models, services, components
test/                  Widget tests
```

## حالة الشاشات

| الحالة | الشاشات |
|---|---|
| منفّذة في Flutter | Splash, Onboarding, Language (يبدّل RTL/LTR فورًا), Phone, OTP, Age, Gender, Discover (سحب + Like/Pass/Undo) + الشريط السفلي العائم |
| مسارات مسجّلة بصفحة "قيد التنفيذ" | الشاشات الـ18 المتبقية — تصميمها المعتمد في `../preview/index.html` |

## ملاحظات

- لم يُشغَّل `flutter analyze` / `flutter test` بعد: بيئة إنشاء المستودع لا تحتوي Flutter SDK. شغّلهما محليًا وأبلغني بأي خطأ.
- Firebase وIn-App Purchase مؤجلة للمرحلة 3، لأنها تحتاج ملفات إعداد المشروع (`GoogleService-Info.plist` و`google-services.json`).

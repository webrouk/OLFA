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
  app/                         MaterialApp.router, theme + locale wiring
  core/
    theme/                     Design tokens: colours, typography, spacing, radius, Material 3 theme
    localization/              ARB (ar, en, fr) — 1029 keys, locale provider (phone language, else English)
    routing/                   GoRouter: 26 route ids + floating-nav tab shell
    network/ security/ errors/ Dio client, secure token store, typed Failures
    widgets/                   Component library (see below)
  shared/
    models/                    Domain models + JSON mapping (UserProfile, Entitlements, ChatMessage…)
    services/demo_backend.dart In-memory API stand-in that enforces server rules (Phase 2 only)
    components/                ProfileCard, SubscriptionCard, enum labels
  features/<feature>/
    domain/                    Repository interfaces, use cases
    data/                      Repository implementations (Demo* now → HTTP in Phase 3) + providers
    application/               Riverpod controllers (Notifier / AsyncNotifier)
    presentation/              Screens
test/
  core/                        Component tests (buttons, OTP, nav bar RTL/LTR, 1.3× text)
  features/                    Business-rule tests (quotas, entitlements, duplicates, blocking, idempotent send)
  screens/                     Opens all 26 screens × ar/en × 3 device sizes, fails on any overflow/exception
```

## مكتبة المكونات (`core/widgets` + `shared/components`)

PrimaryButton · SecondaryButton · OlfaIconButton · ProfileCard · OlfaAvatar · VerifiedBadge · OlfaTextField · PhoneInput · OtpInput · FloatingNavBar · SubscriptionCard · EmptyState · ErrorState · LoadingSkeleton / OlfaSkeleton · showConfirmation · showToast · AsyncView · FormPage · TileGroup / OlfaListTile · ChoiceWrap / OlfaChoice · OlfaStepper · InfoBanner · OlfaTag · OlfaImage (cache + decode size + fallback) · PressScale (reduce-motion aware)

## حالة الشاشات — المرحلة 2

جميع الصفحات الـ26 منفذة وتعمل على مصدر بيانات تجريبي (`DemoBackend`) يطبّق قواعد الخادم نفسها:

| المجموعة | الشاشات |
|---|---|
| A. التسجيل | Splash · Onboarding · Language (RTL/LTR فوري) · Phone (اختيار الدولة) · OTP (لصق/ملء تلقائي، عداد إعادة الإرسال، الخطأ والقفل) · Age 18+ |
| B. إعداد الملف | Gender · Profile info (تحقق على مستوى الحقل) · Partner preferences · Photos · Verification (معلّق/مرفوض/معتمد) |
| C. الاكتشاف | Discover (سحب، Optimistic UI، منع التكرار، تحميل مسبق، Undo حسب الخطة، Match) · Profile details (معرض صور) · Search & filters (حسب الصلاحيات) · Likes · Matches · My profile |
| D. التواصل | Conversations · Chat (Pagination، مؤشر الكتابة، حالة القراءة، إعادة الإرسال، Offline) · Notifications |
| E. الحساب | Edit profile · Plans · Payment history · Privacy & security · FAQ & help (تذكرة دعم) · Settings & account deletion |

أدوات معاينة تجريبية: مبدّل حالات التوثيق في الشاشة 11، و"محاكاة انقطاع الاتصال" في شاشة الخصوصية.

## ملاحظات

- **لم يُشغَّل `flutter analyze` / `flutter test` بعد**: بيئة إنشاء المستودع لا تحتوي Flutter SDK. شغّلهما محليًا وأرسل أي خطأ.
- الصور حاليًا Placeholders (لا توجد روابط صور في الوضع التجريبي)؛ اختيار الصور ورفعها (image_picker + ضغط + Presigned URL) في المرحلة 3.
- Firebase وIn-App Purchase مؤجلة للمرحلة 3.

## الأمان والتحقق (الدفعة 8)

- **حماية صور الأعضاء من لقطات الشاشة** (`core/security/screen_protection.dart`، حزمة `screen_protector`):
  - أندرويد: FLAG_SECURE على التطبيق كله، فتخرج لقطات الشاشة والتسجيل سوداء، ولا تظهر المعاينة في قائمة التطبيقات.
  - iOS: طبقة آمنة تجعل لقطة الشاشة فارغة، وغطاء كامل أثناء تسجيل الشاشة أو بثّها (`CaptureShield`)، وتمويه في قائمة التطبيقات.
  - حدود صريحة: لا يمكن منع التصوير بكاميرا جهاز آخر، والأجهزة المكسورة الحماية (root/jailbreak) قد تتجاوز النظام.
- **سيلفي التحقق** بعد الصور في أول تسجيل (`features/verification`): ثمانية معايير مكتوبة، وإشارة يد عشوائية لمرة واحدة، وفحص الوجه على الجهاز بـ ML Kit دون إرسال الصورة إلى Google، ثم فحص الخادم، ثم مراجعة فريق التحقق. التفاصيل في [docs/VERIFICATION.md](../docs/VERIFICATION.md).
- **الحساب المغلق** (`features/account/closed_account_screen.dart`): إغلاق نهائي أو حتى تاريخ محدد، مع السبب وإمكانية مراسلة الدعم.

> تحتاج الحزم الجديدة `screen_protector` و`google_mlkit_face_detection` و`file_picker` إلى `flutter pub get`. يتطلب ML Kit حدًا أدنى iOS 15.5 / Android minSdk 21.

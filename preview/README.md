# OLFA — Live Preview (Interactive Prototype)

نموذج تفاعلي لجميع صفحات التطبيق الـ26 ولوحة التحكم بأقسامها الـ12، في ملف واحد بدون أي اعتماديات.

## التشغيل
افتح `preview/index.html` مباشرة في المتصفح، أو:
```bash
npx serve preview   # أو: python3 -m http.server -d preview 8080
```

## المزايا
- التبديل بين **التطبيق** و**لوحة التحكم**.
- **العربية RTL / English LTR** مع قلب الاتجاه والأيقونات الاتجاهية.
- مقاسات: iPhone SE، iPhone 15 Pro، 15 Pro Max، Pixel 8، Galaxy A صغير، iPad mini — مع Safe Areas وDynamic Island / Punch-hole.
- عرض **صفحة واحدة** تفاعلية أو **كل الصفحات** دفعة واحدة.
- تفاعل فعلي: Swipe بالسحب، Match، محادثة، OTP، رفع الصور، الخطط، الحذف، البلاغ.
- تعديل حصص الخطط من لوحة التحكم ينعكس فورًا على شاشة الخطط في التطبيق.
- روابط مباشرة: `index.html#lang=en&s=discover&dev=px` أو `#mode=admin&adm=ver`.

> جميع البيانات المعروضة تجريبية. هذا النموذج مرجع التصميم المعتمد لتنفيذ Flutter في `mobile/`.

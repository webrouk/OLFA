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

## v0.8
- **Verification selfie** (`#s=selfie`): mandatory after the photos at first sign-up. It shows the 8 written criteria, the random gesture, the automatic check (with a "simulate a failed selfie" demo), sending to the team, and the selfie status on the verification page.
- **Closed account** (`#s=closed`): permanent or temporary (until a date), with the reason and a message to support.
- **Escrow**: the "Did the consultation take place?" question in the review (No → report to support, the fee stays held). The wallet shows *available / held / under review* and how a fee reaches the wallet.
- **Schedules**: booking picks one of the counselor's free times (`#s=book`); the counselor manages hours, booking rules and time off (`#s=schedule`), and ratings with replies (`#s=creviews`).
- **Support** (`#s=faq`): FAQ in all three languages, my requests, a new request with attachments (`#s=newticket`), and the conversation with support on the same page with a reply (`#s=ticket`).
- **Chat**: "slide to cancel" and "stop and listen before sending" for voice messages.
- **Privacy**: a note on photo protection from screenshots.

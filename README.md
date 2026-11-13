# أُلْفَة | OLFA

**Serious Dating & Marriage Platform** — منصة عالمية للتعارف الجاد بهدف الزواج.

| المكوّن | التقنية | المسار |
|---|---|---|
| تطبيق iOS / Android | Flutter | `mobile/` |
| Backend API + WebSockets | NestJS + Prisma | `backend/` |
| لوحة تحكم الإدارة | Next.js (App Router) | `admin/` |
| قاعدة البيانات | PostgreSQL 16 | `backend/prisma/schema.prisma` |
| التخزين المؤقت والحصص | Redis 7 | — |
| الإشعارات | Firebase Cloud Messaging | — |
| الصور والملفات | S3-compatible Storage + CDN | — |

## الحالة الحالية

**المرحلة 1 — التأسيس والهوية والمعاينة الحية** (بانتظار الاعتماد)

- **معاينة حية تفاعلية** لجميع الصفحات الـ26 ولوحة التحكم بأقسامها الـ12 (عربي RTL / إنجليزي LTR، 6 مقاسات أجهزة): [`preview/index.html`](preview/).
- **أساس Flutter** في [`mobile/`](mobile/): Design Tokens، Typography، Material 3 theme، المكونات المشتركة، الشريط السفلي العائم، الترجمة ARB، GoRouter لـ26 مسارًا، 8 شاشات منفذة، اختبارات Widgets.
- **أصول الهوية** في [`mobile/assets/brand/`](mobile/assets/brand/).
- **مخطط قاعدة البيانات** (Prisma) في [`backend/prisma/schema.prisma`](backend/prisma/schema.prisma).
- **الوثائق**: PRD وSystem Architecture.

## الوثائق

1. [PRD — وثيقة متطلبات المنتج](docs/01-PRD.md)
2. [System Architecture](docs/02-system-architecture.md)
3. Database ERD · API · Matching · Subscriptions · Security · Roadmap — قيد الإعداد (المرحلة 2)

## التشغيل المحلي (بعد المرحلة 3)

```bash
cp .env.example .env
docker compose up -d          # PostgreSQL + Redis + MinIO
cd backend && npm i && npx prisma migrate dev && npm run start:dev
cd admin && npm i && npm run dev
cd mobile && bash scripts/fetch_fonts.sh && flutter pub get && flutter run -d chrome
```

## قواعد التطوير الإلزامية

الالتزام بالهوية (4 ألوان فقط، بدون Gradients أو 3D)، وعدم ترك أزرار شكلية، وعدم وضع مفاتيح أو كلمات مرور داخل الكود، واختبار كل مرحلة قبل الانتقال إلى التالية.

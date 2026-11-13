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

**المرحلة 1 — Product Architecture & System Planning (Script 01)**: بانتظار الاعتماد.

وفق قاعدة Script 01: *ممنوع البدء بكتابة كميات كبيرة من الأكواد قبل اعتماد البنية المعمارية.*
لذلك يحتوي المستودع حاليًا على:

- الوثائق المعمارية العشر في [`docs/`](docs/).
- مخطط قاعدة البيانات الكامل (Prisma) في [`backend/prisma/schema.prisma`](backend/prisma/schema.prisma).
- الهيكل الأولي للمشاريع الثلاثة (بدون منطق أعمال بعد).
- Design Tokens للهوية البصرية في `mobile/lib/core/theme/` و`admin/src/styles/`.

## الوثائق

1. [PRD — وثيقة متطلبات المنتج](docs/01-PRD.md)
2. [System Architecture](docs/02-system-architecture.md)
3. [Database ERD](docs/03-database-erd.md)
4. [API Architecture](docs/04-api-architecture.md)
5. [User Journey](docs/05-user-journey.md)
6. [Matching Algorithm](docs/06-matching-algorithm.md)
7. [Subscription Architecture](docs/07-subscription-architecture.md)
8. [Security Architecture](docs/08-security-architecture.md)
9. [Project Folder Structure](docs/09-folder-structure.md)
10. [Development Roadmap](docs/10-roadmap.md)
11. [سجل القرارات التقنية ADR](docs/adr/)

## التشغيل المحلي (بعد المرحلة 3)

```bash
cp .env.example .env
docker compose up -d          # PostgreSQL + Redis + MinIO
cd backend && npm i && npx prisma migrate dev && npm run start:dev
cd admin && npm i && npm run dev
cd mobile && flutter pub get && flutter run
```

## قواعد التطوير الإلزامية

راجع [`docs/10-roadmap.md#global-development-rules`](docs/10-roadmap.md#global-development-rules).

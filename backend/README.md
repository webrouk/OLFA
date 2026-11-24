# OLFA — Backend (NestJS · PostgreSQL · Redis)

Modular monolith: `auth`, `profiles`, `media` (+ worker), `verification`, `matching` (discovery, likes, matches), `quotas` (entitlements), `messaging` (REST + Socket.IO), `notifications` (FCM), `safety`, `admin` (RBAC).

```
src/
  domain/          pure, framework-free logic (matching engine, quota windows, OTP/crypto) — unit-tested
  common/          infra (Prisma, Redis, rate limiter, settings, audit), guards, errors, request logging
  modules/<name>/  controllers, services, DTOs
  modules/matching/sql/candidates.sql   the discovery query (tested against PostgreSQL)
  main.ts          API · worker.ts  background jobs (image processing)
prisma/
  migrations/…/migration.sql   canonical DDL + olfa_like / olfa_consume_quota
  schema.prisma                mirrors the DDL (checked by test/db/check_prisma_vs_db.py)
  seed.sql                     plans, quotas, interests, roles/permissions, settings (idempotent)
```

## Run locally

```bash
cp .env.example .env                       # from the repo root; fill secrets (openssl rand -base64 48)
docker compose up -d --build               # postgres, redis, minio (+ buckets), api, worker
docker compose exec api npx prisma migrate deploy
docker compose exec api sh -c 'psql "$DATABASE_URL" -f prisma/seed.sql'
open http://localhost:3000/docs            # Swagger
```

With `SMS_PROVIDER=log` the OTP is printed in the API log (`docker compose logs -f api`). Refused in production.

Create the first admin:

```bash
docker compose exec api node -e "require('argon2').hash(process.argv[1]).then(console.log)" 'a-long-password'
docker compose exec postgres psql -U olfa -c "WITH a AS (INSERT INTO admin_users(email,name,password_hash) VALUES ('you@olfa.app','You','<hash>') RETURNING id) INSERT INTO admin_user_roles SELECT a.id, r.id FROM a, roles r WHERE r.key='super_admin';"
```

Point the app at it: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` (Android emulator) or `http://localhost:3000` (iOS simulator / web).

> Use `prisma migrate deploy` (applies the SQL files). Do not run `prisma migrate dev` against shared databases: the schema has partial indexes and SQL functions that Prisma's diff does not model.

## Tests

| Suite | Command | Needs |
|---|---|---|
| Domain + image pipeline (unit) | `npm run test:unit` | Node 22 |
| Database (constraints, SQL functions, concurrency, discovery query, Prisma ↔ DB) | `PGHOST=… PGUSER=… npm run test:db` | PostgreSQL 16 |
| Redis rate limiter | `bash test/redis/rate_limit_test.sh` | Redis 7 |
| API / authorization end-to-end | `npm run test:e2e` | `docker compose up postgres redis` |

## Environment

All variables are validated at boot (`src/config/env.ts`); the API refuses to start with missing or weak secrets. See `/.env.example`.

Added for professional accounts and store subscriptions (values come from the secret manager, never the repo):

| Variable | Purpose |
|---|---|
| `IDENTITY_HMAC_SECRET` | HMAC key for fingerprints of permanently banned phones, devices, licences and payout accounts |
| `PAYOUT_ENC_KEY` | AES-256-GCM key (32 bytes, base64) for counselors' payout account details |
| `APPLE_BUNDLE_ID`, `APPLE_ROOT_CA_PATH`, `APPLE_ALLOW_SANDBOX` | StoreKit 2 JWS verification |
| `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` | App Store Server API |
| `GOOGLE_PACKAGE_NAME`, `GOOGLE_SERVICE_ACCOUNT_JSON`, `GOOGLE_RTDN_TOKEN` | Play Developer API and the RTDN push endpoint |

Store-side setup still needed before launch: create the subscription products (`olfa.plus.monthly`, `olfa.premium.monthly` in one App Store subscription group; `olfa_plus`, `olfa_premium` on Google Play), point App Store Server Notifications v2 to `/v1/subscriptions/apple/notifications`, and create the Pub/Sub push subscription for RTDN to `/v1/subscriptions/google/rtdn?token=…`.

# 04 — API Reference (v1)

Base URL `https://<host>/v1`. JSON only. Interactive OpenAPI/Swagger at `/docs` (non-production), raw spec at `/docs/openapi.json`.

## Conventions

- **Auth**: `Authorization: Bearer <accessToken>` (JWT, 15 min). Refresh with `POST /auth/refresh` — tokens rotate; replaying an old refresh token revokes the whole device family.
- **Language**: `Accept-Language: ar|en` (SMS text, server-rendered pushes).
- **Validation**: unknown fields are rejected (`400`), all inputs validated (class-validator).
- **Account state**: endpoints marked *pending OK* work before approval (profile setup); everything else needs an `ACTIVE` account.
- **Errors** — always:
  ```json
  { "error": { "code": "QUOTA_EXCEEDED", "message": "…", "details": { }, "requestId": "…" } }
  ```

| code | HTTP | meaning |
|---|---|---|
| `VALIDATION` | 400 | bad input (`details.field`) |
| `UNAUTHORIZED` | 401 | missing/expired/revoked token |
| `FORBIDDEN` / `ACCOUNT_NOT_ACTIVE` / `BLOCKED` | 403 | not allowed |
| `NOT_FOUND` | 404 | also returned for resources you may not see (no IDOR leaks) |
| `CONFLICT` / `DUPLICATE` | 409 | already exists / already liked |
| `NOT_ELIGIBLE` / `UNDERAGE` | 422 | outside mutual preferences / under 18 |
| `ENTITLEMENT_REQUIRED` | 402 | paid feature (`details.feature`) |
| `QUOTA_EXCEEDED` / `RATE_LIMITED` / `OTP_COOLDOWN` / `OTP_LOCKED` | 429 | `details.retryAfter` when known |
| `OTP_INVALID` / `OTP_EXPIRED` | 400 | `details.attemptsLeft` |

## Authentication

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/auth/otp/request` | public | `{dialCode, nationalNumber, country, deviceId}` → `{challengeId, expiresInSeconds, resendAfterSeconds}`. Limits: 3/10 min per phone, 10/h per IP and per device, 45 s cooldown. |
| POST | `/auth/otp/verify` | public | `{challengeId, code, deviceId, platform, timezone?, locale?}` → tokens + `isNewUser`, `accountStatus`, `profileComplete`. 5 wrong attempts lock the challenge; code expires after 5 min; single use. |
| POST | `/auth/refresh` | public | `{refreshToken}` → new pair (rotation). |
| POST | `/auth/logout` | user · pending OK | revokes this device session. |
| GET | `/auth/sessions` | user · pending OK | signed-in devices. |
| DELETE | `/auth/sessions/:id` | user · pending OK | revoke a device. |
| PUT | `/auth/push-token` | user · pending OK | `{fcmToken}` for this device. |

## Profile & verification

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/me` | pending OK | owner view (phone, birth date, every photo with review status, preferences). |
| POST | `/me/profile` | pending OK | create — 18+ enforced server-side, `ageConfirmed: true`, `termsVersion`. |
| PATCH | `/me/profile` | pending OK | update; gender/birth date immutable; a name change on a live account waits for review. |
| PUT | `/me/preferences` | pending OK | partner preferences (hard filters); invalidates cached scores. |
| DELETE | `/me` | pending OK | request deletion: hidden immediately, all sessions revoked, purge after 30 days; signing in within 30 days restores. |
| GET | `/profiles/:id` | user | **public view**: no phone, no birth date, approved CDN photos only, location only if allowed, `isIdentityVerified` only from an ID check. |
| GET | `/interests` | public | catalogue (ar/en). |
| POST | `/me/photos/upload-url` | pending OK | `{position, mimeType, bytes, rightsConfirmed: true}` → presigned POST to **private** storage (type and max size bound into the signature). |
| POST | `/me/photos/:id/complete` | pending OK | queue processing (magic-byte check, EXIF strip, WebP variants, perceptual hash, moderation scan) → `PENDING_REVIEW`. |
| DELETE | `/me/photos/:id` | pending OK | soft delete + unpublish from CDN. |
| PUT | `/me/photos/order` | pending OK | `{photoIds[]}` |
| POST | `/me/verification/submit` | pending OK | `PENDING` review request (needs profile + ≥2 processed photos). |
| GET | `/me/verification` | pending OK | status, reject code/reason, badges (`photosReviewed`, `realPerson`, `identityVerified`), `canResubmit`. |

## Discovery, likes, matches

| Method | Path | Notes |
|---|---|---|
| GET | `/discovery?limit&ageMin&ageMax&countryCode&city&interests` | **Paid filters** `maritalStatuses, educations, occupation, minCompatibility`, multiple/non-basic interests → `402` on Free. Returns ranked public profiles with `compatibility`; each is recorded as shown (not repeated within the cooldown). |
| POST | `/likes` `{userId}` | account → mutual preferences → quota (atomic) → duplicate → save → mutual check → match (same transaction, per-pair lock) → notify both. `{matched, matchId, likesRemaining}` |
| POST | `/passes` `{userId}` | resurfaces after `matching.passResurfaceDays`. |
| POST | `/undo` `{userId}` | plan-limited (`daily_undos`); cannot undo a match. |
| GET | `/likes/received` | `{count, locked, profiles}` — identities only with `see_who_liked_you`. |
| GET | `/matches` | active matches with peer + `conversationId`. |
| POST | `/matches/:id/conversation` | starts the chat — spends 1 daily message credit, once per match (concurrent starts resolve to one conversation). |
| DELETE | `/matches/:id` | unmatch. |

## Quotas & plans

| Method | Path | Notes |
|---|---|---|
| GET | `/me/entitlements` | plan, features, `{likes, messages, undos}: {used, limit, remaining}`, `resetsAt` (UTC instant of the user's next local midnight). **The app's only source of truth.** |
| GET | `/plans` | public plan list + features + store product ids. Prices come from App Store / Google Play. |
| GET | `/me/payments` | payment history. |

Defaults (admin-editable, no app release needed): Free 10 likes / 1 message credit · Plus 100 / 5 · Premium 200 / 10.

## Messaging

REST: `GET /conversations`, `GET /conversations/:id/messages?before&limit`, `POST /conversations/:id/messages {clientMessageId (UUID), body}` (idempotent), `POST /conversations/:id/read`.

Realtime — Socket.IO namespace **`/chat`**, connect with `{ auth: { token: <accessToken> } }`:

| direction | event | payload |
|---|---|---|
| → server | `message:send` | `{conversationId, clientMessageId, body}` → ack `{ok, message}` / `{ok:false, error:{code}}` |
| → server | `typing` | `{conversationId, on}` |
| → server | `read` | `{conversationId}` |
| ← client | `message:new` | `{conversationId, message}` |
| ← client | `message:read` | `{conversationId, readerId, at}` |
| ← client | `typing` | `{conversationId, userId, on}` |

Messages consume quota per `chat.messagesConsumeCredit` (`start_only` default; or `every_message`) and a per-conversation anti-spam limit (`chat.continuationDailyLimit`). Blocked pairs cannot exchange messages.

## Safety & notifications

`GET/POST /blocks`, `DELETE /blocks/:userId`, `POST /reports {userId, reason, targetType?, targetId?, details?, block?}` (prioritised queue), `GET /notifications`, `POST /notifications/read-all`.

## Admin (RBAC)

Admin JWTs are separate (`POST /admin/auth/login`). Every admin route declares the permissions it needs; every change is written to `audit_logs`.

| Method | Path | Permission |
|---|---|---|
| GET | `/admin/verification/queue` | `verification.review` |
| GET | `/admin/verification/:id` | `verification.review` (photos via 5-minute signed private URLs) |
| POST | `/admin/verification/:id/approve` `{rejectPhotoIds?}` | `verification.review` — publishes photos to CDN, grants badge, activates account, notifies |
| POST | `/admin/verification/:id/reject` `{code, reason, photoIds?}` | `verification.review` — stores reason, notifies, allows resubmission |
| GET/PUT | `/admin/matching/weights` | `settings.manage` (versioned) |
| GET | `/admin/plans` · PUT `/admin/plans/:code/entitlements` | `plans.manage` |
| GET | `/admin/settings` · PUT `/admin/settings/:key` | `settings.manage` |

## Health

`GET /health/live`, `GET /health/ready` (DB + Redis).

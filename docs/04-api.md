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

### Photos, voice notes, phone safety, search (Nov 2026)

| method | path | notes |
|---|---|---|
| POST | `/conversations/:id/attachments {kind: IMAGE\|VOICE, mime, bytes, durationMs?, waveform?}` | returns a presigned S3 POST (private bucket). Photos ≤ 3 per message, compressed on device (≤2048 px, q86, EXIF stripped) and re-sanitised by the `chat-image` worker job. Voice ≤ 60 s, AAC-LC. |
| POST | `/conversations/:id/messages {clientMessageId, body?, attachmentIds?}` | `body` may be empty when attachments exist. DB trigger `olfa_attachment_guard` rejects >3 photos, more than one voice, or mixing (SQLSTATE P0020). |
| GET | `/conversations/:id/voice-quota` | `{used, limit}` — entitlement `voice_notes_per_conversation`: Free 10, Plus 30, Premium unlimited (-1). |
| GET | `/conversations/search?q=` | one field: partner names and message text, photo captions included. Arabic-aware via `olfa_fold()` (أ/إ/آ = ا, ة = ه, ى = ي, ؤ = و, ئ = ي, harakat/tatweel ignored, Arabic digits = 0-9) on trigram expression indexes; returns `{conversations[], messages[]}`. |

`GET /conversations` returns each row's `unread` (one grouped query) and `lastMessage {body, type, senderId, mine}`. `POST /conversations/:id/read` is called when a chat opens and when a message arrives while it is open; the `message:read` event goes to the reader's own devices (to clear badges — clients must not treat it as the peer reading) and to the peer only when both keep read receipts on. `typing` is only relayed where a message could be sent (not unmatched or closed chats).

Messages carry `containsPhone` (server-side detection, Arabic-Indic digits included). Clients show a safety note to both sides; the sender is warned before sending. Attachment URLs are short-lived signed GETs. Read receipts respect the reader's privacy setting (reciprocal).

## Safety & notifications

`GET/POST /blocks`, `DELETE /blocks/:userId`, `POST /reports {userId, reason, targetType?, targetId?, details?, block?}` (prioritised queue; `targetType: MESSAGE` stores a snapshot of the reported message for moderators), `GET /notifications`, `GET /notifications/unread-count`, `POST /notifications/:id/read`, `POST /notifications/read-all`, `DELETE /notifications/:id`.

Push sounds: APNs `sound` and Android channels `olfa_messages` / `olfa_matches` / `olfa_general` use OLFA's own tones (`message.wav`, `match.wav`, `notification.wav`).

## Account, privacy & payments

| method | path | notes |
|---|---|---|
| GET/PUT | `/me/privacy` | visibility, incognito (Premium), online status and read receipts (both reciprocal), blur photos, show city — enforced by the server in discovery, presence and receipts. |
| GET | `/auth/sessions` · DELETE `/auth/sessions/:id` | signed-in devices (one session per device). |
| POST | `/me/freeze` · `/me/unfreeze` | hides the account everywhere; data, matches, chats and the store subscription are kept. |
| GET | `/me/export` | JSON copy of the user's data. |
| GET | `/me/payments?cursor=` | subscriptions and consultation payments/refunds, newest first. |
| POST | `/likes {toUserId, compliment?}` | compliment ≤ 300 chars; entitlement `monthly_compliments`: Free 3, Plus 10, Premium 20. |

Discovery filters accept `heightMin/heightMax` (cm) and `weightMin/weightMax` (kg).

## Account types (Nov 2026)

`PUT /me/account-type {type: MEMBER|PSYCHOLOGIST|FAMILY_COUNSELOR}` — chosen once at sign-up, after the gender step (which now also takes `heightCm` / `weightKg`). A DB trigger locks it once a profile exists (`account_type_locked`). Members get discovery, likes, matches, preferences and plans; professionals get the counselor desk, wallet and client chats. Member-only routes answer `wrong_account_type` to professionals and vice versa; professionals never appear in discovery and can't be liked.

Sign-up order — member: gender + height/weight → account type → about you (incl. religion & sect) → partner preferences → location → photos. Professional: gender + height/weight → account type → about your practice (licence, services, policy acceptance) → location → photo.

## Religion & sect

Reference keys come from `shared/reference/religions.tsv` (`GET /reference` includes them). Profile: `religion`, `sect` (must belong to the religion; consent required, `undisclosed` allowed). Preferences: `religions[]`, `sects[]` (`religion.sect`; a sect is only accepted under a chosen religion). Discovery filters: `religions=islam,christianity&sects=christianity.maronite` — a religion with no sect selected matches all of its sects; `undisclosed` profiles are excluded only when a religion filter is set.

## Professional wallet

| method | path | notes |
|---|---|---|
| GET | `/wallet` | balances per currency: available, pending (released `wallet.holdDays` after each completed session, default 7), minimum withdrawal, gross / fee / net totals, `payoutsOnHold` while an integrity case is open. |
| GET | `/wallet/entries?cursor=` | immutable ledger: EARNING (gross, fee, net), EARNING_REVERSAL (refund), WITHDRAWAL, WITHDRAWAL_RETURN, ADJUSTMENT. |
| GET/POST/DELETE | `/wallet/payout-methods` | IBAN, SWIFT, Wise, PayPal, Payoneer. Details AES-256-GCM encrypted (`PAYOUT_ENC_KEY`), only a mask is returned; fingerprints of banned accounts are refused. |
| GET/POST | `/wallet/withdrawals` · POST `/wallet/withdrawals/:id/cancel` | one open request per currency; the DB refuses a debit above the available balance. |

The fee is snapshotted on each consultation (`consultations.platformFeePercent`, default 15). The earning is written by a DB trigger when a consultation completes, and reversed on refund.

Admin: `GET /admin/withdrawals`, `POST /admin/withdrawals/:id/processing|paid|reject|failed` (failed/rejected return the money), `POST /admin/wallets/:counselorId/adjust`.

## Post-consultation questionnaire & integrity

`GET /consultations/pending-review` · `POST /consultations/:id/review` — mandatory before the member can book again (DB trigger, `review_required`). It asks for 5 ratings (overall, treatment, commitment, effectiveness, outcome), whether another session was agreed and where, and three safety questions: contact details shared, payment asked outside OLFA, invitation to another app. Answers are confidential; the counselor sees only the overall rating.

Direct and indirect answers, plus phone numbers detected in consultation chats, become `counselor_integrity_signals`. Each (client, kind) counts once; a case opens when the 90-day score reaches 12 from at least 2 different clients. The counselor is notified, withdrawals pause, and they respond through `GET /counselors/me/integrity` and `POST /counselors/me/integrity/:id/respond`. A human decides via `POST /admin/integrity/cases/:id/decide {decision: CLEAR|WARN|SUSPEND|BAN, reason}`.

A permanent ban stores HMAC fingerprints (`IDENTITY_HMAC_SECRET`) of the phone, devices, licence and payout accounts in `banned_identities`. OTP requests, new accounts on a banned device, counselor applications with a banned licence and banned payout accounts are refused (`account_banned`).

## Store subscriptions

| method | path | notes |
|---|---|---|
| GET | `/subscriptions/products` | store product ids per plan and provider. |
| GET | `/subscriptions/me` | plan, the `accountToken` to attach to purchases, and the store state: status (ACTIVE, GRACE_PERIOD, BILLING_RETRY, ON_HOLD, PAUSED, PENDING, EXPIRED, REFUNDED, REVOKED), autoRenew, expiresAt, graceUntil, pendingPlan (downgrade at renewal), billingIssue, manageUrl. |
| POST | `/subscriptions/apple {signedTransaction, signedRenewalInfo?}` | StoreKit 2 JWS verified against Apple Root CA G3, then the App Store Server API. |
| POST | `/subscriptions/google {productId, purchaseToken}` | Play Developer API `subscriptionsv2`; acknowledged by the server. |
| POST | `/subscriptions/restore {apple[], google[]}` | re-attaches purchases; a receipt owned by another account is not transferred. |
| POST | `/subscriptions/apple/notifications` · `/subscriptions/google/rtdn?token=` | App Store Server Notifications v2 and Google RTDN: renewals, grace period, billing retry, on hold, pause, plan changes, refunds, revocations. |

The app finishes a store transaction only after the server accepts it, so an interrupted purchase is re-delivered on the next launch. Upgrades start immediately (Google: time proration); downgrades start at renewal (Google: deferred; Apple: subscription group). Cancelling is done in the store; the app links there.

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

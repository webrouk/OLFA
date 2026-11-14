# 03 — Database ERD

Generated from the migrated PostgreSQL schema (`backend/prisma/migrations/20261114000000_init/migration.sql`) — 41 tables. Every table has a primary key; relations below are the real foreign keys.

## Key design decisions

| Concern | Mechanism |
|---|---|
| One live account per phone, soft delete | partial unique index `users_phone_live_uq … WHERE deleted_at IS NULL` |
| No duplicate likes / passes | `UNIQUE (from_user_id, to_user_id)` |
| One match per pair | `CHECK (user_a_id < user_b_id)` + `UNIQUE (user_a_id, user_b_id)` |
| Race-free mutual match | `olfa_like()` takes a per-pair advisory lock inside one transaction |
| Quotas that cannot be exceeded concurrently | `olfa_consume_quota()` — `INSERT … ON CONFLICT DO UPDATE … WHERE used < limit` |
| Quota windows | `usage_counters.period_start/end` = user-local midnights stored as UTC; append-only `usage_events` ledger |
| Idempotent chat send | `UNIQUE (conversation_id, sender_id, client_message_id)` |
| OTP never stored in clear | `otp_challenges.code_hash` = HMAC-SHA256(secret, phone:code) |
| Refresh-token rotation + reuse detection | `user_sessions.family_id`, `refresh_token_hash` (SHA-256) |
| Photo rights acknowledgement | `CHECK (rights_confirmed)` on `user_photos` |
| One open review per user | partial unique index on `verification_requests (user_id, type) WHERE status = 'PENDING'` |

## Identity & profile

```mermaid
erDiagram
  users {
    uuid id PK
    varchar phone_e164
    bpchar phone_country
    timestamptz phone_verified_at
    account_status status
    app_locale locale
    varchar timezone
    timestamptz age_confirmed_at
    varchar terms_version
    timestamptz terms_accepted_at
    timestamptz last_active_at
    timestamptz deletion_requested_at
    timestamptz deleted_at
    timestamptz created_at
    string plus_1_more
  }
  user_profiles {
    uuid user_id PK
    varchar display_name
    date birth_date
    gender gender
    bpchar country_code
    varchar city
    bool show_location
    marital_status marital_status
    bool has_children
    bool wants_children
    education_level education
    varchar occupation
    marriage_timeline marriage_timeline
    bool smoking
    string plus_6_more
  }
  user_preferences {
    uuid user_id PK
    int2 age_min
    int2 age_max
    bool same_country_only
    bpchar country_codes
    text cities
    marital_status marital_statuses
    education_level education_levels
    text occupations
    bool wants_children
    timestamptz updated_at
  }
  user_photos {
    uuid id PK
    uuid user_id FK
    text storage_key
    varchar mime_type
    int4 bytes
    int4 width
    int4 height
    bpchar sha256
    varchar phash
    jsonb variants
    int2 position
    photo_status status
    bool rights_confirmed
    jsonb moderation
    string plus_4_more
  }
  user_verifications {
    uuid user_id PK
    verification_type type PK
    timestamptz verified_at
    varchar provider
    varchar reference
    timestamptz revoked_at
  }
  verification_requests {
    uuid id PK
    uuid user_id FK
    verification_type type
    verification_status status
    text selfie_key
    jsonb auto_result
    varchar reject_code
    varchar reject_reason
    uuid reviewed_by FK
    timestamptz submitted_at
    timestamptz reviewed_at
  }
  interests {
    int4 id PK
    varchar key
    varchar name_ar
    varchar name_en
    varchar category
    bool is_basic
    bool is_active
  }
  user_interests {
    uuid user_id PK
    int4 interest_id PK
  }
  otp_challenges {
    uuid id PK
    varchar phone_e164
    bpchar code_hash
    int2 attempts
    int2 max_attempts
    bpchar ip_hash
    varchar device_id
    timestamptz expires_at
    timestamptz consumed_at
    timestamptz created_at
  }
  user_sessions {
    uuid id PK
    uuid user_id FK
    uuid family_id
    bpchar refresh_token_hash
    varchar device_id
    varchar platform
    varchar app_version
    text fcm_token
    bpchar ip_hash
    varchar user_agent
    timestamptz created_at
    timestamptz last_used_at
    timestamptz expires_at
    timestamptz revoked_at
    string plus_1_more
  }
  interests ||--o{ user_interests : "interest_id"
  users ||--o{ user_interests : "user_id"
  users ||--o{ user_photos : "user_id"
  users ||--o{ user_preferences : "user_id"
  users ||--o{ user_profiles : "user_id"
  users ||--o{ user_sessions : "user_id"
  users ||--o{ user_verifications : "user_id"
  admin_users ||--o{ verification_requests : "reviewed_by"
  users ||--o{ verification_requests : "user_id"
```

## Discovery & matching

```mermaid
erDiagram
  likes {
    uuid id PK
    uuid from_user_id FK
    uuid to_user_id FK
    timestamptz created_at
  }
  passes {
    uuid id PK
    uuid from_user_id FK
    uuid to_user_id FK
    timestamptz created_at
    timestamptz expires_at
  }
  matches {
    uuid id PK
    uuid user_a_id FK
    uuid user_b_id FK
    match_status status
    int2 score
    timestamptz created_at
    timestamptz ended_at
    uuid ended_by FK
  }
  compatibility_scores {
    uuid viewer_id PK
    uuid candidate_id PK
    int2 score
    jsonb breakdown
    int4 weights_version
    timestamptz computed_at
  }
  discovery_history {
    int8 id PK
    uuid viewer_id FK
    uuid candidate_id FK
    discovery_action action
    timestamptz created_at
  }
  users ||--o{ compatibility_scores : "viewer_id"
  users ||--o{ compatibility_scores : "candidate_id"
  users ||--o{ discovery_history : "viewer_id"
  users ||--o{ discovery_history : "candidate_id"
  users ||--o{ likes : "from_user_id"
  users ||--o{ likes : "to_user_id"
  users ||--o{ matches : "user_a_id"
  users ||--o{ matches : "user_b_id"
  users ||--o{ matches : "ended_by"
  users ||--o{ passes : "from_user_id"
  users ||--o{ passes : "to_user_id"
```

## Messaging

```mermaid
erDiagram
  conversations {
    uuid id PK
    uuid match_id FK
    uuid started_by FK
    timestamptz created_at
    timestamptz last_message_at
  }
  conversation_members {
    uuid conversation_id PK
    uuid user_id PK
    timestamptz joined_at
    timestamptz last_read_at
    bool muted
  }
  messages {
    uuid id PK
    uuid conversation_id FK
    uuid sender_id FK
    uuid client_message_id
    message_type type
    varchar body
    bool flagged
    timestamptz created_at
    timestamptz deleted_at
  }
  message_receipts {
    uuid message_id PK
    uuid user_id PK
    timestamptz delivered_at
    timestamptz read_at
  }
  conversations ||--o{ conversation_members : "conversation_id"
  users ||--o{ conversation_members : "user_id"
  matches ||--o{ conversations : "match_id"
  users ||--o{ conversations : "started_by"
  messages ||--o{ message_receipts : "message_id"
  users ||--o{ message_receipts : "user_id"
  conversations ||--o{ messages : "conversation_id"
  users ||--o{ messages : "sender_id"
```

## Commercial

```mermaid
erDiagram
  subscription_plans {
    uuid id PK
    plan_code code
    varchar name_ar
    varchar name_en
    bool is_active
    int2 sort_order
    timestamptz updated_at
  }
  feature_entitlements {
    uuid plan_id PK
    varchar feature_key PK
    jsonb value
    timestamptz updated_at
  }
  plan_products {
    uuid id PK
    uuid plan_id FK
    payment_provider provider
    varchar product_id
    int2 duration_days
    bool is_active
  }
  user_subscriptions {
    uuid id PK
    uuid user_id FK
    uuid plan_id FK
    payment_provider provider
    subscription_status status
    varchar original_transaction_id
    varchar product_id
    timestamptz starts_at
    timestamptz expires_at
    bool auto_renew
    timestamptz cancelled_at
    timestamptz created_at
    timestamptz updated_at
  }
  usage_counters {
    uuid user_id PK
    varchar counter_key PK
    timestamptz period_start PK
    timestamptz period_end
    int4 used
    timestamptz updated_at
  }
  usage_events {
    int8 id PK
    uuid user_id FK
    varchar counter_key
    int4 delta
    timestamptz period_start
    varchar ref_type
    varchar ref_id
    timestamptz created_at
  }
  payments {
    uuid id PK
    uuid user_id FK
    uuid subscription_id FK
    payment_provider provider
    varchar provider_payment_id
    int4 amount_minor
    bpchar currency
    payment_status status
    timestamptz created_at
    timestamptz refunded_at
  }
  transactions {
    uuid id PK
    uuid payment_id FK
    transaction_type type
    int4 amount_minor
    bpchar currency
    timestamptz created_at
  }
  purchase_events {
    uuid id PK
    payment_provider provider
    varchar event_id
    varchar event_type
    uuid user_id FK
    jsonb payload
    timestamptz received_at
    timestamptz processed_at
    text error
  }
  subscription_plans ||--o{ feature_entitlements : "plan_id"
  user_subscriptions ||--o{ payments : "subscription_id"
  users ||--o{ payments : "user_id"
  subscription_plans ||--o{ plan_products : "plan_id"
  users ||--o{ purchase_events : "user_id"
  payments ||--o{ transactions : "payment_id"
  users ||--o{ usage_counters : "user_id"
  users ||--o{ usage_events : "user_id"
  subscription_plans ||--o{ user_subscriptions : "plan_id"
  users ||--o{ user_subscriptions : "user_id"
```

## Administration

```mermaid
erDiagram
  admin_users {
    uuid id PK
    varchar email
    varchar name
    text password_hash
    text totp_secret_enc
    bool is_active
    timestamptz last_login_at
    timestamptz created_at
  }
  roles {
    int4 id PK
    varchar key
    varchar name
  }
  permissions {
    int4 id PK
    varchar key
    varchar description
  }
  role_permissions {
    int4 role_id PK
    int4 permission_id PK
  }
  admin_user_roles {
    uuid admin_id PK
    int4 role_id PK
  }
  audit_logs {
    int8 id PK
    actor_type actor_type
    uuid actor_id
    varchar action
    varchar entity_type
    varchar entity_id
    jsonb before
    jsonb after
    varchar reason
    bpchar ip_hash
    varchar request_id
    timestamptz created_at
  }
  moderation_actions {
    uuid id PK
    uuid admin_id FK
    uuid target_user_id FK
    moderation_action_type action
    varchar target_type
    varchar target_id
    uuid report_id FK
    varchar reason
    timestamptz created_at
  }
  admin_users ||--o{ admin_user_roles : "admin_id"
  roles ||--o{ admin_user_roles : "role_id"
  admin_users ||--o{ moderation_actions : "admin_id"
  reports ||--o{ moderation_actions : "report_id"
  users ||--o{ moderation_actions : "target_user_id"
  permissions ||--o{ role_permissions : "permission_id"
  roles ||--o{ role_permissions : "role_id"
```

## Support & safety

```mermaid
erDiagram
  reports {
    uuid id PK
    uuid reporter_id FK
    uuid reported_user_id FK
    report_target target_type
    uuid target_id
    report_reason reason
    varchar details
    report_status status
    int2 priority
    uuid handled_by FK
    varchar resolution
    timestamptz created_at
    timestamptz resolved_at
  }
  blocked_users {
    uuid blocker_id PK
    uuid blocked_id PK
    timestamptz created_at
  }
  support_tickets {
    uuid id PK
    uuid user_id FK
    ticket_category category
    varchar subject
    ticket_status status
    uuid assigned_to FK
    timestamptz created_at
    timestamptz updated_at
  }
  ticket_messages {
    uuid id PK
    uuid ticket_id FK
    actor_type author_type
    uuid author_id
    varchar body
    timestamptz created_at
  }
  notifications {
    uuid id PK
    uuid user_id FK
    notification_type type
    varchar title_key
    varchar body_key
    jsonb params
    jsonb data
    timestamptz read_at
    timestamptz created_at
  }
  system_settings {
    varchar key PK
    jsonb value
    varchar description
    uuid updated_by FK
    timestamptz updated_at
  }
  users ||--o{ blocked_users : "blocker_id"
  users ||--o{ blocked_users : "blocked_id"
  users ||--o{ notifications : "user_id"
  admin_users ||--o{ reports : "handled_by"
  users ||--o{ reports : "reporter_id"
  users ||--o{ reports : "reported_user_id"
  admin_users ||--o{ support_tickets : "assigned_to"
  users ||--o{ support_tickets : "user_id"
  admin_users ||--o{ system_settings : "updated_by"
  support_tickets ||--o{ ticket_messages : "ticket_id"
```


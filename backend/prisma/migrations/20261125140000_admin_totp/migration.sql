-- Admin two-factor sign-in (TOTP, RFC 6238). The secret is stored sealed
-- (AES-256-GCM, key ADMIN_TOTP_KEY) in admin_users.totp_secret_enc.
ALTER TABLE admin_users
  ADD COLUMN totp_confirmed_at timestamptz,
  -- last accepted 30-second step: the same code can never be used twice
  ADD COLUMN totp_last_step bigint;

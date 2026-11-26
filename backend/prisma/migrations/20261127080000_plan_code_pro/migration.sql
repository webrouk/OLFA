-- Counselor plans (Plus / Premium for licensed professionals). Kept in their
-- own migration: a new enum value cannot be used in the transaction that adds it.
ALTER TYPE plan_code ADD VALUE IF NOT EXISTS 'PRO_PLUS';
ALTER TYPE plan_code ADD VALUE IF NOT EXISTS 'PRO_PREMIUM';

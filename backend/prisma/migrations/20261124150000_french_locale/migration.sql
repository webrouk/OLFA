-- French joins Arabic and English. Devices in any other language get English,
-- so English (not Arabic) is the default for rows created without a locale.
ALTER TYPE app_locale ADD VALUE IF NOT EXISTS 'fr';
ALTER TABLE users ALTER COLUMN locale SET DEFAULT 'en';

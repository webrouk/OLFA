# Website and admin dashboard (sukna.online)

- Source: `web/` (see `web/README.md`). Hosting: Hostinger Business, order 61000645, account u185135406, website `sukna.online` (static).
- Deploy steps:
  1. `npm run build` in `web/`.
  2. Zip the contents of `dist/`, with `index.html` at the root.
  3. Upload the zip with `hosting_files_generate-upload-url` (TUS) as `site.zip`.
  4. Run `hosting_websites_deploy-static-site-archive` with `archive_path: site.zip`.
  Every deploy replaces the whole site.
- Admin API added for the dashboard (all under `/v1/admin`, admin JWT):

| Method | Path | Permission | Notes |
| --- | --- | --- | --- |
| POST | `auth/login` | public | `{email,password,totp?}` → `{accessToken, mfa, totpSetupRequired}`. Enrolled admins without `totp` get 401 with `details.totpRequired`. A code is accepted once (`totp_last_step`) |
| GET | `me` | any (allowed before 2FA set-up) | profile, `totpEnrolled`, permissions |
| POST | `auth/totp/setup` | any (before 2FA) | `{secret, otpauthUrl}`; secret stored sealed with `ADMIN_TOTP_KEY` |
| POST | `auth/totp/confirm` | any (before 2FA) | `{code}` → new token with `mfa: true` |
| GET | `stats` | any | member counters and queue sizes |
| GET | `users?q&status&accountType&page` | users.read | 25 per page; phone masked |
| GET | `users/:id` | users.read | detail + last 20 audit entries |
| GET | `reports?status` | reports.manage | default: OPEN + IN_REVIEW |
| POST | `reports/:id/resolve` | reports.manage | `{status: ACTION_TAKEN|DISMISSED, resolution}` |
| GET | `support/faq` | support.manage | all entries, all languages |

- With `ADMIN_REQUIRE_TOTP=true` (default), a token without `mfa` gets 403 `details.totpSetupRequired` everywhere except the three set-up routes.
- `CORS_ORIGINS` on the API must include `https://sukna.online`.
- The admin CLI: `npm run admin:create -- --email … --name … --role super_admin` (password read from the terminal, argon2id).

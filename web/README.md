# sukna.online — OLFA website and admin dashboard

A static site with no server code of its own. It is built into `dist/` and served by Hostinger. Admin data comes from the OLFA NestJS API.

| Path | What it is |
| --- | --- |
| `/`, `/en/`, `/fr/` | Landing page in Arabic (RTL), English and French |
| `/terms/`, `/privacy/`, `/professional/` (also under `/en/`, `/fr/`) | The app's legal texts, generated from `content/legal.json` |
| `/admin/` | Team dashboard (React). It is never indexed or cached and runs under a strict CSP |

## Build

```bash
cd web
npm install
OLFA_API_BASE=https://api.sukna.online npm run build   # leave the variable out → the dashboard shows "not connected"
npm run check                                          # i18n keys + legal texts + TypeScript
```

- The API address is written into `dist/admin/config.js` at build time. You can also edit that file on the hosting without rebuilding.
- The legal pages come from the same source as the app (`mobile/lib/features/legal/legal_content*.dart`). After changing those files, run `npm run legal`.
- No `package-lock.json` is committed yet: the build machine had no registry access. Run `npm install` once and commit the lock file.

## Dashboard

The dashboard has these sections:

| Section | What it does |
| --- | --- |
| Overview | Counters and queues |
| Verification | Profile photos and the selfie, with the 8 criteria (C1–C8). Approve is enabled only after all 8 are ticked. Reject with a code, or reject single photos. Shows a note when the member asked for a female reviewer |
| Members | Search and detail (phone masked), suspend, ban, lift, action history |
| Reports | List and resolve |
| Support | Ticket thread: reply, change status, attachments (up to 3 images or PDFs, 10 MB each; uploaded to storage through a presigned POST) |
| Session disputes | Release the held fee to the counselor, or refund the client |
| Counselors | Applications and credential documents |
| Integrity reviews | Review and decide |
| Withdrawals | Process, mark paid, reject or fail. Viewing full transfer details is recorded in the audit log |
| FAQ | Create, edit and delete in ar/en/fr |
| Settings | Edit server settings |

Security:

- **Two-factor sign-in (TOTP)** is required by default (`ADMIN_REQUIRE_TOTP=true`). On first sign-in the admin adds the key to an authenticator app. Until then the server refuses every endpoint except set-up.
- Each code can be used only once.
- The secret is stored sealed with `ADMIN_TOTP_KEY`.
- The session token lives in `sessionStorage` only and expires after 8 hours.
- The server enforces every permission. The dashboard only hides links the admin has no permission for.

## Backend requirements before the dashboard shows data

1. Host the NestJS API with PostgreSQL, Redis and S3 on an HTTPS host, e.g. `api.sukna.online`. Hostinger shared hosting has no PostgreSQL or Redis, so this needs a VPS or a managed service.
2. Set these environment variables on the API:
   - `CORS_ORIGINS=https://sukna.online`
   - `ADMIN_TOTP_KEY=<base64 of 32 random bytes>` (`openssl rand -base64 32`)
   - `ADMIN_REQUIRE_TOTP=true`
3. Create the first admin on the server. The password is typed in the terminal and never passed as an argument:
   `npm run build && npm run admin:create -- --email you@example.com --name "Name" --role super_admin`
4. Rebuild the site with `OLFA_API_BASE` and deploy it again.

## Deploy (Hostinger)

The target is in `.hostinger/site.json`. Zip the contents of `dist/` with `index.html` at the root, upload the zip, then deploy it as a static site archive (see `docs/05-website-admin.md`).

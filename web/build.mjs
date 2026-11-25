// Builds the whole sukna.online site into dist/:
//   /            Arabic landing      /en/  /fr/   English / French
//   /terms/ /privacy/ /professional/  (and under /en/, /fr/) — from content/legal.json
//   /admin/      the dashboard (React, bundled by esbuild)
// Usage: node build.mjs            (OLFA_API_BASE=https://api.example.com to bake the API address)
//        node build.mjs --check    (i18n and legal checks only)
import { build } from 'esbuild';
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { LANGS } from './src/site/content.mjs';
import { ORIGIN, pages } from './src/site/render.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const out = join(root, 'dist');
const legal = JSON.parse(readFileSync(join(root, 'content/legal.json'), 'utf8'));

// ── checks: every t('key') exists, no empty translation ──
function check() {
  const dict = readFileSync(join(root, 'src/admin/i18n.ts'), 'utf8');
  const keys = new Set([...dict.matchAll(/^\s+'?([\w.]+)'?: \[/gm)].map((m) => m[1]));
  const empty = [...dict.matchAll(/^\s+'?([\w.]+)'?: \[(.*)\],$/gm)].filter((m) => /(^|, )''/.test(m[2])).map((m) => m[1]);
  const used = new Set();
  const walk = (d) => readdirSync(d, { withFileTypes: true }).forEach((e) => (e.isDirectory() ? walk(join(d, e.name)) : /\.tsx?$/.test(e.name) && [...readFileSync(join(d, e.name), 'utf8').matchAll(/\bt\('([\w.]+)'/g)].forEach((m) => used.add(m[1]))));
  walk(join(root, 'src/admin'));
  const missing = [...used].filter((k) => !keys.has(k));
  if (missing.length || empty.length) throw new Error(`i18n: missing ${missing.join(', ') || '-'}; empty ${empty.join(', ') || '-'}`);
  for (const [k, d] of Object.entries(legal)) if (!d.title || !d.sections.length) throw new Error(`legal.json: ${k} is empty`);
  console.log(`✓ i18n ${keys.size} keys (${used.size} used directly), legal ${Object.keys(legal).length} documents`);
}
check();
if (process.argv.includes('--check')) process.exit(0);

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

// ── public pages ──
const site = pages(legal);
for (const [path, html] of Object.entries(site)) {
  mkdirSync(dirname(join(out, path)), { recursive: true });
  writeFileSync(join(out, path), html);
}
cpSync(join(root, 'src/site/site.css'), join(out, 'site.css'));
for (const f of ['favicon.svg', 'robots.txt', '.htaccess']) cpSync(join(root, 'public', f), join(out, f));
writeFileSync(
  join(out, 'sitemap.xml'),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${Object.keys(site)
    .map((p) => `  <url><loc>${ORIGIN}/${p.replace(/index\.html$/, '')}</loc></url>`)
    .join('\n')}\n</urlset>\n`,
);
const notFound = site['index.html'].replace(/<main>[\s\S]*<\/main>/, `<main><section class="hero"><div class="wrap"><p class="kicker">404</p><h1>الصفحة غير موجودة · Page not found</h1><p class="lead"><a href="/">أُلْفَة</a> · <a href="/en/">OLFA</a> · <a href="/fr/">OLFA (FR)</a></p></div></section></main>`);
writeFileSync(join(out, '404.html'), notFound);

// ── dashboard ──
const admin = join(out, 'admin');
mkdirSync(admin, { recursive: true });
const r = await build({
  entryPoints: [join(root, 'src/admin/main.tsx')],
  bundle: true,
  minify: !process.env.OLFA_DEV,
  sourcemap: false,
  format: 'esm',
  target: ['es2021', 'safari15'],
  jsx: 'automatic',
  define: { 'process.env.NODE_ENV': '"production"' },
  nodePaths: (process.env.NODE_PATH ?? '').split(':').filter(Boolean),
  write: false,
  logLevel: 'warning',
});
const js = r.outputFiles[0].contents;
const hash = createHash('sha256').update(js).digest('hex').slice(0, 10);
writeFileSync(join(admin, `app.${hash}.js`), js);
const css = readFileSync(join(root, 'src/admin/admin.css'));
const cssHash = createHash('sha256').update(css).digest('hex').slice(0, 10);
writeFileSync(join(admin, `app.${cssHash}.css`), css);
const apiBase = (process.env.OLFA_API_BASE ?? '').trim();
if (apiBase && !/^https:\/\/[^/]+$/.test(apiBase)) throw new Error('OLFA_API_BASE must be https://host with no path');
writeFileSync(
  join(admin, 'config.js'),
  `// Address of the OLFA API (NestJS). Empty = not connected yet: the dashboard says so instead of showing anything.\n// Set it at build time: OLFA_API_BASE=https://api.example.com npm run build\nwindow.OLFA_CONFIG = { apiBase: ${JSON.stringify(apiBase)} };\n`,
);
writeFileSync(
  join(admin, 'index.html'),
  `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="referrer" content="no-referrer">
<title>OLFA admin</title>
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700;800&family=Tajawal:wght@400;500;700;800&display=swap">
<link rel="stylesheet" href="/admin/app.${cssHash}.css">
<script src="/admin/config.js"></script>
<script type="module" src="/admin/app.${hash}.js"></script>
</head>
<body><div id="root"></div><noscript>JavaScript is required.</noscript></body>
</html>
`,
);
cpSync(join(root, 'public/admin.htaccess'), join(admin, '.htaccess'));
console.log(`✓ built ${Object.keys(site).length} pages (${LANGS.join('/')}) + admin (${(js.length / 1024).toFixed(0)} KB js) → dist/ · API ${apiBase || 'not set'}`);

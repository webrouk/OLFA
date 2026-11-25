// Renders the public pages to static HTML (no JavaScript needed to read them).
import { LANGS, LEGAL, site } from './content.mjs';

export const ORIGIN = 'https://sukna.online';
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const base = (lang) => (lang === 'ar' ? '/' : `/${lang}/`);
const LANG_LABEL = { ar: 'العربية', en: 'English', fr: 'Français' };

const SYMBOL = (color) =>
  `<svg viewBox="0 0 48 48" aria-hidden="true" class="sym"><g transform="translate(0 1)"><circle cx="17.2" cy="11.4" r="3.4" fill="${color}"/><circle cx="30.8" cy="11.4" r="3.4" fill="${color}"/><path d="M24 38.2 13.4 27.6a6 6 0 0 1 8.5-8.5L24 21.2l2.1-2.1a6 6 0 0 1 8.5 8.5Z" fill="none" stroke="${color}" stroke-width="3" stroke-linejoin="round"/></g></svg>`;

function head(lang, title, desc, path) {
  const alt = LANGS.map((l) => `<link rel="alternate" hreflang="${l}" href="${ORIGIN}${base(l)}${path}">`).join('');
  return `<!DOCTYPE html>
<html lang="${lang}" dir="${site[lang].dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${ORIGIN}${base(lang)}${path}">${alt}<link rel="alternate" hreflang="x-default" href="${ORIGIN}/en/${path}">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:type" content="website">
<meta name="theme-color" content="#8B0D2B">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&family=Tajawal:wght@400;500;700;800&display=swap">
<link rel="stylesheet" href="/site.css">
</head>`;
}

function header(lang, path) {
  const t = site[lang];
  const langs = LANGS.map((l) => `<a href="${base(l)}${path}" hreflang="${l}" lang="${l}"${l === lang ? ' aria-current="true"' : ''}>${LANG_LABEL[l]}</a>`).join('');
  return `<header class="top"><div class="wrap row">
<a class="brand" href="${base(lang)}">${SYMBOL('#8B0D2B')}<span>${esc(t.name)}</span></a>
<nav class="menu" aria-label="main">${path ? '' : `<a href="#how">${t.nav.how}</a><a href="#safety">${t.nav.safety}</a><a href="#experts">${t.nav.experts}</a><a href="#faq">${t.nav.faq}</a>`}</nav>
<div class="langs" aria-label="${t.footer.lang}">${langs}</div>
</div></header>`;
}

function footer(lang) {
  const t = site[lang];
  const b = base(lang);
  return `<footer class="foot"><div class="wrap row">
<div class="brand light">${SYMBOL('#FFFFFF')}<span>${esc(t.name)}</span></div>
<nav aria-label="${t.nav.legal}"><a href="${b}terms/">${t.footer.terms}</a><a href="${b}privacy/">${t.footer.privacy}</a><a href="${b}professional/">${t.footer.pro}</a></nav>
<small>© ${new Date().getUTCFullYear()} ${esc(t.name)} · ${t.footer.rights}</small>
</div></footer>`;
}

const lines = (s) => esc(s).replace(/\n/g, '<br>');

export function landing(lang) {
  const t = site[lang];
  return `${head(lang, t.metaTitle, t.metaDesc, '')}
<body>
${header(lang, '')}
<main>
<section class="hero"><div class="wrap">
<p class="kicker">${esc(t.hero.kicker)}</p>
<h1>${lines(t.hero.title)}</h1>
<p class="lead">${esc(t.hero.body)}</p>
<p class="status"><span class="dot" aria-hidden="true"></span>${esc(t.hero.status)}</p>
</div></section>
<section class="pillars"><div class="wrap grid3">
${t.pillars.map(([h, p], i) => `<article class="card"><span class="num">0${i + 1}</span><h2>${esc(h)}</h2><p>${esc(p)}</p></article>`).join('\n')}
</div></section>
<section id="how" class="band"><div class="wrap">
<h2 class="title">${esc(t.how.title)}</h2>
<ol class="steps">${t.how.steps.map(([h, p]) => `<li><h3>${esc(h)}</h3><p>${esc(p)}</p></li>`).join('')}</ol>
</div></section>
<section id="safety"><div class="wrap">
<h2 class="title">${esc(t.safety.title)}</h2>
<div class="grid2">${t.safety.items.map(([h, p]) => `<article class="item"><h3>${esc(h)}</h3><p>${esc(p)}</p></article>`).join('')}</div>
</div></section>
<section id="experts" class="dark"><div class="wrap narrow">
<h2 class="title">${esc(t.experts.title)}</h2>
<p class="lead">${esc(t.experts.body)}</p>
</div></section>
<section id="faq"><div class="wrap narrow">
<h2 class="title">${esc(t.faq.title)}</h2>
${t.faq.items.map(([q, a]) => `<details><summary>${esc(q)}</summary><p>${esc(a)}</p></details>`).join('\n')}
</div></section>
</main>
${footer(lang)}
</body></html>
`;
}

export function legalPage(lang, kind, legal) {
  const t = site[lang];
  const d = legal[LEGAL[kind][lang]];
  const body = (s) =>
    s
      .split('\n')
      .filter((x) => x.trim())
      .map((x) => (x.trim().startsWith('•') ? `<li>${esc(x.trim().slice(1).trim())}</li>` : `<p>${esc(x)}</p>`))
      .join('')
      .replace(/(<li>.*?<\/li>)+/g, (m) => `<ul>${m}</ul>`);
  return `${head(lang, `${d.title} — ${t.name}`, d.intro.slice(0, 155), `${kind}/`)}
<body>
${header(lang, `${kind}/`)}
<main class="legal"><div class="wrap narrow">
<a class="back" href="${base(lang)}">${esc(t.back)}</a>
<h1>${esc(d.title)}</h1>
<p class="updated">${esc(d.updated)}</p>
<p class="lead">${esc(d.intro)}</p>
${d.sections.map(([h, b]) => `<section><h2>${esc(h)}</h2>${body(b)}</section>`).join('\n')}
</div></main>
${footer(lang)}
</body></html>
`;
}

export const pages = (legal) => {
  const out = {};
  for (const l of LANGS) {
    const b = l === 'ar' ? '' : `${l}/`;
    out[`${b}index.html`] = landing(l);
    for (const k of Object.keys(LEGAL)) out[`${b}${k}/index.html`] = legalPage(l, k, legal);
  }
  return out;
};

import React from 'react';
import type { Key } from './i18n';
import { Logo, saveLang, useT } from './ui';

export function LangSwitch() {
  const { lang, setLang } = useT();
  return (
    <div className="langs" role="group" aria-label="Language">
      {(
        [
          ['ar', 'العربية'],
          ['en', 'English'],
          ['fr', 'Français'],
        ] as const
      ).map(([l, n]) => (
        <button
          key={l}
          type="button"
          aria-pressed={lang === l}
          onClick={() => {
            saveLang(l);
            setLang(l);
          }}
          lang={l}
        >
          {n}
        </button>
      ))}
    </div>
  );
}

export const NAV: { path: string; key: Key; perm?: string }[] = [
  { path: '', key: 'nav.overview' },
  { path: 'verification', key: 'nav.verification', perm: 'verification.review' },
  { path: 'users', key: 'nav.users', perm: 'users.read' },
  { path: 'reports', key: 'nav.reports', perm: 'reports.manage' },
  { path: 'support', key: 'nav.support', perm: 'support.manage' },
  { path: 'disputes', key: 'nav.disputes', perm: 'consultations.manage' },
  { path: 'counselors', key: 'nav.counselors', perm: 'counselors.review' },
  { path: 'integrity', key: 'nav.integrity', perm: 'integrity.manage' },
  { path: 'withdrawals', key: 'nav.withdrawals', perm: 'payouts.manage' },
  { path: 'faq', key: 'nav.faq', perm: 'support.manage' },
  { path: 'compat', key: 'nav.compat', perm: 'settings.manage' },
  { path: 'ads', key: 'nav.ads', perm: 'settings.manage' },
  { path: 'settings', key: 'nav.settings', perm: 'settings.manage' },
];

export function Shell({ route, me, onSignOut, children }: { route: string; me?: { name: string; email: string; permissions: string[] }; onSignOut: () => void; children: React.ReactNode }) {
  const { t } = useT();
  const can = (p?: string) => !p || !me || me.permissions.includes(p) || me.permissions.includes('*');
  return (
    <div className="shell">
      <aside className="side">
        <a className="side-brand" href="#/">
          <Logo light />
          <span>
            {t('brand')}
            <small>{t('nav.panel')}</small>
          </span>
        </a>
        <nav>
          {NAV.filter((n) => can(n.perm)).map((n) => (
            <a key={n.path} href={'#/' + n.path} aria-current={route === n.path ? 'page' : undefined}>
              {t(n.key)}
            </a>
          ))}
        </nav>
        <div className="side-foot">
          {me && (
            <div className="me">
              <strong>{me.name}</strong>
              <small dir="ltr">{me.email}</small>
            </div>
          )}
          <LangSwitch />
          <button type="button" className="signout" onClick={onSignOut}>
            {t('signOut')}
          </button>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}

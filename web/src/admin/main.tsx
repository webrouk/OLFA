import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { apiConfigured, GET, session, setSessionHandlers } from './api';
import type { Lang } from './i18n';
import { Login, NotConnected, TotpSetup } from './pages/auth';
import { AdsPage } from './pages/ads';
import { Counselors, Integrity } from './pages/counselors';
import { FaqPage, Settings } from './pages/config';
import { Disputes, Withdrawals } from './pages/money';
import { Overview } from './pages/overview';
import { Reports } from './pages/reports';
import { Tickets, TicketThread } from './pages/support';
import { UserDetailPage, Users } from './pages/users';
import { VerificationDetail, VerificationQueue } from './pages/verification';
import { Shell } from './shell';
import { I18nCtx, initialLang, makeT, ToastHost, useRoute, useT } from './ui';

type Me = { id: string; email: string; name: string; totpEnrolled: boolean; permissions: string[] };
type Phase = 'login' | 'setup' | 'app';

function App() {
  const { t } = useT();
  const route = useRoute();
  const [phase, setPhase] = useState<Phase>(() => (session.get() ? 'app' : 'login'));
  const [me, setMe] = useState<Me>();

  useEffect(() => {
    setSessionHandlers(() => setPhase('login'), () => setPhase('setup'));
  }, []);
  useEffect(() => {
    if (phase !== 'app') return;
    GET<Me>('me').then(setMe, () => {});
  }, [phase]);

  const signOut = () => {
    session.clear();
    setMe(undefined);
    setPhase('login');
  };

  if (!apiConfigured()) return <NotConnected />;
  if (phase === 'login') return <Login onDone={(setup) => setPhase(setup ? 'setup' : 'app')} />;
  if (phase === 'setup') return <TotpSetup onDone={() => setPhase('app')} onSignOut={signOut} />;

  const [a, b] = route;
  let page: React.ReactNode;
  switch (a ?? '') {
    case '':
      page = <Overview />;
      break;
    case 'verification':
      page = b ? <VerificationDetail id={b} /> : <VerificationQueue />;
      break;
    case 'users':
      page = b ? <UserDetailPage id={b} /> : <Users />;
      break;
    case 'reports':
      page = <Reports />;
      break;
    case 'support':
      page = b ? <TicketThread id={b} /> : <Tickets />;
      break;
    case 'disputes':
      page = <Disputes />;
      break;
    case 'counselors':
      page = <Counselors />;
      break;
    case 'integrity':
      page = <Integrity />;
      break;
    case 'withdrawals':
      page = <Withdrawals />;
      break;
    case 'faq':
      page = <FaqPage />;
      break;
    case 'ads':
      page = <AdsPage />;
      break;
    case 'settings':
      page = <Settings />;
      break;
    default:
      page = (
        <div className="state">
          <p>{t('err.notFound')}</p>
          <a className="btn ghost" href="#/">
            {t('nav.overview')}
          </a>
        </div>
      );
  }
  return (
    <Shell route={a ?? ''} me={me} onSignOut={signOut}>
      {page}
    </Shell>
  );
}

function Root() {
  const [lang, setLang] = useState<Lang>(initialLang);
  const value = useMemo(() => ({ lang, setLang, t: makeT(lang) }), [lang]);
  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.title = value.t('title');
  }, [lang, value]);
  return (
    <I18nCtx.Provider value={value}>
      <ToastHost>
        <App />
      </ToastHost>
    </I18nCtx.Provider>
  );
}

createRoot(document.getElementById('root')!).render(<Root />);

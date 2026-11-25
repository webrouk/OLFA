import React, { useState } from 'react';
import { ApiError, apiBase, POST, session } from '../api';
import { Btn, errorText, Field, Logo, useT } from '../ui';
import { LangSwitch } from '../shell';

type LoginRes = { accessToken: string; mfa: boolean; totpSetupRequired: boolean };

export function Login({ onDone }: { onDone: (setupNeeded: boolean) => void }) {
  const { t } = useT();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [totp, setTotp] = useState('');
  const [needTotp, setNeedTotp] = useState(false);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setErr('');
    try {
      const r = await POST<LoginRes>('auth/login', { email: email.trim(), password, ...(needTotp ? { totp } : {}) });
      session.set({ token: r.accessToken, mfa: r.mfa });
      setPassword('');
      onDone(r.totpSetupRequired);
    } catch (x) {
      if (x instanceof ApiError && x.details?.totpRequired) {
        if (needTotp) setErr(t('auth.badCode'));
        setNeedTotp(true);
        setTotp('');
      } else if (x instanceof ApiError && x.status === 401) setErr(t('auth.bad'));
      else setErr(errorText(x, t));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="auth">
      <form className="auth-card" onSubmit={submit}>
        <div className="auth-brand">
          <Logo />
          <div>
            <strong>{t('brand')}</strong>
            <span>{t('auth.subtitle')}</span>
          </div>
        </div>
        <Field label={t('auth.email')}>
          <input type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} dir="ltr" disabled={needTotp} />
        </Field>
        <Field label={t('auth.password')}>
          <input type="password" autoComplete="current-password" required minLength={12} value={password} onChange={(e) => setPassword(e.target.value)} dir="ltr" disabled={needTotp} />
        </Field>
        {needTotp && (
          <Field label={t('auth.code')} hint={t('auth.codeHint')}>
            <input inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required value={totp} onChange={(e) => setTotp(e.target.value.replace(/\D/g, ''))} dir="ltr" autoFocus className="code" />
          </Field>
        )}
        {err && (
          <p className="err" role="alert">
            {err}
          </p>
        )}
        <Btn type="submit" disabled={busy}>
          {needTotp ? t('auth.verify') : t('auth.signIn')}
        </Btn>
        {needTotp && (
          <Btn
            kind="ghost"
            onClick={() => {
              setNeedTotp(false);
              setTotp('');
              setErr('');
            }}
          >
            {t('back')}
          </Btn>
        )}
        <p className="muted small">{t('auth.note')}</p>
        <LangSwitch />
      </form>
    </div>
  );
}

export function TotpSetup({ onDone, onSignOut }: { onDone: () => void; onSignOut: () => void }) {
  const { t } = useT();
  const [secret, setSecret] = useState<{ secret: string; otpauthUrl: string } | null>(null);
  const [code, setCode] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const start = async () => {
    setBusy(true);
    setErr('');
    try {
      setSecret(await POST('auth/totp/setup'));
    } catch (x) {
      setErr(errorText(x, t));
    } finally {
      setBusy(false);
    }
  };
  const confirm = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setErr('');
    try {
      const r = await POST<{ accessToken: string; mfa: boolean }>('auth/totp/confirm', { code });
      session.set({ token: r.accessToken, mfa: true });
      onDone();
    } catch (x) {
      setErr(x instanceof ApiError && x.status === 400 ? t('auth.badCode') : errorText(x, t));
    } finally {
      setBusy(false);
    }
  };
  const grouped = secret?.secret.replace(/(.{4})/g, '$1 ').trim();
  return (
    <div className="auth">
      <form className="auth-card wide" onSubmit={confirm}>
        <h1>{t('totp.title')}</h1>
        <p>{t('totp.why')}</p>
        {!secret ? (
          <Btn onClick={start} disabled={busy}>
            {t('totp.start')}
          </Btn>
        ) : (
          <>
            <ol className="steps-list">
              <li>{t('totp.s1')}</li>
              <li>
                {t('totp.s2')}
                <code className="secret" dir="ltr">
                  {grouped}
                </code>
                <a className="btn ghost" href={secret.otpauthUrl}>
                  {t('totp.openApp')}
                </a>
              </li>
              <li>{t('totp.s3')}</li>
            </ol>
            <Field label={t('auth.code')}>
              <input inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))} dir="ltr" className="code" autoFocus />
            </Field>
            <Btn type="submit" disabled={busy || code.length !== 6}>
              {t('totp.confirm')}
            </Btn>
          </>
        )}
        {err && (
          <p className="err" role="alert">
            {err}
          </p>
        )}
        <Btn kind="ghost" onClick={onSignOut}>
          {t('signOut')}
        </Btn>
      </form>
    </div>
  );
}

/** Shown while /admin/config.js has no API address: the honest state before the backend is hosted. */
export function NotConnected() {
  const { t } = useT();
  return (
    <div className="auth">
      <div className="auth-card wide">
        <div className="auth-brand">
          <Logo />
          <div>
            <strong>{t('brand')}</strong>
            <span>{t('auth.subtitle')}</span>
          </div>
        </div>
        <h1>{t('nc.title')}</h1>
        <p>{t('nc.body')}</p>
        <ol className="steps-list">
          <li>{t('nc.s1')}</li>
          <li>
            {t('nc.s2')}
            <code className="secret" dir="ltr">
              OLFA_API_BASE=https://api.sukna.online npm run build
            </code>
          </li>
          <li>{t('nc.s3')}</li>
        </ol>
        {apiBase() && (
          <p className="err" dir="ltr">
            {t('nc.invalid')}: {apiBase()}
          </p>
        )}
        <LangSwitch />
      </div>
    </div>
  );
}

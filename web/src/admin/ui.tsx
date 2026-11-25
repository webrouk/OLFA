import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { ApiError } from './api';
import { DICT, Lang, type Key } from './i18n';

// ───────────── language ─────────────
const LANG_KEY = 'olfa.admin.lang';
export function initialLang(): Lang {
  try {
    const s = localStorage.getItem(LANG_KEY);
    if (s === 'ar' || s === 'en' || s === 'fr') return s;
  } catch {
    /* ignore */
  }
  const n = (navigator.language || 'en').slice(0, 2);
  return n === 'ar' || n === 'fr' ? n : 'en';
}
export function saveLang(l: Lang) {
  try {
    localStorage.setItem(LANG_KEY, l);
  } catch {
    /* ignore */
  }
}

type I18n = { lang: Lang; setLang: (l: Lang) => void; t: (k: Key, vars?: Record<string, string | number>) => string };
export const I18nCtx = createContext<I18n>(null as unknown as I18n);
export const useT = () => useContext(I18nCtx);
export function makeT(lang: Lang) {
  const i = lang === 'ar' ? 0 : lang === 'en' ? 1 : 2;
  return (k: Key, vars?: Record<string, string | number>) => {
    let s = DICT[k]?.[i] ?? k;
    if (vars) for (const [a, b] of Object.entries(vars)) s = s.replaceAll(`{${a}}`, String(b));
    return s;
  };
}

// ───────────── formatting ─────────────
export function useFmt() {
  const { lang } = useT();
  const loc = lang === 'ar' ? 'ar-u-nu-latn' : lang;
  return {
    date: (v?: string | null) => (v ? new Date(v).toLocaleString(loc, { dateStyle: 'medium', timeStyle: 'short' }) : '—'),
    day: (v?: string | null) => (v ? new Date(v).toLocaleDateString(loc, { dateStyle: 'medium' }) : '—'),
    num: (n?: number | null) => (n == null ? '—' : n.toLocaleString(loc)),
    money: (minor?: number | string | null, cur?: string | null) => {
      if (minor == null || !cur) return '—';
      const digits = ['KWD', 'BHD', 'OMR', 'JOD', 'TND', 'IQD', 'LYD'].includes(cur) ? 3 : ['JPY', 'KRW'].includes(cur) ? 0 : 2;
      return new Intl.NumberFormat(loc, { style: 'currency', currency: cur, minimumFractionDigits: digits }).format(Number(minor) / 10 ** digits);
    },
  };
}

// ───────────── routing (hash, so static hosting needs no rewrites) ─────────────
export function useRoute(): string[] {
  const read = () => window.location.hash.replace(/^#\/?/, '').split('?')[0].split('/').filter(Boolean);
  const [r, setR] = useState(read);
  useEffect(() => {
    const f = () => setR(read());
    window.addEventListener('hashchange', f);
    return () => window.removeEventListener('hashchange', f);
  }, []);
  return r;
}
export const go = (path: string) => {
  window.location.hash = '#/' + path.replace(/^\//, '');
};

// ───────────── data loading ─────────────
export type Load<T> = { data?: T; error?: ApiError; loading: boolean; reload: () => void };
export function useLoad<T>(fn: () => Promise<T>, deps: unknown[] = []): Load<T> {
  const [st, setSt] = useState<{ data?: T; error?: ApiError; loading: boolean }>({ loading: true });
  const [n, setN] = useState(0);
  useEffect(() => {
    let live = true;
    setSt((s) => ({ ...s, loading: true, error: undefined }));
    fn().then(
      (data) => live && setSt({ data, loading: false }),
      (error: unknown) => live && setSt((s) => ({ data: s.data, loading: false, error: error instanceof ApiError ? error : new ApiError(0, 'CLIENT', String(error)) })),
    );
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, n]);
  return { ...st, reload: useCallback(() => setN((x) => x + 1), []) };
}

// ───────────── toasts ─────────────
type Toast = { id: number; text: string; bad?: boolean };
const ToastCtx = createContext<(text: string, bad?: boolean) => void>(() => {});
export const useToast = () => useContext(ToastCtx);
export function ToastHost({ children }: { children: React.ReactNode }) {
  const [list, setList] = useState<Toast[]>([]);
  const push = useCallback((text: string, bad?: boolean) => {
    const id = Date.now() + Math.random();
    setList((l) => [...l, { id, text, bad }]);
    setTimeout(() => setList((l) => l.filter((x) => x.id !== id)), 4200);
  }, []);
  return (
    <ToastCtx.Provider value={push}>
      {children}
      <div className="toasts" role="status" aria-live="polite">
        {list.map((x) => (
          <div key={x.id} className={'toast' + (x.bad ? ' bad' : '')}>
            {x.text}
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}

/** Runs an action with a busy flag, toasts the outcome and returns whether it succeeded. */
export function useAction() {
  const toast = useToast();
  const { t } = useT();
  const [busy, setBusy] = useState(false);
  const run = async (fn: () => Promise<unknown>, ok?: string) => {
    setBusy(true);
    try {
      await fn();
      if (ok) toast(ok);
      return true;
    } catch (e) {
      toast(errorText(e, t), true);
      return false;
    } finally {
      setBusy(false);
    }
  };
  return { busy, run };
}

export function errorText(e: unknown, t: I18n['t']): string {
  if (!(e instanceof ApiError)) return t('err.generic');
  if (e.unreachable) return t('err.unreachable');
  if (e.status === 403) return t('err.forbidden');
  if (e.status === 404) return t('err.notFound');
  if (e.status === 409) return t('err.conflict') + (e.message && e.message !== 'CONFLICT' ? ` — ${e.message}` : '');
  if (e.status === 429) return t('err.rate');
  if (e.status === 400 || e.status === 422) return t('err.validation') + (e.message ? ` — ${e.message}` : '');
  return t('err.generic') + (e.message ? ` — ${e.message}` : '');
}

// ───────────── components ─────────────
export function Btn({ kind = 'primary', ...p }: React.ButtonHTMLAttributes<HTMLButtonElement> & { kind?: 'primary' | 'ghost' | 'danger' | 'dark' }) {
  return <button type="button" {...p} className={`btn ${kind} ${p.className ?? ''}`} />;
}

export function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
      {hint && <small>{hint}</small>}
    </label>
  );
}

export function Badge({ tone = 'mist', children }: { tone?: 'wine' | 'ink' | 'mist' | 'line'; children: React.ReactNode }) {
  return <span className={'badge ' + tone}>{children}</span>;
}

export function Page({ title, actions, children }: { title: string; actions?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="page">
      <header className="page-head">
        <h1>{title}</h1>
        <div className="actions">{actions}</div>
      </header>
      {children}
    </section>
  );
}

/** One switch for loading / error / empty / content. */
export function View<T>({ load, empty, children }: { load: Load<T>; empty?: (d: T) => boolean; children: (d: T) => React.ReactNode }) {
  const { t } = useT();
  if (load.error && !load.data)
    return (
      <div className="state">
        <p>{errorText(load.error, t)}</p>
        <Btn kind="ghost" onClick={load.reload}>
          {t('retry')}
        </Btn>
      </div>
    );
  if (!load.data) return <div className="state muted">{t('loading')}</div>;
  if (empty?.(load.data)) return <div className="state muted">{t('empty')}</div>;
  return <>{children(load.data)}</>;
}

/** Modal that asks for a reason (and optional extra fields) before an action. */
export function Dialog({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open) d.showModal();
  }, []);
  return (
    <dialog ref={ref} className="dialog" onClose={onClose} onCancel={onClose}>
      <h2>{title}</h2>
      {children}
    </dialog>
  );
}

export function ReasonDialog({
  title,
  confirm,
  danger,
  min = 5,
  extra,
  onSubmit,
  onClose,
}: {
  title: string;
  confirm: string;
  danger?: boolean;
  min?: number;
  extra?: React.ReactNode;
  onSubmit: (reason: string) => Promise<boolean>;
  onClose: () => void;
}) {
  const { t } = useT();
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const ok = reason.trim().length >= min;
  return (
    <Dialog title={title} onClose={onClose}>
      {extra}
      <Field label={t('reason')} hint={t('reasonHint', { n: min })}>
        <textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={1000} autoFocus />
      </Field>
      <div className="row end">
        <Btn kind="ghost" onClick={onClose}>
          {t('cancel')}
        </Btn>
        <Btn
          kind={danger ? 'danger' : 'primary'}
          disabled={!ok || busy}
          onClick={async () => {
            setBusy(true);
            const done = await onSubmit(reason.trim());
            setBusy(false);
            if (done) onClose();
          }}
        >
          {confirm}
        </Btn>
      </div>
    </Dialog>
  );
}

export function Stat({ label, value, href }: { label: string; value: React.ReactNode; href?: string }) {
  const inner = (
    <>
      <span className="stat-v">{value}</span>
      <span className="stat-l">{label}</span>
    </>
  );
  return href ? (
    <a className="stat link" href={'#/' + href}>
      {inner}
    </a>
  ) : (
    <div className="stat">{inner}</div>
  );
}

export const Logo = ({ light }: { light?: boolean }) => (
  <svg viewBox="0 0 48 48" className="logo" aria-hidden="true">
    <g transform="translate(0 1)" fill={light ? '#FFFFFF' : '#8B0D2B'}>
      <circle cx="17.2" cy="11.4" r="3.4" />
      <circle cx="30.8" cy="11.4" r="3.4" />
      <path d="M24 38.2 13.4 27.6a6 6 0 0 1 8.5-8.5L24 21.2l2.1-2.1a6 6 0 0 1 8.5 8.5Z" fill="none" stroke={light ? '#FFFFFF' : '#8B0D2B'} strokeWidth="3" strokeLinejoin="round" />
    </g>
  </svg>
);

import React, { useState } from 'react';
import { GET, POST } from '../api';
import type { Key } from '../i18n';
import { Badge, Btn, Field, Page, ReasonDialog, useAction, useFmt, useLoad, useT, View } from '../ui';

type Counselor = {
  userId: string;
  kind: string;
  displayName: string;
  headline: string | null;
  bio: string | null;
  yearsExperience: number | null;
  licenseAuthority: string | null;
  licenseCountry: string | null;
  licenseNumber: string | null;
  languages: string[];
  services: string[];
  status: string;
  credentialKeys: string[];
  createdAt: string;
  rejectReason: string | null;
};

export function Counselors() {
  const { t } = useT();
  const f = useFmt();
  const [status, setStatus] = useState('PENDING');
  const load = useLoad(() => GET<Counselor[]>('counselors', { status }), [status]);
  const act = useAction();
  const [rejecting, setRejecting] = useState<Counselor | null>(null);
  const openCredential = (c: Counselor, i: number) =>
    act.run(async () => {
      const r = await GET<{ url: string }>(`counselors/${c.userId}/credentials/${i}`);
      window.open(r.url, '_blank', 'noopener,noreferrer');
    });
  return (
    <Page title={t('nav.counselors')} actions={<Btn kind="ghost" onClick={load.reload}>{t('refresh')}</Btn>}>
      <div className="filters">
        <select value={status} onChange={(e) => setStatus(e.target.value)} aria-label={t('col.status')}>
          {['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'].map((s) => (
            <option key={s} value={s}>
              {t(('cs.' + s) as Key)}
            </option>
          ))}
        </select>
      </div>
      <View load={load} empty={(d) => d.length === 0}>
        {(list) => (
          <div className="cards">
            {list.map((c) => (
              <article key={c.userId} className="panel">
                <header className="row">
                  <strong>{c.displayName}</strong>
                  <Badge tone="line">{t(('acct.' + c.kind) as Key)}</Badge>
                  <Badge tone={c.status === 'APPROVED' ? 'ink' : 'mist'}>{t(('cs.' + c.status) as Key)}</Badge>
                  <span className="push muted small">{f.day(c.createdAt)}</span>
                </header>
                {c.headline && <p>{c.headline}</p>}
                <dl className="kv">
                  <dt>{t('co.license')}</dt>
                  <dd dir="auto">{[c.licenseNumber, c.licenseAuthority, c.licenseCountry].filter(Boolean).join(' · ') || '—'}</dd>
                  <dt>{t('co.years')}</dt>
                  <dd>{c.yearsExperience ?? '—'}</dd>
                  <dt>{t('co.languages')}</dt>
                  <dd>{c.languages.join(', ') || '—'}</dd>
                  <dt>{t('co.services')}</dt>
                  <dd>{c.services.map((s) => t(('svc.' + s) as Key)).join('، ') || '—'}</dd>
                </dl>
                {c.bio && <p className="bio">{c.bio}</p>}
                {c.rejectReason && (
                  <p className="muted">
                    {t('co.rejectReason')}: {c.rejectReason}
                  </p>
                )}
                <div className="row wrap">
                  {c.credentialKeys.map((_, i) => (
                    <Btn key={i} kind="ghost" onClick={() => openCredential(c, i)} disabled={act.busy}>
                      {t('co.document', { n: i + 1 })}
                    </Btn>
                  ))}
                </div>
                {c.status === 'PENDING' && (
                  <div className="row end">
                    <Btn kind="danger" onClick={() => setRejecting(c)}>
                      {t('reject')}
                    </Btn>
                    <Btn disabled={act.busy} onClick={() => void act.run(() => POST(`counselors/${c.userId}/approve`), t('saved')).then((ok) => ok && load.reload())}>
                      {t('approve')}
                    </Btn>
                  </div>
                )}
              </article>
            ))}
          </div>
        )}
      </View>
      {rejecting && (
        <ReasonDialog
          title={t('co.rejectTitle')}
          confirm={t('reject')}
          danger
          onClose={() => setRejecting(null)}
          onSubmit={async (reason) => {
            const ok = await act.run(() => POST(`counselors/${rejecting.userId}/reject`, { reason }), t('saved'));
            if (ok) load.reload();
            return ok;
          }}
        />
      )}
    </Page>
  );
}

type Case = {
  id: string;
  counselorId: string;
  status: string;
  score: number;
  reasons: string[];
  openedAt: string;
  responseDueAt: string | null;
  counselorResponse: string | null;
  counselor: { displayName: string; kind: string; ratingAvg: number | null; ratingCount: number; status: string };
};

export function Integrity() {
  const { t } = useT();
  const f = useFmt();
  const load = useLoad(() => GET<Case[]>('integrity/cases'));
  const act = useAction();
  const [deciding, setDeciding] = useState<Case | null>(null);
  const [decision, setDecision] = useState<'CLEARED' | 'WARNED' | 'SUSPENDED' | 'BANNED'>('CLEARED');
  return (
    <Page title={t('nav.integrity')} actions={<Btn kind="ghost" onClick={load.reload}>{t('refresh')}</Btn>}>
      <p className="muted">{t('int.intro')}</p>
      <View load={load} empty={(d) => d.length === 0}>
        {(list) => (
          <div className="cards">
            {list.map((c) => (
              <article key={c.id} className="panel">
                <header className="row">
                  <a href={'#/users/' + c.counselorId}>
                    <strong>{c.counselor.displayName}</strong>
                  </a>
                  <Badge tone="wine">{t('int.score', { n: c.score })}</Badge>
                  <Badge tone="line">{t(('ic.' + c.status) as Key)}</Badge>
                  <span className="push muted small">{f.date(c.openedAt)}</span>
                </header>
                <ul className="reasons" dir="ltr">
                  {c.reasons.map((r) => (
                    <li key={r}>
                      <code>{r}</code>
                    </li>
                  ))}
                </ul>
                {c.counselorResponse ? <blockquote>{c.counselorResponse}</blockquote> : <p className="muted small">{t('int.noResponse', { d: f.date(c.responseDueAt) })}</p>}
                <div className="row end">
                  <Btn onClick={() => setDeciding(c)}>{t('int.decide')}</Btn>
                </div>
              </article>
            ))}
          </div>
        )}
      </View>
      {deciding && (
        <ReasonDialog
          title={t('int.decide')}
          confirm={t('confirm')}
          danger={decision === 'BANNED' || decision === 'SUSPENDED'}
          min={10}
          extra={
            <Field label={t('int.decision')}>
              <select value={decision} onChange={(e) => setDecision(e.target.value as typeof decision)}>
                {(['CLEARED', 'WARNED', 'SUSPENDED', 'BANNED'] as const).map((s) => (
                  <option key={s} value={s}>
                    {t(('ic.' + s) as Key)}
                  </option>
                ))}
              </select>
            </Field>
          }
          onClose={() => setDeciding(null)}
          onSubmit={async (reason) => {
            const ok = await act.run(() => POST(`integrity/cases/${deciding.id}/decide`, { decision, reason }), t('saved'));
            if (ok) load.reload();
            return ok;
          }}
        />
      )}
    </Page>
  );
}

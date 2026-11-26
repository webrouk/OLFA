import React, { useState } from 'react';
import { GET, POST } from '../api';
import type { Key } from '../i18n';
import { Badge, Btn, Field, Page, ReasonDialog, useAction, useFmt, useLoad, useT, View } from '../ui';

type Report = {
  id: string;
  reason: string;
  details: string | null;
  status: string;
  priority: number;
  targetType: string;
  createdAt: string;
  resolution: string | null;
  reportedUser: { id: string; status: string; profile: { displayName: string } | null } | null;
  reporter: { id: string; profile: { displayName: string } | null } | null;
};

export function Reports() {
  const { t } = useT();
  const f = useFmt();
  const [status, setStatus] = useState('');
  const load = useLoad(() => GET<Report[]>('reports', { status: status || undefined }), [status]);
  const act = useAction();
  const [resolving, setResolving] = useState<{ r: Report; to: 'ACTION_TAKEN' | 'DISMISSED' } | null>(null);
  return (
    <Page title={t('nav.reports')} actions={<Btn kind="ghost" onClick={load.reload}>{t('refresh')}</Btn>}>
      <div className="filters">
        <Field label={t('col.status')}>
          <select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">{t('rep.open')}</option>
            {['OPEN', 'IN_REVIEW', 'ACTION_TAKEN', 'DISMISSED'].map((s) => (
              <option key={s} value={s}>
                {t(('rs.' + s) as Key)}
              </option>
            ))}
          </select>
        </Field>
      </div>
      <View load={load} empty={(d) => d.length === 0}>
        {(list) => (
          <div className="cards">
            {list.map((r) => (
              <article key={r.id} className="panel">
                <header className="row">
                  <strong>{t(('rr.' + r.reason) as Key)}</strong>
                  <Badge tone={r.priority > 0 ? 'wine' : 'mist'}>{t(('rt.' + r.targetType) as Key)}</Badge>
                  <Badge tone="line">{t(('rs.' + r.status) as Key)}</Badge>
                  <span className="muted small push">{f.date(r.createdAt)}</span>
                </header>
                <p>
                  {t('rep.against')}:{' '}
                  {r.reportedUser ? <a href={'#/users/' + r.reportedUser.id}>{r.reportedUser.profile?.displayName ?? r.reportedUser.id.slice(0, 8)}</a> : '—'} · {t('rep.by')}:{' '}
                  {r.reporter ? <a href={'#/users/' + r.reporter.id}>{r.reporter.profile?.displayName ?? r.reporter.id.slice(0, 8)}</a> : '—'}
                </p>
                {r.details && <blockquote>{r.details}</blockquote>}
                {r.resolution && (
                  <p className="muted">
                    {t('rep.resolution')}: {r.resolution}
                  </p>
                )}
                {(r.status === 'OPEN' || r.status === 'IN_REVIEW') && (
                  <div className="row end">
                    <Btn kind="ghost" onClick={() => setResolving({ r, to: 'DISMISSED' })}>
                      {t('rep.dismiss')}
                    </Btn>
                    <Btn onClick={() => setResolving({ r, to: 'ACTION_TAKEN' })}>{t('rep.actionTaken')}</Btn>
                  </div>
                )}
              </article>
            ))}
          </div>
        )}
      </View>
      {resolving && (
        <ReasonDialog
          title={resolving.to === 'DISMISSED' ? t('rep.dismiss') : t('rep.actionTaken')}
          confirm={t('save')}
          min={3}
          extra={resolving.to === 'ACTION_TAKEN' ? <p className="muted small">{t('rep.actionHint')}</p> : undefined}
          onClose={() => setResolving(null)}
          onSubmit={async (resolution) => {
            const ok = await act.run(() => POST(`reports/${resolving.r.id}/resolve`, { status: resolving.to, resolution }), t('saved'));
            if (ok) load.reload();
            return ok;
          }}
        />
      )}
    </Page>
  );
}

import React, { useState } from 'react';
import { GET, POST } from '../api';
import type { Key } from '../i18n';
import { Badge, Btn, Dialog, Field, Page, ReasonDialog, useAction, useFmt, useLoad, useT, View } from '../ui';

type Dispute = {
  id: string;
  status: string;
  service: string;
  durationMinutes: number;
  priceMinor: number;
  currency: string;
  counselorNetMinor: number | null;
  scheduledAt: string | null;
  completedAt: string | null;
  disputeReason: string | null;
  clientId: string;
  counselor: { userId: string; displayName: string };
  conversation: { id: string } | null;
};

export function Disputes() {
  const { t } = useT();
  const f = useFmt();
  const load = useLoad(() => GET<Dispute[]>('consultations/disputes'));
  const act = useAction();
  const [decide, setDecide] = useState<{ d: Dispute; decision: 'RELEASE' | 'REFUND' } | null>(null);
  return (
    <Page title={t('nav.disputes')} actions={<Btn kind="ghost" onClick={load.reload}>{t('refresh')}</Btn>}>
      <p className="muted">{t('dis.intro')}</p>
      <View load={load} empty={(d) => d.length === 0}>
        {(list) => (
          <div className="cards">
            {list.map((d) => (
              <article key={d.id} className="panel">
                <header className="row">
                  <strong>{t(('svc.' + d.service) as Key)}</strong>
                  <Badge tone="wine">{t('dis.held')}</Badge>
                  <span className="push muted small">{f.date(d.scheduledAt)}</span>
                </header>
                <dl className="kv">
                  <dt>{t('dis.counselor')}</dt>
                  <dd>
                    <a href={'#/users/' + d.counselor.userId}>{d.counselor.displayName}</a>
                  </dd>
                  <dt>{t('dis.client')}</dt>
                  <dd>
                    <a href={'#/users/' + d.clientId}>{t('open')}</a>
                  </dd>
                  <dt>{t('dis.fee')}</dt>
                  <dd>{f.money(d.priceMinor, d.currency)}</dd>
                  <dt>{t('dis.net')}</dt>
                  <dd>{f.money(d.counselorNetMinor, d.currency)}</dd>
                  <dt>{t('dis.duration')}</dt>
                  <dd>{t('minutes', { n: d.durationMinutes })}</dd>
                </dl>
                {d.disputeReason && <blockquote>{d.disputeReason}</blockquote>}
                <div className="row end">
                  <Btn kind="ghost" onClick={() => setDecide({ d, decision: 'REFUND' })}>
                    {t('dis.refund')}
                  </Btn>
                  <Btn onClick={() => setDecide({ d, decision: 'RELEASE' })}>{t('dis.release')}</Btn>
                </div>
              </article>
            ))}
          </div>
        )}
      </View>
      {decide && (
        <ReasonDialog
          title={decide.decision === 'RELEASE' ? t('dis.release') : t('dis.refund')}
          confirm={t('confirm')}
          danger={decide.decision === 'REFUND'}
          extra={<p className="muted small">{decide.decision === 'RELEASE' ? t('dis.releaseHint') : t('dis.refundHint')}</p>}
          onClose={() => setDecide(null)}
          onSubmit={async (reason) => {
            const ok = await act.run(() => POST(`consultations/${decide.d.id}/escrow`, { decision: decide.decision, reason }), t('saved'));
            if (ok) load.reload();
            return ok;
          }}
        />
      )}
    </Page>
  );
}

type Withdrawal = {
  id: string;
  counselorId: string;
  amountMinor: number;
  currency: string;
  status: string;
  requestedAt: string;
  providerRef: string | null;
  failureReason: string | null;
  payoutMethod: { kind: string; detailsMask: string; countryCode: string; currency: string; holderName: string };
  counselor: { displayName: string; status: string; integrityCases: { id: string }[] };
};

export function Withdrawals() {
  const { t } = useT();
  const f = useFmt();
  const [status, setStatus] = useState('');
  const load = useLoad(() => GET<Withdrawal[]>('withdrawals', { status: status || undefined }), [status]);
  const act = useAction();
  const [dlg, setDlg] = useState<{ w: Withdrawal; kind: 'paid' | 'reject' | 'failed' | 'reveal' } | null>(null);
  const [ref, setRef] = useState('');
  const [revealed, setRevealed] = useState<Record<string, unknown> | null>(null);
  const reload = () => {
    setDlg(null);
    load.reload();
  };
  return (
    <Page title={t('nav.withdrawals')} actions={<Btn kind="ghost" onClick={load.reload}>{t('refresh')}</Btn>}>
      <div className="filters">
        <select value={status} onChange={(e) => setStatus(e.target.value)} aria-label={t('col.status')}>
          <option value="">{t('wd.pending')}</option>
          {['REQUESTED', 'PROCESSING', 'PAID', 'REJECTED', 'FAILED', 'CANCELLED'].map((s) => (
            <option key={s} value={s}>
              {t(('ws.' + s) as Key)}
            </option>
          ))}
        </select>
      </div>
      <View load={load} empty={(d) => d.length === 0}>
        {(list) => (
          <table className="table">
            <thead>
              <tr>
                <th>{t('dis.counselor')}</th>
                <th>{t('wd.amount')}</th>
                <th>{t('wd.method')}</th>
                <th>{t('col.status')}</th>
                <th>{t('wd.requested')}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {list.map((w) => (
                <tr key={w.id}>
                  <td>
                    <a href={'#/users/' + w.counselorId}>{w.counselor.displayName}</a>
                    {w.counselor.integrityCases.length > 0 && (
                      <>
                        {' '}
                        <Badge tone="wine">{t('wd.integrity')}</Badge>
                      </>
                    )}
                  </td>
                  <td>{f.money(w.amountMinor, w.currency)}</td>
                  <td>
                    {t(('pm.' + w.payoutMethod.kind) as Key)} <span dir="ltr">{w.payoutMethod.detailsMask}</span>
                  </td>
                  <td>
                    <Badge tone="line">{t(('ws.' + w.status) as Key)}</Badge>
                  </td>
                  <td>{f.date(w.requestedAt)}</td>
                  <td className="end nowrap">
                    {(w.status === 'REQUESTED' || w.status === 'PROCESSING') && (
                      <>
                        <Btn kind="ghost" onClick={() => setDlg({ w, kind: 'reveal' })}>
                          {t('wd.reveal')}
                        </Btn>
                        {w.status === 'REQUESTED' && (
                          <Btn kind="ghost" disabled={act.busy} onClick={() => void act.run(() => POST(`withdrawals/${w.id}/processing`), t('saved')).then((ok) => ok && load.reload())}>
                            {t('wd.processing')}
                          </Btn>
                        )}
                        {w.status === 'PROCESSING' && <Btn onClick={() => setDlg({ w, kind: 'paid' })}>{t('wd.paid')}</Btn>}
                        <Btn kind="danger" onClick={() => setDlg({ w, kind: w.status === 'PROCESSING' ? 'failed' : 'reject' })}>
                          {w.status === 'PROCESSING' ? t('wd.failed') : t('reject')}
                        </Btn>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </View>
      {dlg?.kind === 'paid' && (
        <Dialog title={t('wd.paid')} onClose={() => setDlg(null)}>
          <Field label={t('wd.ref')} hint={t('wd.refHint')}>
            <input value={ref} onChange={(e) => setRef(e.target.value)} maxLength={120} dir="ltr" />
          </Field>
          <div className="row end">
            <Btn kind="ghost" onClick={() => setDlg(null)}>
              {t('cancel')}
            </Btn>
            <Btn
              disabled={ref.trim().length < 3 || act.busy}
              onClick={async () => {
                if (await act.run(() => POST(`withdrawals/${dlg.w.id}/paid`, { providerRef: ref.trim() }), t('saved'))) {
                  setRef('');
                  reload();
                }
              }}
            >
              {t('confirm')}
            </Btn>
          </div>
        </Dialog>
      )}
      {(dlg?.kind === 'reject' || dlg?.kind === 'failed') && (
        <ReasonDialog
          title={dlg.kind === 'reject' ? t('wd.rejectTitle') : t('wd.failed')}
          confirm={t('confirm')}
          danger
          extra={<p className="muted small">{t('wd.returnHint')}</p>}
          onClose={() => setDlg(null)}
          onSubmit={async (reason) => {
            const ok = await act.run(() => POST(`withdrawals/${dlg.w.id}/${dlg.kind}`, { reason }), t('saved'));
            if (ok) load.reload();
            return ok;
          }}
        />
      )}
      {dlg?.kind === 'reveal' && (
        <Dialog
          title={t('wd.reveal')}
          onClose={() => {
            setDlg(null);
            setRevealed(null);
          }}
        >
          {!revealed ? (
            <>
              <p>{t('wd.revealHint')}</p>
              <div className="row end">
                <Btn kind="ghost" onClick={() => setDlg(null)}>
                  {t('cancel')}
                </Btn>
                <Btn disabled={act.busy} onClick={() => act.run(async () => setRevealed(await GET<Record<string, unknown>>('withdrawals/' + dlg.w.id)))}>
                  {t('wd.show')}
                </Btn>
              </div>
            </>
          ) : (
            <>
              <dl className="kv" dir="ltr">
                {Object.entries(((revealed.payoutMethod as { details?: Record<string, unknown> } | undefined)?.details ?? {}) as Record<string, unknown>).map(([k, v]) => (
                  <React.Fragment key={k}>
                    <dt>{k}</dt>
                    <dd className="mono">{String(v)}</dd>
                  </React.Fragment>
                ))}
              </dl>
              <p className="muted small">{t('wd.audited')}</p>
              <div className="row end">
                <Btn
                  onClick={() => {
                    setRevealed(null);
                    setDlg(null);
                  }}
                >
                  {t('close')}
                </Btn>
              </div>
            </>
          )}
        </Dialog>
      )}
    </Page>
  );
}

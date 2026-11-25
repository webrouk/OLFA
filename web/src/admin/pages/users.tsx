import React, { useState } from 'react';
import { GET, POST } from '../api';
import type { Key } from '../i18n';
import { Badge, Btn, Field, go, Page, ReasonDialog, useAction, useFmt, useLoad, useT, View } from '../ui';

type Row = { id: string; phone: string; status: string; accountType: string; createdAt: string; lastActiveAt: string | null; suspendedUntil: string | null; profile: { displayName: string; gender: string; countryCode: string; city: string | null } | null };
type List = { total: number; page: number; pageSize: number; items: Row[] };
type UserDetail = Row & {
  phoneCountry: string;
  locale: string;
  frozenAt: string | null;
  restrictionReason: string | null;
  restrictedAt: string | null;
  deletionRequestedAt: string | null;
  profile: (Row['profile'] & { birthDate: string; maritalStatus: string | null; occupation: string | null; bio: string | null }) | null;
  verifications: { type: string; verifiedAt: string }[];
  reportsAgainst: number;
  reportsMade: number;
  openTickets: number;
  history: { action: string; actorType: string; reason: string | null; createdAt: string }[];
  accountManager: { managerName: string; relation: string; phoneHolder: 'OWNER' | 'MANAGER'; ownerConsentAt: string; createdAt: string; revokedAt: string | null; revokedBy: string | null } | null;
};

const STATUSES = ['ACTIVE', 'PENDING_VERIFICATION', 'SUSPENDED', 'RESTRICTED', 'BANNED', 'REJECTED', 'DELETED'];

export const statusTone = (s: string) => (s === 'ACTIVE' ? 'ink' : s === 'BANNED' || s === 'SUSPENDED' ? 'wine' : 'mist');

function queryOf(): Record<string, string> {
  const q = window.location.hash.split('?')[1] ?? '';
  return Object.fromEntries(new URLSearchParams(q));
}

export function Users() {
  const { t } = useT();
  const f = useFmt();
  const init = queryOf();
  const [q, setQ] = useState(init.q ?? '');
  const [applied, setApplied] = useState({ q: init.q ?? '', status: init.status ?? '', accountType: init.accountType ?? '', page: 1 });
  const load = useLoad(() => GET<List>('users', applied), [applied.q, applied.status, applied.accountType, applied.page]);
  return (
    <Page title={t('nav.users')}>
      <form
        className="filters"
        onSubmit={(e) => {
          e.preventDefault();
          setApplied((a) => ({ ...a, q: q.trim(), page: 1 }));
        }}
      >
        <input type="search" placeholder={t('u.search')} value={q} onChange={(e) => setQ(e.target.value)} aria-label={t('u.search')} maxLength={80} />
        <select value={applied.status} onChange={(e) => setApplied((a) => ({ ...a, status: e.target.value, page: 1 }))} aria-label={t('col.status')}>
          <option value="">{t('u.allStatuses')}</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {t(('st.' + s) as Key)}
            </option>
          ))}
        </select>
        <select value={applied.accountType} onChange={(e) => setApplied((a) => ({ ...a, accountType: e.target.value, page: 1 }))} aria-label={t('col.type')}>
          <option value="">{t('u.allTypes')}</option>
          {['MEMBER', 'PSYCHOLOGIST', 'FAMILY_COUNSELOR'].map((s) => (
            <option key={s} value={s}>
              {t(('acct.' + s) as Key)}
            </option>
          ))}
        </select>
        <Btn type="submit">{t('search')}</Btn>
      </form>
      <View load={load} empty={(d) => d.items.length === 0}>
        {(d) => (
          <>
            <p className="muted small">{t('u.total', { n: f.num(d.total) })}</p>
            <table className="table">
              <thead>
                <tr>
                  <th>{t('col.member')}</th>
                  <th>{t('u.phone')}</th>
                  <th>{t('col.type')}</th>
                  <th>{t('col.status')}</th>
                  <th>{t('u.joined')}</th>
                  <th>{t('u.lastActive')}</th>
                </tr>
              </thead>
              <tbody>
                {d.items.map((u) => (
                  <tr key={u.id} className="click" onClick={() => go('users/' + u.id)}>
                    <td>
                      <a href={'#/users/' + u.id}>{u.profile?.displayName ?? '—'}</a>
                    </td>
                    <td dir="ltr">{u.phone}</td>
                    <td>{t(('acct.' + u.accountType) as Key)}</td>
                    <td>
                      <Badge tone={statusTone(u.status)}>{t(('st.' + u.status) as Key)}</Badge>
                    </td>
                    <td>{f.day(u.createdAt)}</td>
                    <td>{f.date(u.lastActiveAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <div className="pager">
              <Btn kind="ghost" disabled={d.page <= 1} onClick={() => setApplied((a) => ({ ...a, page: a.page - 1 }))}>
                {t('prev')}
              </Btn>
              <span>{t('pageOf', { p: d.page, n: Math.max(1, Math.ceil(d.total / d.pageSize)) })}</span>
              <Btn kind="ghost" disabled={d.page * d.pageSize >= d.total} onClick={() => setApplied((a) => ({ ...a, page: a.page + 1 }))}>
                {t('next')}
              </Btn>
            </div>
          </>
        )}
      </View>
    </Page>
  );
}

export function UserDetailPage({ id }: { id: string }) {
  const { t } = useT();
  const f = useFmt();
  const load = useLoad(() => GET<UserDetail>('users/' + id), [id]);
  const act = useAction();
  const [dialog, setDialog] = useState<'ban' | 'suspend' | 'unrestrict' | 'lift' | 'manager' | null>(null);
  const [until, setUntil] = useState('');

  return (
    <Page title={t('u.detail')} actions={<a className="btn ghost" href="#/users">{t('back')}</a>}>
      <View load={load}>
        {(u) => (
          <div className="grid-2">
            <div className="panel">
              <h2>
                {u.profile?.displayName ?? '—'} <Badge tone={statusTone(u.status)}>{t(('st.' + u.status) as Key)}</Badge>
              </h2>
              <dl className="kv">
                <dt>{t('u.phone')}</dt>
                <dd dir="ltr">{u.phone}</dd>
                <dt>{t('col.type')}</dt>
                <dd>{t(('acct.' + u.accountType) as Key)}</dd>
                <dt>{t('u.gender')}</dt>
                <dd>{u.profile?.gender ? t(('g.' + u.profile.gender) as Key) : '—'}</dd>
                <dt>{t('u.birth')}</dt>
                <dd>{f.day(u.profile?.birthDate)}</dd>
                <dt>{t('col.place')}</dt>
                <dd>{[u.profile?.city, u.profile?.countryCode].filter(Boolean).join(' · ') || '—'}</dd>
                <dt>{t('u.occupation')}</dt>
                <dd>{u.profile?.occupation || '—'}</dd>
                <dt>{t('u.joined')}</dt>
                <dd>{f.date(u.createdAt)}</dd>
                <dt>{t('u.lastActive')}</dt>
                <dd>{f.date(u.lastActiveAt)}</dd>
                <dt>{t('u.verified')}</dt>
                <dd>{u.verifications.length ? u.verifications.map((v) => t(('vt.' + v.type) as Key)).join('، ') : '—'}</dd>
                <dt>{t('u.reportsAgainst')}</dt>
                <dd>{u.reportsAgainst}</dd>
                <dt>{t('u.reportsMade')}</dt>
                <dd>{u.reportsMade}</dd>
                <dt>{t('u.openTickets')}</dt>
                <dd>{u.openTickets}</dd>
                {u.deletionRequestedAt && (
                  <>
                    <dt>{t('u.deletion')}</dt>
                    <dd>{f.date(u.deletionRequestedAt)}</dd>
                  </>
                )}
              </dl>
              {u.profile?.bio && <p className="bio">{u.profile.bio}</p>}
              <p className="muted small">{t('u.privacyNote')}</p>
              {u.accountManager && (
                <>
                  <h3>{t('mgr.title')}</h3>
                  {u.accountManager.revokedAt ? (
                    <p className="muted small">{t('mgr.revoked', { d: f.date(u.accountManager.revokedAt), by: t(('mgr.by.' + (u.accountManager.revokedBy ?? 'ACCOUNT')) as Key) })}</p>
                  ) : (
                    <>
                      <dl className="kv">
                        <dt>{t('mgr.relation')}</dt>
                        <dd>{t(('rel.' + u.accountManager.relation) as Key)}</dd>
                        <dt>{t('mgr.name')}</dt>
                        <dd>{u.accountManager.managerName}</dd>
                        <dt>{t('mgr.phone')}</dt>
                        <dd>{t(u.accountManager.phoneHolder === 'OWNER' ? 'mgr.phoneOwner' : 'mgr.phoneManager')}</dd>
                        <dt>{t('mgr.consent')}</dt>
                        <dd>{f.date(u.accountManager.ownerConsentAt)}</dd>
                      </dl>
                      <p className="muted small">{t('mgr.publicNote')}</p>
                      <div className="row end">
                        <Btn kind="danger" onClick={() => setDialog('manager')}>
                          {t('mgr.revoke')}
                        </Btn>
                      </div>
                    </>
                  )}
                </>
              )}
            </div>
            <div className="panel">
              <h2>{t('u.restrictions')}</h2>
              {(u.status === 'SUSPENDED' || u.status === 'BANNED') && (
                <div className="note">
                  <strong>{t(('st.' + u.status) as Key)}</strong>
                  {u.suspendedUntil && <span> — {t('u.until', { d: f.date(u.suspendedUntil) })}</span>}
                  {u.restrictionReason && <p>{u.restrictionReason}</p>}
                </div>
              )}
              <div className="row wrap">
                {u.status !== 'BANNED' && u.status !== 'DELETED' && (
                  <>
                    <Btn kind="ghost" onClick={() => setDialog('suspend')}>
                      {t('u.suspend')}
                    </Btn>
                    <Btn kind="danger" onClick={() => setDialog('ban')}>
                      {t('u.ban')}
                    </Btn>
                  </>
                )}
                {u.status === 'SUSPENDED' && <Btn onClick={() => setDialog('unrestrict')}>{t('u.unrestrict')}</Btn>}
                {u.status === 'BANNED' && <Btn onClick={() => setDialog('lift')}>{t('u.liftBan')}</Btn>}
              </div>
              <h3>{t('u.history')}</h3>
              {u.history.length === 0 ? (
                <p className="muted">{t('empty')}</p>
              ) : (
                <ul className="timeline">
                  {u.history.map((h, i) => (
                    <li key={i}>
                      <code dir="ltr">{h.action}</code> <span className="muted small">{f.date(h.createdAt)}</span>
                      {h.reason && <p>{h.reason}</p>}
                    </li>
                  ))}
                </ul>
              )}
            </div>
            {(dialog === 'ban' || dialog === 'suspend') && (
              <ReasonDialog
                title={dialog === 'ban' ? t('u.banTitle') : t('u.suspendTitle')}
                confirm={dialog === 'ban' ? t('u.ban') : t('u.suspend')}
                danger
                min={3}
                extra={
                  <>
                    <p className="muted small">{dialog === 'ban' ? t('u.banHint') : t('u.suspendHint')}</p>
                    {dialog === 'suspend' && (
                      <Field label={t('u.untilLabel')} hint={t('u.untilHint')}>
                        <input type="datetime-local" value={until} onChange={(e) => setUntil(e.target.value)} />
                      </Field>
                    )}
                  </>
                }
                onClose={() => setDialog(null)}
                onSubmit={async (reason) => {
                  const ok = await act.run(
                    () => POST(`users/${u.id}/restrict`, { action: dialog, reason, ...(dialog === 'suspend' && until ? { until: new Date(until).toISOString() } : {}) }),
                    t('saved'),
                  );
                  if (ok) load.reload();
                  return ok;
                }}
              />
            )}
            {dialog === 'unrestrict' && (
              <ReasonDialog
                title={t('u.unrestrict')}
                confirm={t('u.unrestrict')}
                min={3}
                onClose={() => setDialog(null)}
                onSubmit={async (reason) => {
                  const ok = await act.run(() => POST(`users/${u.id}/unrestrict`, { reason }), t('saved'));
                  if (ok) load.reload();
                  return ok;
                }}
              />
            )}
            {dialog === 'manager' && (
              <ReasonDialog
                title={t('mgr.revoke')}
                confirm={t('mgr.revoke')}
                danger
                min={3}
                extra={<p className="muted small">{t('mgr.revokeHint')}</p>}
                onClose={() => setDialog(null)}
                onSubmit={async (reason) => {
                  const ok = await act.run(() => POST(`users/${u.id}/manager/revoke`, { reason }), t('saved'));
                  if (ok) load.reload();
                  return ok;
                }}
              />
            )}
            {dialog === 'lift' && (
              <ReasonDialog
                title={t('u.liftBan')}
                confirm={t('u.liftBan')}
                min={10}
                onClose={() => setDialog(null)}
                onSubmit={async (reason) => {
                  const ok = await act.run(() => POST(`users/${u.id}/lift-ban`, { reason }), t('saved'));
                  if (ok) load.reload();
                  return ok;
                }}
              />
            )}
          </div>
        )}
      </View>
    </Page>
  );
}

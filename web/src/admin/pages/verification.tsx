import React, { useState } from 'react';
import { GET, POST } from '../api';
import type { Key } from '../i18n';
import { Badge, Btn, Dialog, Field, go, Page, useAction, useFmt, useLoad, useT, View } from '../ui';

type QueueItem = { id: string; type: 'PROFILE_REVIEW' | 'LIVENESS'; userId: string; submittedAt: string; preferFemaleReviewer: boolean; user: { profile: { displayName: string; countryCode: string; city: string | null } | null } };
type Photo = { id: string; position: number; status: string; url: string };
type Detail = {
  id: string;
  type: string;
  status: string;
  submittedAt: string;
  autoResult: Record<string, unknown> | null;
  profile: { displayName: string; gender: string; birthDate: string; countryCode: string; city: string | null; bio: string | null; occupation: string | null } | null;
  accountStatus: string;
  photos: Photo[];
  reportsAgainst: number;
  selfie: null | { requestId: string; status: string; gesture: string | null; preferFemaleReviewer: boolean; checks: Record<string, unknown> | null; url: string | null; criteria: string[] };
};

const REJECT_CODES = [
  'photo_unclear',
  'photo_not_you',
  'photo_group',
  'photo_inappropriate',
  'photo_filtered',
  'bio_contact_info',
  'bio_inappropriate',
  'name_invalid',
  'suspected_fake',
  'selfie_no_face',
  'selfie_multiple_faces',
  'selfie_face_covered',
  'selfie_blurry',
  'selfie_dark',
  'selfie_gesture_wrong',
  'selfie_not_match',
  'selfie_not_live',
  'other',
] as const;

export function VerificationQueue() {
  const { t } = useT();
  const f = useFmt();
  const load = useLoad(() => GET<QueueItem[]>('verification/queue'));
  return (
    <Page title={t('nav.verification')} actions={<Btn kind="ghost" onClick={load.reload}>{t('refresh')}</Btn>}>
      <p className="muted">{t('ver.intro')}</p>
      <View load={load} empty={(d) => d.length === 0}>
        {(list) => (
          <table className="table">
            <thead>
              <tr>
                <th>{t('col.member')}</th>
                <th>{t('col.type')}</th>
                <th>{t('col.place')}</th>
                <th>{t('col.submitted')}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {list.map((r) => (
                <tr key={r.id} className="click" onClick={() => go('verification/' + r.id)}>
                  <td>
                    {r.user.profile?.displayName ?? '—'} {r.preferFemaleReviewer && <Badge tone="wine">{t('ver.female')}</Badge>}
                  </td>
                  <td>{r.type === 'LIVENESS' ? t('ver.selfieOnly') : t('ver.profile')}</td>
                  <td>{[r.user.profile?.city, r.user.profile?.countryCode].filter(Boolean).join(' · ') || '—'}</td>
                  <td>{f.date(r.submittedAt)}</td>
                  <td className="end">
                    <a href={'#/verification/' + r.id}>{t('open')}</a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </View>
    </Page>
  );
}

export function VerificationDetail({ id }: { id: string }) {
  const { t } = useT();
  const f = useFmt();
  const load = useLoad(() => GET<Detail>('verification/' + id), [id]);
  const act = useAction();
  const [rejectPhotos, setRejectPhotos] = useState<string[]>([]);
  const [checked, setChecked] = useState<string[]>([]);
  const [rejecting, setRejecting] = useState(false);

  return (
    <Page title={t('ver.review')} actions={<a className="btn ghost" href="#/verification">{t('back')}</a>}>
      <View load={load}>
        {(d) => {
          const allCriteria = d.selfie ? d.selfie.criteria.every((c) => checked.includes(c)) : true;
          const approve = () =>
            act.run(async () => {
              await POST(`verification/${d.id}/approve`, rejectPhotos.length ? { rejectPhotoIds: rejectPhotos } : {});
              go('verification');
            }, t('ver.approved'));
          return (
            <div className="grid-2">
              <div className="panel">
                <h2>{d.profile?.displayName ?? '—'}</h2>
                <dl className="kv">
                  <dt>{t('col.type')}</dt>
                  <dd>{d.type === 'LIVENESS' ? t('ver.selfieOnly') : t('ver.profile')}</dd>
                  <dt>{t('u.gender')}</dt>
                  <dd>{d.profile?.gender ? t(('g.' + d.profile.gender) as Key) : '—'}</dd>
                  <dt>{t('u.birth')}</dt>
                  <dd>{f.day(d.profile?.birthDate)}</dd>
                  <dt>{t('col.place')}</dt>
                  <dd>{[d.profile?.city, d.profile?.countryCode].filter(Boolean).join(' · ') || '—'}</dd>
                  <dt>{t('u.occupation')}</dt>
                  <dd>{d.profile?.occupation || '—'}</dd>
                  <dt>{t('u.reportsAgainst')}</dt>
                  <dd>{d.reportsAgainst}</dd>
                  <dt>{t('col.submitted')}</dt>
                  <dd>{f.date(d.submittedAt)}</dd>
                </dl>
                {d.profile?.bio && <p className="bio">{d.profile.bio}</p>}
                <h3>{t('ver.photos')}</h3>
                <p className="muted small">{t('ver.photosHint')}</p>
                <div className="photos">
                  {d.photos.map((p) => {
                    const off = rejectPhotos.includes(p.id);
                    return (
                      <button
                        type="button"
                        key={p.id}
                        className={'photo' + (off ? ' off' : '')}
                        aria-pressed={off}
                        onClick={() => setRejectPhotos((l) => (off ? l.filter((x) => x !== p.id) : [...l, p.id]))}
                      >
                        <img src={p.url} alt={t('ver.photoN', { n: p.position + 1 })} loading="lazy" referrerPolicy="no-referrer" />
                        <span>{off ? t('ver.willReject') : t(('ps.' + p.status) as Key)}</span>
                      </button>
                    );
                  })}
                </div>
              </div>
              <div className="panel">
                <h2>{t('ver.selfie')}</h2>
                {!d.selfie ? (
                  <p className="muted">{t('ver.noSelfie')}</p>
                ) : (
                  <>
                    {d.selfie.preferFemaleReviewer && <p className="note">{t('ver.femaleNote')}</p>}
                    <div className="selfie">{d.selfie.url ? <img src={d.selfie.url} alt={t('ver.selfie')} referrerPolicy="no-referrer" /> : <span className="muted">—</span>}</div>
                    <p>
                      {t('ver.gesture')}: <strong>{d.selfie.gesture ? t(('gesture.' + d.selfie.gesture) as Key) : '—'}</strong>
                    </p>
                    {d.selfie.checks && (
                      <details>
                        <summary>{t('ver.autoChecks')}</summary>
                        <pre dir="ltr">{JSON.stringify(d.selfie.checks, null, 2)}</pre>
                      </details>
                    )}
                    <h3>{t('ver.criteria')}</h3>
                    <ul className="checks">
                      {d.selfie.criteria.map((c) => (
                        <li key={c}>
                          <label>
                            <input type="checkbox" checked={checked.includes(c)} onChange={(e) => setChecked((l) => (e.target.checked ? [...l, c] : l.filter((x) => x !== c)))} />
                            <span>
                              <strong>{t(('crit.' + c) as Key)}</strong>
                              <small>{t(('crit.' + c + '.d') as Key)}</small>
                            </span>
                          </label>
                        </li>
                      ))}
                    </ul>
                  </>
                )}
                <div className="row end sticky-actions">
                  <Btn kind="danger" onClick={() => setRejecting(true)} disabled={act.busy}>
                    {t('reject')}
                  </Btn>
                  <Btn onClick={approve} disabled={act.busy || !allCriteria}>
                    {rejectPhotos.length ? t('ver.approveExcept', { n: rejectPhotos.length }) : t('approve')}
                  </Btn>
                </div>
                {!allCriteria && <p className="muted small">{t('ver.checkAll')}</p>}
              </div>
              {rejecting && <RejectDialog id={d.id} photoIds={rejectPhotos} onClose={() => setRejecting(false)} />}
            </div>
          );
        }}
      </View>
    </Page>
  );
}

function RejectDialog({ id, photoIds, onClose }: { id: string; photoIds: string[]; onClose: () => void }) {
  const { t } = useT();
  const act = useAction();
  const [code, setCode] = useState<string>('photo_unclear');
  const [reason, setReason] = useState('');
  return (
    <Dialog title={t('ver.rejectTitle')} onClose={onClose}>
      <Field label={t('ver.code')}>
        <select value={code} onChange={(e) => setCode(e.target.value)}>
          {REJECT_CODES.map((c) => (
            <option key={c} value={c}>
              {t(('rc.' + c) as Key)}
            </option>
          ))}
        </select>
      </Field>
      <Field label={t('ver.reasonUser')} hint={t('reasonHint', { n: 5 })}>
        <textarea rows={3} maxLength={300} value={reason} onChange={(e) => setReason(e.target.value)} />
      </Field>
      {photoIds.length > 0 && <p className="muted small">{t('ver.rejectPhotosOnly', { n: photoIds.length })}</p>}
      <div className="row end">
        <Btn kind="ghost" onClick={onClose}>
          {t('cancel')}
        </Btn>
        <Btn
          kind="danger"
          disabled={act.busy || reason.trim().length < 5}
          onClick={async () => {
            const ok = await act.run(() => POST(`verification/${id}/reject`, { code, reason: reason.trim(), ...(photoIds.length ? { photoIds } : {}) }), t('ver.rejected'));
            if (ok) {
              onClose();
              go('verification');
            }
          }}
        >
          {t('reject')}
        </Btn>
      </div>
    </Dialog>
  );
}

import React, { useState } from 'react';
import { GET, POST, PUT } from '../api';
import type { Key, Lang } from '../i18n';
import { Badge, Btn, Dialog, Field, Page, Stat, useAction, useLoad, useT, View } from '../ui';

type I18n = { ar: string; en: string; fr: string };
type Option = { key: string; value: number; label: I18n };
type Question = {
  id: string;
  topic: string;
  domain: Domain;
  audience: 'ALL' | 'MALE' | 'FEMALE';
  prompt: I18n;
  options: Option[];
  weight: number;
  scoring: 'SCALE' | 'MATCH';
  active: boolean;
  sortOrder: number;
  _count?: { answers: number };
};
type Domain = 'FINANCE' | 'FUTURE' | 'FAMILY_ROLES' | 'LIFESTYLE' | 'MARRIAGE';
type Stats = {
  enabled: boolean;
  started: number;
  finished: number;
  completionRate: number;
  averageScore: number | null;
  last30Days: { started: number; finished: number };
  distribution: { bucket: string; count: number }[];
  domains: { domain: Domain; averageScore: number | null }[];
};

const DOMAINS: Domain[] = ['FINANCE', 'FUTURE', 'FAMILY_ROLES', 'LIFESTYLE', 'MARRIAGE'];
const TOPIC = /^[a-z][a-z0-9_]{1,39}$/;
const OPT_KEY = /^[a-z0-9_]{1,20}$/;
const blank = (): Question => ({
  id: '',
  topic: '',
  domain: 'LIFESTYLE',
  audience: 'ALL',
  prompt: { ar: '', en: '', fr: '' },
  options: [
    { key: 'o0', value: 0, label: { ar: '', en: '', fr: '' } },
    { key: 'o1', value: 1, label: { ar: '', en: '', fr: '' } },
  ],
  weight: 3,
  scoring: 'SCALE',
  active: true,
  sortOrder: 0,
});

/** What is wrong with a question before it is sent (the server and the database check again). */
function problems(q: Question): Key[] {
  const out: Key[] = [];
  if (!TOPIC.test(q.topic)) out.push('cq.badTopic');
  if (!q.prompt.ar.trim() || !q.prompt.en.trim() || !q.prompt.fr.trim()) out.push('cq.needPrompt');
  if (q.options.length < 2 || q.options.length > 6) out.push('cq.optCount');
  if (q.options.some((o) => !OPT_KEY.test(o.key) || !Number.isInteger(o.value) || o.value < 0 || o.value > 10 || !o.label.ar.trim() || !o.label.en.trim() || !o.label.fr.trim())) out.push('cq.badOption');
  if (new Set(q.options.map((o) => o.key)).size !== q.options.length) out.push('cq.dupKey');
  if (!Number.isInteger(q.weight) || q.weight < 1 || q.weight > 10) out.push('cq.badWeight');
  return out;
}

export function CompatPage() {
  const { t, lang } = useT();
  const stats = useLoad(() => GET<Stats>('compat/stats'));
  const list = useLoad(() => GET<Question[]>('compat/questions'));
  const act = useAction();
  const [edit, setEdit] = useState<Question | null>(null);
  const reload = () => {
    stats.reload();
    list.reload();
  };

  return (
    <Page title={t('nav.compat')} actions={<Btn onClick={() => setEdit(blank())}>{t('cq.new')}</Btn>}>
      <p className="muted">{t('cq.intro')}</p>
      <View load={stats}>
        {(s) => (
          <div className="panel">
            <div className="row wrap" style={{ justifyContent: 'space-between' }}>
              <h2>{t('cq.usage')}</h2>
              <label className="inline">
                <input
                  type="checkbox"
                  checked={s.enabled}
                  onChange={async (e) => {
                    const ok = await act.run(() => PUT('compat/enabled', { active: e.target.checked }), t('saved'));
                    if (ok) stats.reload();
                  }}
                />
                {t('cq.enabled')}
              </label>
            </div>
            <div className="stats">
              <Stat label={t('cq.started')} value={s.started} />
              <Stat label={t('cq.finished')} value={s.finished} />
              <Stat label={t('cq.rate')} value={`${s.completionRate}%`} />
              <Stat label={t('cq.avg')} value={s.averageScore == null ? '—' : `${s.averageScore}%`} />
              <Stat label={t('cq.last30')} value={`${s.last30Days.finished}/${s.last30Days.started}`} />
            </div>
            <div className="grid-2">
              <div>
                <h3>{t('cq.distribution')}</h3>
                <Bars rows={s.distribution.map((d) => ({ label: d.bucket + '%', value: d.count }))} max={Math.max(1, ...s.distribution.map((d) => d.count))} />
              </div>
              <div>
                <h3>{t('cq.byDomain')}</h3>
                <Bars rows={s.domains.map((d) => ({ label: t(('cd.' + d.domain) as Key), value: d.averageScore ?? 0, suffix: d.averageScore == null ? '—' : '%' }))} max={100} />
              </div>
            </div>
            <p className="muted small">{t('cq.privacy')}</p>
          </div>
        )}
      </View>
      <View load={list} empty={(d) => d.length === 0}>
        {(qs) => (
          <>
            {DOMAINS.map((d) => {
              const rows = qs.filter((q) => q.domain === d);
              if (!rows.length) return null;
              return (
                <div className="panel" key={d}>
                  <h2>{t(('cd.' + d) as Key)}</h2>
                  <table className="table">
                    <thead>
                      <tr>
                        <th>{t('cq.question')}</th>
                        <th>{t('cq.audience')}</th>
                        <th>{t('cq.weight')}</th>
                        <th>{t('cq.answers')}</th>
                        <th>{t('cq.state')}</th>
                        <th />
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((q) => (
                        <tr key={q.id}>
                          <td>
                            <div>{q.prompt[lang as Lang]}</div>
                            <code dir="ltr" className="small muted">
                              {q.topic}
                            </code>{' '}
                            <span className="muted small">· {q.options.length} {t('cq.optionsShort')}</span>
                          </td>
                          <td>{t(('aud.' + q.audience) as Key)}</td>
                          <td>{q.weight}</td>
                          <td>{q._count?.answers ?? 0}</td>
                          <td>
                            <label className="inline">
                              <input
                                type="checkbox"
                                checked={q.active}
                                onChange={async (e) => {
                                  const ok = await act.run(() => POST(`compat/questions/${q.id}/active`, { active: e.target.checked }), t('saved'));
                                  if (ok) list.reload();
                                }}
                              />
                              {q.active ? <Badge tone="ink">{t('cq.on')}</Badge> : <Badge tone="mist">{t('cq.off')}</Badge>}
                            </label>
                          </td>
                          <td>
                            <Btn kind="ghost" onClick={() => setEdit(structuredClone(q))}>
                              {t('edit')}
                            </Btn>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              );
            })}
          </>
        )}
      </View>
      {edit && <QuestionDialog q={edit} onClose={() => setEdit(null)} onSaved={reload} />}
    </Page>
  );
}

function Bars({ rows, max }: { rows: { label: string; value: number; suffix?: string }[]; max: number }) {
  return (
    <ul className="bars">
      {rows.map((r) => (
        <li key={r.label}>
          <span className="bar-l">{r.label}</span>
          <span className="bar-t">
            <span className="bar-f" style={{ width: `${Math.round((100 * r.value) / max)}%` }} />
          </span>
          <span className="bar-v" dir="ltr">
            {r.suffix === '—' ? '—' : `${r.value}${r.suffix ?? ''}`}
          </span>
        </li>
      ))}
    </ul>
  );
}

function QuestionDialog({ q: initial, onClose, onSaved }: { q: Question; onClose: () => void; onSaved: () => void }) {
  const { t } = useT();
  const act = useAction();
  const [q, setQ] = useState<Question>(initial);
  const answered = (initial._count?.answers ?? 0) > 0;
  const issues = problems(q);
  const langs: Lang[] = ['ar', 'en', 'fr'];
  const setOpt = (i: number, o: Partial<Option>) => setQ({ ...q, options: q.options.map((x, j) => (j === i ? { ...x, ...o } : x)) });

  return (
    <Dialog title={q.id ? t('cq.editTitle') : t('cq.new')} onClose={onClose}>
      <div className="row wrap">
        <Field label={t('cq.topic')} hint={t('cq.topicHint')}>
          <input dir="ltr" value={q.topic} maxLength={40} onChange={(e) => setQ({ ...q, topic: e.target.value.trim().toLowerCase() })} aria-invalid={!TOPIC.test(q.topic)} />
        </Field>
        <Field label={t('cq.domain')}>
          <select value={q.domain} onChange={(e) => setQ({ ...q, domain: e.target.value as Domain })}>
            {DOMAINS.map((d) => (
              <option key={d} value={d}>
                {t(('cd.' + d) as Key)}
              </option>
            ))}
          </select>
        </Field>
        <Field label={t('cq.audience')} hint={t('cq.audienceHint')}>
          <select value={q.audience} onChange={(e) => setQ({ ...q, audience: e.target.value as Question['audience'] })}>
            {(['ALL', 'MALE', 'FEMALE'] as const).map((a) => (
              <option key={a} value={a}>
                {t(('aud.' + a) as Key)}
              </option>
            ))}
          </select>
        </Field>
      </div>
      <div className="row wrap">
        <Field label={t('cq.weight')} hint={t('cq.weightHint')}>
          <input type="number" min={1} max={10} value={q.weight} onChange={(e) => setQ({ ...q, weight: Math.trunc(Number(e.target.value)) })} />
        </Field>
        <Field label={t('cq.scoring')} hint={t(q.scoring === 'SCALE' ? 'cq.scaleHint' : 'cq.matchHint')}>
          <select value={q.scoring} onChange={(e) => setQ({ ...q, scoring: e.target.value as Question['scoring'] })}>
            <option value="SCALE">{t('cq.scale')}</option>
            <option value="MATCH">{t('cq.match')}</option>
          </select>
        </Field>
        <Field label={t('cq.order')}>
          <input type="number" min={0} value={q.sortOrder} onChange={(e) => setQ({ ...q, sortOrder: Math.max(0, Math.trunc(Number(e.target.value))) })} />
        </Field>
      </div>
      {langs.map((l) => (
        <Field key={l} label={`${t('cq.question')} (${l.toUpperCase()})`}>
          <input dir={l === 'ar' ? 'rtl' : 'ltr'} value={q.prompt[l]} maxLength={300} onChange={(e) => setQ({ ...q, prompt: { ...q.prompt, [l]: e.target.value } })} />
        </Field>
      ))}
      <h3>{t('cq.options')}</h3>
      {answered && <p className="note small">{t('cq.frozen')}</p>}
      {q.options.map((o, i) => (
        <div className="option-row" key={i}>
          <input dir="ltr" className="narrow" value={o.key} maxLength={20} disabled={answered} onChange={(e) => setOpt(i, { key: e.target.value })} aria-label={t('cq.optKey')} />
          <input type="number" className="narrow" min={0} max={10} value={o.value} disabled={answered} onChange={(e) => setOpt(i, { value: Math.trunc(Number(e.target.value)) })} aria-label={t('cq.optValue')} />
          {langs.map((l) => (
            <input key={l} dir={l === 'ar' ? 'rtl' : 'ltr'} placeholder={l.toUpperCase()} value={o.label[l]} maxLength={300} disabled={answered} onChange={(e) => setOpt(i, { label: { ...o.label, [l]: e.target.value } })} />
          ))}
          {!answered && q.options.length > 2 && (
            <Btn kind="ghost" onClick={() => setQ({ ...q, options: q.options.filter((_, j) => j !== i) })}>
              {t('remove')}
            </Btn>
          )}
        </div>
      ))}
      {!answered && q.options.length < 6 && (
        <Btn kind="ghost" onClick={() => setQ({ ...q, options: [...q.options, { key: `o${q.options.length}`, value: q.options.length, label: { ar: '', en: '', fr: '' } }] })}>
          {t('cq.addOption')}
        </Btn>
      )}
      <p className="muted small">{t('cq.valueHint')}</p>
      {issues.length > 0 && (
        <ul className="err small">
          {issues.map((k) => (
            <li key={k}>{t(k)}</li>
          ))}
        </ul>
      )}
      <div className="row end">
        <Btn kind="ghost" onClick={onClose}>
          {t('cancel')}
        </Btn>
        <Btn
          disabled={issues.length > 0 || act.busy}
          onClick={async () => {
            const body = {
              topic: q.topic,
              domain: q.domain,
              audience: q.audience,
              prompt: { ar: q.prompt.ar.trim(), en: q.prompt.en.trim(), fr: q.prompt.fr.trim() },
              options: q.options.map((o) => ({ key: o.key.trim(), value: o.value, label: { ar: o.label.ar.trim(), en: o.label.en.trim(), fr: o.label.fr.trim() } })),
              weight: q.weight,
              scoring: q.scoring,
              sortOrder: q.sortOrder,
              active: q.active,
            };
            const ok = await act.run(() => (q.id ? PUT(`compat/questions/${q.id}`, body) : POST('compat/questions', body)), t('saved'));
            if (ok) {
              onSaved();
              onClose();
            }
          }}
        >
          {t('save')}
        </Btn>
      </div>
    </Dialog>
  );
}

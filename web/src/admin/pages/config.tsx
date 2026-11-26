import React, { useState } from 'react';
import { DEL, GET, POST, PUT } from '../api';
import type { Key } from '../i18n';
import { Badge, Btn, Dialog, Field, Page, useAction, useFmt, useLoad, useT, View } from '../ui';

type L3 = { ar: string; en: string; fr: string };
type Faq = { id: string; category: string; question: L3; answer: L3; sortOrder: number; published: boolean };
const CATS = ['PAYMENT', 'ACCOUNT', 'VERIFICATION', 'TECHNICAL', 'OTHER'];
const blank = (): Omit<Faq, 'id'> => ({ category: 'ACCOUNT', question: { ar: '', en: '', fr: '' }, answer: { ar: '', en: '', fr: '' }, sortOrder: 0, published: true });

export function FaqPage() {
  const { t, lang } = useT();
  const load = useLoad(() => GET<Faq[]>('support/faq'));
  const act = useAction();
  const [edit, setEdit] = useState<(Omit<Faq, 'id'> & { id?: string }) | null>(null);
  const complete = (e: Omit<Faq, 'id'>) => (['ar', 'en', 'fr'] as const).every((l) => e.question[l].trim() && e.answer[l].trim());
  return (
    <Page title={t('nav.faq')} actions={<Btn onClick={() => setEdit(blank())}>{t('faq.add')}</Btn>}>
      <p className="muted">{t('faq.intro')}</p>
      <View load={load} empty={(d) => d.length === 0}>
        {(list) => (
          <table className="table">
            <thead>
              <tr>
                <th>{t('faq.question')}</th>
                <th>{t('sup.category')}</th>
                <th>{t('faq.order')}</th>
                <th>{t('col.status')}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {list.map((x) => (
                <tr key={x.id}>
                  <td>{x.question[lang] || x.question.en}</td>
                  <td>{t(('tc.' + x.category) as Key)}</td>
                  <td>{x.sortOrder}</td>
                  <td>
                    <Badge tone={x.published ? 'ink' : 'mist'}>{x.published ? t('faq.published') : t('faq.hidden')}</Badge>
                  </td>
                  <td className="end nowrap">
                    <Btn kind="ghost" onClick={() => setEdit({ ...x })}>
                      {t('edit')}
                    </Btn>
                    <Btn
                      kind="danger"
                      disabled={act.busy}
                      onClick={() => {
                        if (window.confirm(t('faq.confirmDelete'))) void act.run(() => DEL('support/faq/' + x.id), t('saved')).then((ok) => ok && load.reload());
                      }}
                    >
                      {t('delete')}
                    </Btn>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </View>
      {edit && (
        <Dialog title={edit.id ? t('faq.edit') : t('faq.add')} onClose={() => setEdit(null)}>
          <div className="row">
            <Field label={t('sup.category')}>
              <select value={edit.category} onChange={(e) => setEdit({ ...edit, category: e.target.value })}>
                {CATS.map((c) => (
                  <option key={c} value={c}>
                    {t(('tc.' + c) as Key)}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={t('faq.order')}>
              <input type="number" min={0} max={999} value={edit.sortOrder} onChange={(e) => setEdit({ ...edit, sortOrder: Math.max(0, Math.min(999, Number(e.target.value) || 0)) })} />
            </Field>
            <label className="inline">
              <input type="checkbox" checked={edit.published} onChange={(e) => setEdit({ ...edit, published: e.target.checked })} />
              {t('faq.published')}
            </label>
          </div>
          {(['ar', 'en', 'fr'] as const).map((l) => (
            <fieldset key={l} className="lang-block" dir={l === 'ar' ? 'rtl' : 'ltr'} lang={l}>
              <legend>{t(('lang.' + l) as Key)}</legend>
              <Field label={t('faq.question')}>
                <input value={edit.question[l]} maxLength={300} onChange={(e) => setEdit({ ...edit, question: { ...edit.question, [l]: e.target.value } })} />
              </Field>
              <Field label={t('faq.answer')}>
                <textarea rows={3} maxLength={3000} value={edit.answer[l]} onChange={(e) => setEdit({ ...edit, answer: { ...edit.answer, [l]: e.target.value } })} />
              </Field>
            </fieldset>
          ))}
          {!complete(edit) && <p className="muted small">{t('faq.allLangs')}</p>}
          <div className="row end">
            <Btn kind="ghost" onClick={() => setEdit(null)}>
              {t('cancel')}
            </Btn>
            <Btn
              disabled={act.busy || !complete(edit)}
              onClick={async () => {
                const { id, ...body } = edit;
                const payload = { ...body, question: trim3(body.question), answer: trim3(body.answer) };
                const ok = await act.run(() => (id ? PUT('support/faq/' + id, payload) : POST('support/faq', payload)), t('saved'));
                if (ok) {
                  setEdit(null);
                  load.reload();
                }
              }}
            >
              {t('save')}
            </Btn>
          </div>
        </Dialog>
      )}
    </Page>
  );
}
const trim3 = (x: L3): L3 => ({ ar: x.ar.trim(), en: x.en.trim(), fr: x.fr.trim() });

type Setting = { key: string; value: unknown; description: string | null; updatedAt: string };

export function Settings() {
  const { t } = useT();
  const f = useFmt();
  const load = useLoad(() => GET<Setting[]>('settings'));
  const act = useAction();
  const [edit, setEdit] = useState<{ key: string; text: string; description: string | null } | null>(null);
  let parsed: { ok: boolean; value?: unknown } = { ok: false };
  if (edit) {
    try {
      parsed = { ok: true, value: JSON.parse(edit.text) };
    } catch {
      parsed = { ok: false };
    }
  }
  return (
    <Page title={t('nav.settings')}>
      <p className="muted">{t('set.intro')}</p>
      <View load={load} empty={(d) => d.length === 0}>
        {(list) => (
          <table className="table">
            <thead>
              <tr>
                <th>{t('set.key')}</th>
                <th>{t('set.value')}</th>
                <th>{t('set.updated')}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {list.map((s) => (
                <tr key={s.key}>
                  <td>
                    <code dir="ltr">{s.key}</code>
                    {s.description && <small className="muted block">{s.description}</small>}
                  </td>
                  <td>
                    <code dir="ltr" className="mono">{JSON.stringify(s.value)}</code>
                  </td>
                  <td>{f.date(s.updatedAt)}</td>
                  <td className="end">
                    <Btn kind="ghost" onClick={() => setEdit({ key: s.key, text: JSON.stringify(s.value, null, 2), description: s.description })}>
                      {t('edit')}
                    </Btn>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </View>
      {edit && (
        <Dialog title={edit.key} onClose={() => setEdit(null)}>
          {edit.description && <p className="muted">{edit.description}</p>}
          <Field label={t('set.json')} hint={parsed.ok ? t('set.valid') : t('set.invalid')}>
            <textarea dir="ltr" rows={8} className="mono" value={edit.text} onChange={(e) => setEdit({ ...edit, text: e.target.value })} />
          </Field>
          <div className="row end">
            <Btn kind="ghost" onClick={() => setEdit(null)}>
              {t('cancel')}
            </Btn>
            <Btn
              disabled={!parsed.ok || act.busy}
              onClick={async () => {
                const ok = await act.run(() => PUT('settings/' + encodeURIComponent(edit.key), { value: parsed.value }), t('saved'));
                if (ok) {
                  setEdit(null);
                  load.reload();
                }
              }}
            >
              {t('save')}
            </Btn>
          </div>
        </Dialog>
      )}
    </Page>
  );
}

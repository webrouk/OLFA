import React, { useEffect, useRef, useState } from 'react';
import { GET, POST, PUT, uploadAttachment } from '../api';
import type { Key } from '../i18n';
import { Badge, Btn, go, Page, useAction, useFmt, useLoad, useT, View } from '../ui';

type Ticket = { id: string; userId: string; category: string; subject: string; status: string; createdAt: string; lastMessageAt: string; staffLastReadAt: string | null };
type Attachment = { id: string; fileName: string; mime: string; bytes: number; url: string };
type Thread = Omit<Ticket, 'lastMessageAt' | 'staffLastReadAt'> & { messages: { id: string; authorType: 'USER' | 'ADMIN' | 'SYSTEM'; body: string; createdAt: string; attachments: Attachment[] }[] };

const STATUSES = ['OPEN', 'PENDING_USER', 'RESOLVED', 'CLOSED'];
const MIMES = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
const MAX_BYTES = 10 * 1024 * 1024;

export function Tickets() {
  const { t } = useT();
  const f = useFmt();
  const [status, setStatus] = useState('');
  const load = useLoad(() => GET<Ticket[]>('support/tickets', { status: status || undefined }), [status]);
  return (
    <Page title={t('nav.support')} actions={<Btn kind="ghost" onClick={load.reload}>{t('refresh')}</Btn>}>
      <div className="filters">
        <select value={status} onChange={(e) => setStatus(e.target.value)} aria-label={t('col.status')}>
          <option value="">{t('sup.active')}</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {t(('ts.' + s) as Key)}
            </option>
          ))}
        </select>
      </div>
      <View load={load} empty={(d) => d.length === 0}>
        {(list) => (
          <table className="table">
            <thead>
              <tr>
                <th>{t('sup.subject')}</th>
                <th>{t('sup.category')}</th>
                <th>{t('col.status')}</th>
                <th>{t('sup.last')}</th>
              </tr>
            </thead>
            <tbody>
              {list.map((x) => {
                const unread = !x.staffLastReadAt || new Date(x.lastMessageAt) > new Date(x.staffLastReadAt);
                return (
                  <tr key={x.id} className="click" onClick={() => go('support/' + x.id)}>
                    <td>
                      <a href={'#/support/' + x.id}>{x.subject}</a> {unread && <Badge tone="wine">{t('sup.new')}</Badge>}
                    </td>
                    <td>{t(('tc.' + x.category) as Key)}</td>
                    <td>
                      <Badge tone="line">{t(('ts.' + x.status) as Key)}</Badge>
                    </td>
                    <td>{f.date(x.lastMessageAt)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </View>
    </Page>
  );
}

export function TicketThread({ id }: { id: string }) {
  const { t } = useT();
  const f = useFmt();
  const load = useLoad(() => GET<Thread>('support/tickets/' + id), [id]);
  const act = useAction();
  const [body, setBody] = useState('');
  const [files, setFiles] = useState<File[]>([]);
  const [fileErr, setFileErr] = useState('');
  const endRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' });
  }, [load.data?.messages.length]);

  const pick = (list: FileList | null) => {
    setFileErr('');
    const next = [...files];
    for (const file of Array.from(list ?? [])) {
      if (!MIMES.includes(file.type)) setFileErr(t('sup.badType'));
      else if (file.size > MAX_BYTES) setFileErr(t('sup.tooBig'));
      else if (next.length < 3) next.push(file);
      else setFileErr(t('sup.max3'));
    }
    setFiles(next);
  };

  const send = () =>
    act.run(async () => {
      const attachmentIds: string[] = [];
      for (const file of files) attachmentIds.push(await uploadAttachment(file));
      await POST(`support/tickets/${id}/messages`, { ...(body.trim() ? { body: body.trim() } : {}), ...(attachmentIds.length ? { attachmentIds } : {}) });
      setBody('');
      setFiles([]);
      load.reload();
    }, t('sup.sent'));

  return (
    <Page title={t('sup.thread')} actions={<a className="btn ghost" href="#/support">{t('back')}</a>}>
      <View load={load}>
        {(th) => (
          <div className="thread-wrap">
            <header className="panel row">
              <strong>{th.subject}</strong>
              <Badge tone="line">{t(('tc.' + th.category) as Key)}</Badge>
              <span className="push" />
              <label className="inline">
                {t('col.status')}
                <select
                  value={th.status}
                  onChange={(e) => {
                    const status = e.target.value;
                    void act.run(async () => {
                      await PUT(`support/tickets/${id}/status`, { status });
                      load.reload();
                    }, t('saved'));
                  }}
                >
                  {STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {t(('ts.' + s) as Key)}
                    </option>
                  ))}
                </select>
              </label>
              <a href={'#/users/' + th.userId}>{t('sup.member')}</a>
            </header>
            <div className="thread">
              {th.messages.map((m) => (
                <div key={m.id} className={'msg ' + (m.authorType === 'ADMIN' ? 'mine' : m.authorType === 'SYSTEM' ? 'sys' : '')}>
                  <span className="who">{t(('author.' + m.authorType) as Key)}</span>
                  {m.body && <p>{m.body}</p>}
                  {m.attachments.length > 0 && (
                    <div className="atts">
                      {m.attachments.map((a) =>
                        a.mime.startsWith('image/') ? (
                          <a key={a.id} href={a.url} target="_blank" rel="noreferrer noopener">
                            <img src={a.url} alt={a.fileName} referrerPolicy="no-referrer" loading="lazy" />
                          </a>
                        ) : (
                          <a key={a.id} className="file" href={a.url} target="_blank" rel="noreferrer noopener">
                            PDF · {a.fileName}
                          </a>
                        ),
                      )}
                    </div>
                  )}
                  <time>{f.date(m.createdAt)}</time>
                </div>
              ))}
              <div ref={endRef} />
            </div>
            {th.status !== 'CLOSED' ? (
              <div className="composer">
                <textarea rows={3} maxLength={4000} placeholder={t('sup.reply')} value={body} onChange={(e) => setBody(e.target.value)} aria-label={t('sup.reply')} />
                {files.length > 0 && (
                  <ul className="chips">
                    {files.map((file, i) => (
                      <li key={i}>
                        {file.name}
                        <button type="button" aria-label={t('remove')} onClick={() => setFiles((l) => l.filter((_, j) => j !== i))}>
                          ×
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
                {fileErr && <p className="err">{fileErr}</p>}
                <div className="row">
                  <label className="btn ghost">
                    {t('sup.attach')}
                    <input type="file" accept={MIMES.join(',')} multiple hidden onChange={(e) => {
                      pick(e.target.files);
                      e.target.value = '';
                    }} />
                  </label>
                  <span className="muted small">{t('sup.attachHint')}</span>
                  <span className="push" />
                  <Btn disabled={act.busy || (!body.trim() && files.length === 0)} onClick={send}>
                    {t('send')}
                  </Btn>
                </div>
              </div>
            ) : (
              <p className="muted">{t('sup.closed')}</p>
            )}
          </div>
        )}
      </View>
    </Page>
  );
}

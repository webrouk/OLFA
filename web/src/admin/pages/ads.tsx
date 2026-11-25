import React, { useEffect, useState } from 'react';
import { GET, PUT } from '../api';
import type { Key } from '../i18n';
import { Badge, Btn, Field, Page, useAction, useLoad, useT, View } from '../ui';

type Ads = {
  enabled: boolean;
  freePlanShowsAds: boolean;
  firstAfter: number;
  interval: number;
  maxPerSession: number;
  preloadAhead: number;
  personalized: boolean;
  maxAdContentRating: 'G' | 'PG' | 'T' | 'MA';
  units: { android: string; ios: string };
};
type Res = Ads & { effective: { enabled: boolean; reason?: string } };

const UNIT = /^ca-app-pub-\d{16}\/\d{10}$/;
const LIMITS = { firstAfter: [1, 50], interval: [3, 50], maxPerSession: [0, 50], preloadAhead: [1, 3] } as const;

export function AdsPage() {
  const { t } = useT();
  const load = useLoad(() => GET<Res>('ads'));
  const act = useAction();
  const [f, setF] = useState<Ads | null>(null);
  useEffect(() => {
    if (load.data) {
      const { effective: _e, ...rest } = load.data;
      setF(rest);
    }
  }, [load.data]);

  const badUnit = (s: string) => s.trim() !== '' && !UNIT.test(s.trim());
  const badNum = (k: keyof typeof LIMITS) => !f || !Number.isInteger(f[k]) || f[k] < LIMITS[k][0] || f[k] > LIMITS[k][1];
  const invalid = !f || badUnit(f.units.android) || badUnit(f.units.ios) || (Object.keys(LIMITS) as (keyof typeof LIMITS)[]).some(badNum) || (f.enabled && !f.units.android.trim() && !f.units.ios.trim());

  const num = (k: keyof typeof LIMITS, label: Key, hint: Key) =>
    f && (
      <Field label={t(label)} hint={t(hint, { a: LIMITS[k][0], b: LIMITS[k][1] })}>
        <input type="number" min={LIMITS[k][0]} max={LIMITS[k][1]} value={f[k]} onChange={(e) => setF({ ...f, [k]: Math.trunc(Number(e.target.value)) })} aria-invalid={badNum(k)} />
      </Field>
    );

  return (
    <Page title={t('nav.ads')}>
      <p className="muted">{t('ads.intro')}</p>
      <View load={load}>
        {(d) =>
          f && (
            <div className="grid-2">
              <div className="panel">
                <h2>{t('ads.status')}</h2>
                <p>
                  {d.effective.enabled ? <Badge tone="wine">{t('ads.liveOn')}</Badge> : <Badge tone="mist">{t('ads.liveOff')}</Badge>}{' '}
                  {!d.effective.enabled && d.effective.reason && <span className="muted">{t(('ads.why.' + d.effective.reason) as Key)}</span>}
                </p>
                <p className="muted small">{t('ads.paidNever')}</p>
                <label className="inline">
                  <input type="checkbox" checked={f.enabled} onChange={(e) => setF({ ...f, enabled: e.target.checked })} />
                  {t('ads.enabled')}
                </label>
                <p />
                <label className="inline">
                  <input type="checkbox" checked={f.freePlanShowsAds} onChange={(e) => setF({ ...f, freePlanShowsAds: e.target.checked })} />
                  {t('ads.freePlan')}
                </label>
                <h3>{t('ads.frequency')}</h3>
                <div className="row wrap">
                  {num('firstAfter', 'ads.firstAfter', 'ads.range')}
                  {num('interval', 'ads.interval', 'ads.range')}
                </div>
                <div className="row wrap">
                  {num('maxPerSession', 'ads.maxPerSession', 'ads.range')}
                  {num('preloadAhead', 'ads.preloadAhead', 'ads.preloadHint')}
                </div>
                <p className="muted small">{t('ads.example', { a: f.firstAfter, b: f.interval, c: f.maxPerSession })}</p>
              </div>
              <div className="panel">
                <h2>{t('ads.units')}</h2>
                <p className="muted small">{t('ads.unitsHint')}</p>
                <Field label="Android" hint={badUnit(f.units.android) ? t('ads.unitBad') : undefined}>
                  <input dir="ltr" placeholder="ca-app-pub-0000000000000000/0000000000" value={f.units.android} maxLength={60} onChange={(e) => setF({ ...f, units: { ...f.units, android: e.target.value } })} aria-invalid={badUnit(f.units.android)} />
                </Field>
                <Field label="iOS" hint={badUnit(f.units.ios) ? t('ads.unitBad') : undefined}>
                  <input dir="ltr" placeholder="ca-app-pub-0000000000000000/0000000000" value={f.units.ios} maxLength={60} onChange={(e) => setF({ ...f, units: { ...f.units, ios: e.target.value } })} aria-invalid={badUnit(f.units.ios)} />
                </Field>
                <h3>{t('ads.privacy')}</h3>
                <label className="inline">
                  <input type="checkbox" checked={f.personalized} onChange={(e) => setF({ ...f, personalized: e.target.checked })} />
                  {t('ads.personalized')}
                </label>
                <p className="muted small">{t('ads.personalizedHint')}</p>
                <Field label={t('ads.rating')}>
                  <select value={f.maxAdContentRating} onChange={(e) => setF({ ...f, maxAdContentRating: e.target.value as Ads['maxAdContentRating'] })}>
                    {(['G', 'PG', 'T', 'MA'] as const).map((r) => (
                      <option key={r} value={r}>
                        {t(('ads.r.' + r) as Key)}
                      </option>
                    ))}
                  </select>
                </Field>
                {f.enabled && !f.units.android.trim() && !f.units.ios.trim() && <p className="err">{t('ads.needUnit')}</p>}
                <div className="row end">
                  <Btn
                    disabled={invalid || act.busy}
                    onClick={async () => {
                      const ok = await act.run(() => PUT('ads', { ...f, units: { android: f.units.android.trim(), ios: f.units.ios.trim() } }), t('saved'));
                      if (ok) load.reload();
                    }}
                  >
                    {t('save')}
                  </Btn>
                </div>
              </div>
            </div>
          )
        }
      </View>
    </Page>
  );
}

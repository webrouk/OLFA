import React, { useEffect, useState } from 'react';
import { GET, PUT } from '../api';
import type { Key } from '../i18n';
import { Badge, Btn, Field, Page, useAction, useLoad, useT, View } from '../ui';

// Plans and what each unlocks. Member plans and counselor plans are separate:
// a member never holds a counselor plan and the other way round (server + DB).
type Plan = { code: string; nameAr: string; nameEn: string; audience: 'MEMBER' | 'PROFESSIONAL'; isActive: boolean; entitlements: { featureKey: string; value: number | boolean }[] };
type Values = Record<string, number | boolean>;

const MEMBER_KEYS: [string, 'number' | 'boolean'][] = [
  ['daily_likes', 'number'],
  ['daily_messages', 'number'],
  ['daily_undos', 'number'],
  ['advanced_filters', 'boolean'],
  ['see_who_liked_you', 'boolean'],
  ['priority_visibility', 'boolean'],
];
const PRO_KEYS: [string, 'number' | 'boolean'][] = [
  ['directory_boost', 'number'],
  ['featured_badge', 'boolean'],
  ['profile_insights', 'boolean'],
];

function PlanPanel({ plan, keys, pro, onSaved }: { plan: Plan; keys: [string, 'number' | 'boolean'][]; pro: boolean; onSaved: () => void }) {
  const { t, lang } = useT();
  const act = useAction();
  const initial = (): Values => Object.fromEntries(keys.map(([k, ty]) => [k, plan.entitlements.find((e) => e.featureKey === k)?.value ?? (ty === 'number' ? 0 : false)]));
  const [v, setV] = useState<Values>(initial);
  useEffect(() => setV(initial()), [plan]); // eslint-disable-line react-hooks/exhaustive-deps
  const free = plan.code === 'FREE';
  const locked = pro && free; // counselors on Free: standard placement, no badge, no insights
  const badNum = (k: string) => {
    const n = v[k] as number;
    if (k === 'directory_boost') return !Number.isInteger(n) || n < 0 || n > 2;
    return !Number.isInteger(n) || n < -1 || n > 10000;
  };
  const invalid = keys.some(([k, ty]) => ty === 'number' && badNum(k));
  return (
    <div className="panel">
      <h2>
        {lang === 'ar' ? plan.nameAr : plan.nameEn} {plan.isActive ? null : <Badge tone="mist">{t('plans.inactive')}</Badge>}
      </h2>
      <p className="muted small" dir="ltr">
        {plan.code}
      </p>
      {locked && <p className="muted small">{t('plans.proFree')}</p>}
      {keys.map(([k, ty]) =>
        ty === 'boolean' ? (
          <label key={k} className="inline" style={{ display: 'flex', margin: '6px 0' }}>
            <input type="checkbox" disabled={locked} checked={v[k] === true} onChange={(e) => setV({ ...v, [k]: e.target.checked })} />
            {t(('plans.k.' + k) as Key)}
          </label>
        ) : k === 'directory_boost' ? (
          <Field key={k} label={t('plans.k.directory_boost')}>
            <select disabled={locked} value={String(v[k])} onChange={(e) => setV({ ...v, [k]: Number(e.target.value) })}>
              <option value="0">{t('plans.boost0')}</option>
              <option value="1">{t('plans.boost1')}</option>
              <option value="2">{t('plans.boost2')}</option>
            </select>
          </Field>
        ) : (
          <Field key={k} label={t(('plans.k.' + k) as Key)} hint={badNum(k) ? t('plans.numBad') : t('plans.numHint')}>
            <input type="number" min={-1} max={10000} value={v[k] as number} onChange={(e) => setV({ ...v, [k]: Math.trunc(Number(e.target.value)) })} aria-invalid={badNum(k)} />
          </Field>
        ),
      )}
      {!locked && (
        <div className="row end">
          <Btn
            disabled={invalid || act.busy}
            onClick={async () => {
              if (await act.run(() => PUT(`plans/${plan.code}/entitlements`, { values: v }), t('saved'))) onSaved();
            }}
          >
            {t('save')}
          </Btn>
        </div>
      )}
    </div>
  );
}

export function PlansPage() {
  const { t } = useT();
  const load = useLoad(() => GET<Plan[]>('plans'));
  return (
    <Page title={t('nav.plans')}>
      <p className="muted">{t('plans.intro')}</p>
      <View load={load}>
        {(plans) => (
          <>
            <h2>{t('plans.members')}</h2>
            <div className="grid-3">
              {plans
                .filter((p) => p.audience === 'MEMBER')
                .map((p) => (
                  <PlanPanel key={p.code} plan={p} keys={MEMBER_KEYS} pro={false} onSaved={load.reload} />
                ))}
            </div>
            <h2>{t('plans.counselors')}</h2>
            <p className="muted small">{t('plans.counselorsIntro')}</p>
            <div className="grid-3">
              {plans
                .filter((p) => p.code === 'FREE' || p.audience === 'PROFESSIONAL')
                .map((p) => (
                  <PlanPanel key={'pro-' + p.code} plan={p} keys={PRO_KEYS} pro onSaved={load.reload} />
                ))}
            </div>
          </>
        )}
      </View>
    </Page>
  );
}

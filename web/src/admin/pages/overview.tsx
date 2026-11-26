import React from 'react';
import { GET } from '../api';
import { Page, Stat, useFmt, useLoad, useT, View } from '../ui';

type Stats = {
  users: number;
  activeLast7Days: number;
  newUsers7d: number;
  banned: number;
  suspended: number;
  queues: { profiles: number; selfies: number; reports: number; tickets: number; disputes: number; withdrawals: number; counselors: number };
};

export function Overview() {
  const { t } = useT();
  const f = useFmt();
  const load = useLoad(() => GET<Stats>('stats'));
  return (
    <Page title={t('nav.overview')}>
      <View load={load}>
        {(s) => (
          <>
            <h2 className="sub">{t('ov.members')}</h2>
            <div className="stats">
              <Stat label={t('ov.users')} value={f.num(s.users)} href="users" />
              <Stat label={t('ov.active7')} value={f.num(s.activeLast7Days)} />
              <Stat label={t('ov.new7')} value={f.num(s.newUsers7d)} />
              <Stat label={t('ov.suspended')} value={f.num(s.suspended)} href="users?status=SUSPENDED" />
              <Stat label={t('ov.banned')} value={f.num(s.banned)} />
            </div>
            <h2 className="sub">{t('ov.queues')}</h2>
            <div className="stats">
              <Stat label={t('ov.qProfiles')} value={f.num(s.queues.profiles)} href="verification" />
              <Stat label={t('ov.qSelfies')} value={f.num(s.queues.selfies)} href="verification" />
              <Stat label={t('ov.qReports')} value={f.num(s.queues.reports)} href="reports" />
              <Stat label={t('ov.qTickets')} value={f.num(s.queues.tickets)} href="support" />
              <Stat label={t('ov.qDisputes')} value={f.num(s.queues.disputes)} href="disputes" />
              <Stat label={t('ov.qCounselors')} value={f.num(s.queues.counselors)} href="counselors" />
              <Stat label={t('ov.qWithdrawals')} value={f.num(s.queues.withdrawals)} href="withdrawals" />
            </div>
          </>
        )}
      </View>
    </Page>
  );
}

import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger, OnApplicationBootstrap } from '@nestjs/common';
import { Queue } from 'bullmq';
import { PrismaService } from '../../common/infra';
import { NotificationsService } from '../notifications/notifications.module';
import { StorageService } from '../media/storage.service';

export const RETENTION_QUEUE = 'retention';

type RetentionRow = { action: 'warned' | 'expired' | 'deleted_unmatched' | 'deleted_consultation' | 'deleted_empty'; conversation_id: string; user_id: string | null };

/**
 * Hourly sweep (idempotent):
 *  · inbox chats with no message for 15 days leave the list (warning at day 10)
 *  · archived chats are removed after 30 days (warning 7 days before)
 *  · unmatched chats are deleted 30 days after the unmatch without a re-match
 *  · consultation chats are deleted for both 30 days after the consultation
 *    ended or after the last message, whichever is later (warning 3 days before)
 *  · unpaid consultation bookings expire after their payment window
 * All windows come from app_settings; the rules live in olfa_run_retention().
 */
@Processor(RETENTION_QUEUE)
export class RetentionProcessor extends WorkerHost implements OnApplicationBootstrap {
  private readonly log = new Logger('Retention');
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly storage: StorageService,
    @InjectQueue(RETENTION_QUEUE) private readonly queue: Queue,
  ) {
    super();
  }

  async onApplicationBootstrap() {
    await this.queue.upsertJobScheduler('sweep', { pattern: '7 * * * *' }, { name: 'sweep' });
  }

  async process() {
    const rows = await this.prisma.$queryRaw<RetentionRow[]>`SELECT * FROM olfa_run_retention(now())`;
    for (const r of rows) {
      if (r.action === 'warned' && r.user_id) {
        // olfa_run_retention already stored the in-app notification; push it.
        await this.notifications.push(r.user_id, 'push.conversation_expiring', { conversationId: r.conversation_id }).catch((e: unknown) => this.log.warn(`push failed: ${String(e)}`));
      }
    }
    // Incognito switches off when the plan no longer includes it.
    const [{ reset }] = await this.prisma.$queryRaw<{ reset: number }[]>`SELECT olfa_reset_lapsed_privacy() AS reset`;
    // Counselor profile views feed 30-day insights; kept 90 days, then gone.
    await this.prisma.counselorProfileView.deleteMany({ where: { day: { lt: new Date(Date.now() - 90 * 86_400_000) } } });
    // Uploads never attached to a message within a day are dropped; then their objects.
    await this.prisma.messageAttachment.deleteMany({ where: { messageId: null, createdAt: { lt: new Date(Date.now() - 86_400_000) } } });
    await this.prisma.ticketAttachment.deleteMany({ where: { messageId: null, createdAt: { lt: new Date(Date.now() - 86_400_000) } } });
    let removed = 0;
    for (;;) {
      const batch = await this.prisma.storageGarbage.findMany({ take: 500, orderBy: { createdAt: 'asc' } });
      if (batch.length === 0) break;
      await this.storage.deletePrivate(batch.map((b) => b.storageKey));
      await this.prisma.storageGarbage.deleteMany({ where: { storageKey: { in: batch.map((b) => b.storageKey) } } });
      removed += batch.length;
    }
    // Reviewed selfies are deleted after verification.selfieRetentionDays; abandoned captures after a day.
    const [{ selfies }] = await this.prisma.$queryRaw<{ selfies: number }[]>`SELECT olfa_purge_selfies() AS selfies`;
    // Temporary suspensions whose date passed → active again.
    const [{ lifted }] = await this.prisma.$queryRaw<{ lifted: number }[]>`SELECT olfa_lift_expired_suspensions() AS lifted`;
    // Escrow: optional auto-release (escrow.autoReleaseDays, 0 = never) …
    const [{ autoReleased }] = await this.prisma.$queryRaw<{ autoReleased: number }[]>`SELECT olfa_auto_release_escrow() AS "autoReleased"`;
    // … and reminders to confirm + rate, 1 and 3 days after completion (the fee stays held until then).
    const remind = await this.prisma.consultation.findMany({
      where: {
        status: 'COMPLETED', escrowStatus: 'HELD', review: null,
        OR: [1, 3].map((d) => ({ completedAt: { gt: new Date(Date.now() - (d * 24 + 1) * 3_600_000), lte: new Date(Date.now() - d * 24 * 3_600_000) } })),
      },
      select: { id: true, clientId: true },
    });
    for (const r of remind) await this.notifications.push(r.clientId, 'push.review_reminder', { consultationId: r.id }).catch((e: unknown) => this.log.warn(`push failed: ${String(e)}`));
    const expired = await this.prisma.consultation.updateMany({ where: { status: 'AWAITING_PAYMENT', expiresAt: { lt: new Date() } }, data: { status: 'EXPIRED' } });
    // Integrity cases whose response window passed go to review.
    const toReview = await this.prisma.counselorIntegrityCase.updateMany({ where: { status: 'AWAITING_RESPONSE', responseDueAt: { lt: new Date() } }, data: { status: 'UNDER_REVIEW' } });
    // Earnings that left the hold period during the last hour → tell the counselor.
    const hourAgo = new Date(Date.now() - 3_600_000);
    // (entries available immediately were already announced as "fee released")
    const released = (await this.prisma.walletEntry.findMany({ where: { kind: 'EARNING', availableAt: { gt: hourAgo, lte: new Date() } }, select: { counselorId: true, createdAt: true, availableAt: true } }))
      .filter((e) => e.availableAt.getTime() - e.createdAt.getTime() > 60_000)
      .filter((e, i, all) => all.findIndex((x) => x.counselorId === e.counselorId) === i);
    for (const r of released) {
      await this.notifications.notify(r.counselorId, 'WITHDRAWAL_UPDATE', 'push.earning_available', {}).catch((e: unknown) => this.log.warn(`notify failed: ${String(e)}`));
    }
    const counts = rows.reduce<Record<string, number>>((a, r) => ((a[r.action] = (a[r.action] ?? 0) + 1), a), {});
    this.log.log(`sweep: ${JSON.stringify(counts)} bookingsExpired=${expired.count} incognitoReset=${reset} mediaRemoved=${removed} casesToReview=${toReview.count} earningsReleased=${released.length} suspensionsLifted=${lifted} escrowAutoReleased=${autoReleased} reviewReminders=${remind.length} selfiesPurged=${selfies}`);
    return { ...counts, bookingsExpired: expired.count, incognitoReset: reset };
  }
}

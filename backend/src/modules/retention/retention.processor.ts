import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger, OnApplicationBootstrap } from '@nestjs/common';
import { Queue } from 'bullmq';
import { PrismaService } from '../../common/infra';
import { NotificationsService } from '../notifications/notifications.module';

export const RETENTION_QUEUE = 'retention';

type RetentionRow = { action: 'warned' | 'expired' | 'deleted_unmatched' | 'deleted_empty'; conversation_id: string; user_id: string | null };

/**
 * Hourly sweep (idempotent):
 *  · inbox chats with no message for 15 days leave the list (warning at day 10)
 *  · archived chats are removed after 30 days (warning 7 days before)
 *  · unmatched chats are deleted 30 days after the unmatch without a re-match
 *  · unpaid consultation bookings expire after their payment window
 * All windows come from app_settings; the rules live in olfa_run_retention().
 */
@Processor(RETENTION_QUEUE)
export class RetentionProcessor extends WorkerHost implements OnApplicationBootstrap {
  private readonly log = new Logger('Retention');
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
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
    const expired = await this.prisma.consultation.updateMany({ where: { status: 'AWAITING_PAYMENT', expiresAt: { lt: new Date() } }, data: { status: 'EXPIRED' } });
    const counts = rows.reduce<Record<string, number>>((a, r) => ((a[r.action] = (a[r.action] ?? 0) + 1), a), {});
    this.log.log(`sweep: ${JSON.stringify(counts)} bookingsExpired=${expired.count}`);
    return { ...counts, bookingsExpired: expired.count };
  }
}

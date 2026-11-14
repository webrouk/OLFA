import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Inject, Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { PrismaService } from '../../common/infra';
import { hamming, processImage, sanitizeChatImage, sniffImage, VariantName } from './image-pipeline';
import { MEDIA_QUEUE } from './media.module';
import { MODERATION_PROVIDER, ModerationProvider } from './moderation.provider';
import { StorageService } from './storage.service';

/**
 * Runs in the worker process: verify file type by magic bytes, strip
 * metadata, build variants, hash, scan, then queue for human review.
 * Nothing is public until an admin approves (VerificationService.approve).
 */
@Processor(MEDIA_QUEUE)
export class MediaProcessor extends WorkerHost {
  private readonly log = new Logger('MediaProcessor');
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    @Inject(MODERATION_PROVIDER) private readonly moderation: ModerationProvider,
  ) {
    super();
  }

  async process(job: Job<{ photoId?: string; attachmentId?: string }>) {
    if (job.name === 'chat-image') return this.chatImage(job.data.attachmentId!);
    const photo = await this.prisma.userPhoto.findUnique({ where: { id: job.data.photoId! } });
    if (!photo || photo.deletedAt || photo.status !== 'PROCESSING') return;

    const original = await this.storage.getPrivate(photo.storageKey);
    const sniffed = sniffImage(original);
    if (!sniffed) return this.reject(photo.id, 'unsupported_file');

    let out;
    try {
      out = await processImage(original);
    } catch (e) {
      this.log.warn(`photo ${photo.id} rejected: ${(e as Error).message}`);
      return this.reject(photo.id, 'unreadable_or_too_small');
    }

    const variants: Record<string, string> = {};
    for (const name of Object.keys(out.variants) as VariantName[]) {
      const key = `variants/${photo.userId}/${photo.id}/${name}.webp`;
      await this.storage.putPrivate(key, out.variants[name], 'image/webp');
      variants[name] = key;
    }

    const scan = await this.moderation.scan(out.variants.card);
    // Same or near-identical image used by ANOTHER account → fake-account signal.
    const others = await this.prisma.userPhoto.findMany({
      where: { userId: { not: photo.userId }, phash: { not: null }, deletedAt: null },
      select: { userId: true, phash: true },
      take: 5000,
      orderBy: { createdAt: 'desc' },
    });
    const duplicates = others.filter((o) => hamming(o.phash!, out.phash) <= 6).map((o) => o.userId);

    await this.prisma.userPhoto.update({
      where: { id: photo.id },
      data: {
        status: 'PENDING_REVIEW',
        mimeType: sniffed,
        width: out.width,
        height: out.height,
        sha256: out.sha256,
        phash: out.phash,
        variants,
        moderation: { ...scan, duplicateOfUsers: [...new Set(duplicates)].slice(0, 10) },
      },
    });
  }

  private async reject(photoId: string, reason: string) {
    await this.prisma.userPhoto.update({ where: { id: photoId }, data: { status: 'REJECTED', rejectReason: reason, reviewedAt: new Date() } });
  }

  /** Chat photo: verify it is really an image, strip metadata, cap at 2048 px. Non-images are removed. */
  private async chatImage(id: string) {
    const a = await this.prisma.messageAttachment.findUnique({ where: { id } });
    if (!a || a.kind !== 'IMAGE') return;
    const buf = await this.storage.getPrivate(a.storageKey);
    if (!sniffImage(buf)) {
      this.log.warn(`chat attachment ${id} is not an image — removed`);
      await this.prisma.messageAttachment.delete({ where: { id } });
      return;
    }
    const out = await sanitizeChatImage(buf);
    await this.storage.putPrivate(a.storageKey, out.data, 'image/jpeg');
    await this.prisma.messageAttachment.update({ where: { id }, data: { mime: 'image/jpeg', bytes: out.data.length, width: out.width, height: out.height } });
  }
}

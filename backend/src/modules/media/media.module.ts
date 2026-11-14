import { InjectQueue, BullModule } from '@nestjs/bullmq';
import { Body, Controller, Delete, HttpCode, Inject, Injectable, Logger, Module, Param, ParseUUIDPipe, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { Queue } from 'bullmq';
import { ArrayMaxSize, ArrayUnique, Equals, IsArray, IsIn, IsInt, IsUUID, Max, Min } from 'class-validator';
import { randomUUID } from 'node:crypto';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode } from '../../common/errors';
import { AllowPending, AuthUser, CurrentUser, RateLimit } from '../../common/http';
import { AuditService, PrismaService } from '../../common/infra';
import { ALLOWED_MIME, MAX_UPLOAD_BYTES } from './image-pipeline';
import { StorageService } from './storage.service';

export const MEDIA_QUEUE = 'media';
const MAX_PHOTOS = 6;

class UploadUrlDto {
  @ApiProperty({ minimum: 0, maximum: 5 }) @IsInt() @Min(0) @Max(5) position: number;
  @ApiProperty({ enum: ALLOWED_MIME }) @IsIn(ALLOWED_MIME as unknown as string[]) mimeType: string;
  @ApiProperty({ maximum: MAX_UPLOAD_BYTES }) @IsInt() @Min(1) @Max(MAX_UPLOAD_BYTES) bytes: number;
  @ApiProperty({ description: 'User confirms the photo is theirs / they hold the rights' }) @Equals(true) rightsConfirmed: true;
}

class ReorderDto {
  @ApiProperty({ type: [String] }) @IsArray() @ArrayUnique() @ArrayMaxSize(MAX_PHOTOS) @IsUUID('4', { each: true }) photoIds: string[];
}

@Injectable()
export class MediaService {
  private readonly log = new Logger('Media');
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly audit: AuditService,
    @InjectQueue(MEDIA_QUEUE) private readonly queue: Queue,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /** Step 1: reserve a slot and return a presigned POST bound to type + size. */
  async createUpload(userId: string, dto: UploadUrlDto) {
    const live = await this.prisma.userPhoto.findMany({ where: { userId, deletedAt: null }, select: { id: true, position: true, status: true } });
    const inSlot = live.find((p) => p.position === dto.position);
    if (!inSlot && live.length >= MAX_PHOTOS) throw new AppError(ErrorCode.VALIDATION, `Maximum ${MAX_PHOTOS} photos`);
    if (inSlot) await this.remove(userId, inSlot.id); // replacing a slot

    const id = randomUUID();
    const key = `originals/${userId}/${id}`;
    await this.prisma.userPhoto.create({
      data: { id, userId, storageKey: key, mimeType: dto.mimeType, bytes: dto.bytes, position: dto.position, rightsConfirmed: true, status: 'UPLOADING' },
    });
    const post = await this.storage.presignUpload(key, dto.mimeType, Math.min(dto.bytes + 1024, MAX_UPLOAD_BYTES));
    return { photoId: id, upload: { url: post.url, fields: post.fields, expiresInSeconds: 300 } };
  }

  /** Step 2: the client confirms the upload; processing runs in the worker. */
  async complete(userId: string, photoId: string) {
    const photo = await this.prisma.userPhoto.findFirst({ where: { id: photoId, userId, deletedAt: null } });
    if (!photo) throw new AppError(ErrorCode.NOT_FOUND);
    if (photo.status !== 'UPLOADING') return { photoId, status: photo.status };
    let size: number | undefined;
    try {
      size = (await this.storage.head(photo.storageKey)).ContentLength;
    } catch {
      throw new AppError(ErrorCode.UPLOAD_INVALID, 'Upload not found');
    }
    if (!size || size > MAX_UPLOAD_BYTES) throw new AppError(ErrorCode.UPLOAD_INVALID, 'Invalid size');
    await this.prisma.userPhoto.update({ where: { id: photoId }, data: { status: 'PROCESSING', bytes: size } });
    await this.queue.add('process', { photoId }, { jobId: `photo:${photoId}`, attempts: 3, backoff: { type: 'exponential', delay: 5000 }, removeOnComplete: 1000 });
    return { photoId, status: 'PROCESSING' };
  }

  async remove(userId: string, photoId: string) {
    const photo = await this.prisma.userPhoto.findFirst({ where: { id: photoId, userId, deletedAt: null } });
    if (!photo) throw new AppError(ErrorCode.NOT_FOUND);
    await this.prisma.userPhoto.update({ where: { id: photoId }, data: { deletedAt: new Date() } });
    const v = (photo.variants ?? {}) as Record<string, string>;
    const published = Object.values(v).filter((k) => k.startsWith('p/'));
    await this.storage.unpublish(published).catch((e) => this.log.error(`unpublish failed ${photoId}: ${e}`));
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'photo.delete', entityType: 'photo', entityId: photoId });
  }

  async reorder(userId: string, ids: string[]) {
    const photos = await this.prisma.userPhoto.findMany({ where: { userId, deletedAt: null }, select: { id: true } });
    if (photos.length !== ids.length || !photos.every((p) => ids.includes(p.id))) throw new AppError(ErrorCode.VALIDATION, 'photoIds must list every photo once');
    // Two-phase update avoids the (user_id, position) unique index colliding mid-way.
    await this.prisma.$transaction([
      ...ids.map((id, i) => this.prisma.userPhoto.update({ where: { id }, data: { position: 10 + i } })),
      ...ids.map((id, i) => this.prisma.userPhoto.update({ where: { id }, data: { position: i } })),
    ]);
  }
}

@ApiTags('media')
@ApiBearerAuth()
@Controller('v1/me/photos')
export class MediaController {
  constructor(private readonly media: MediaService) {}

  @AllowPending() @RateLimit(30, 3600) @Post('upload-url')
  upload(@CurrentUser() u: AuthUser, @Body() dto: UploadUrlDto) {
    return this.media.createUpload(u.id, dto);
  }

  @AllowPending() @Post(':id/complete') @HttpCode(202)
  complete(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.media.complete(u.id, id);
  }

  @AllowPending() @Delete(':id') @HttpCode(204)
  async remove(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.media.remove(u.id, id);
  }

  @AllowPending() @Put('order') @HttpCode(204)
  async reorder(@CurrentUser() u: AuthUser, @Body() dto: ReorderDto) {
    await this.media.reorder(u.id, dto.photoIds);
  }
}

@Module({
  imports: [BullModule.registerQueue({ name: MEDIA_QUEUE })],
  controllers: [MediaController],
  providers: [MediaService, StorageService],
  exports: [StorageService],
})
export class MediaModule {}

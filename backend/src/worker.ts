import { BullModule } from '@nestjs/bullmq';
import { Logger, Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { bullConnection } from './app.module';
import { ENV, Env } from './config/env';
import { InfraModule } from './common/infra';
import { MediaProcessor } from './modules/media/media.processor';
import { MEDIA_QUEUE } from './modules/media/media.module';
import { ManualOnlyModerationProvider, MODERATION_PROVIDER, RekognitionModerationProvider } from './modules/media/moderation.provider';
import { StorageService } from './modules/media/storage.service';

/** Background worker process: image processing / moderation scans. */
@Module({
  imports: [InfraModule, BullModule.forRootAsync(bullConnection), BullModule.registerQueue({ name: MEDIA_QUEUE })],
  providers: [
    StorageService,
    MediaProcessor,
    RekognitionModerationProvider,
    ManualOnlyModerationProvider,
    {
      provide: MODERATION_PROVIDER,
      inject: [ENV, RekognitionModerationProvider, ManualOnlyModerationProvider],
      useFactory: (env: Env, rek: RekognitionModerationProvider, manual: ManualOnlyModerationProvider) => (env.MODERATION_PROVIDER === 'rekognition' ? rek : manual),
    },
  ],
})
class WorkerModule {}

async function bootstrap() {
  const app = await NestFactory.createApplicationContext(WorkerModule);
  app.enableShutdownHooks();
  Logger.log('OLFA worker started', 'Worker');
}
bootstrap();

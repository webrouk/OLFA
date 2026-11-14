import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { createAdapter } from '@socket.io/redis-adapter';
import helmet from 'helmet';
import Redis from 'ioredis';
import type { ServerOptions } from 'socket.io';
import { AppModule } from './app.module';
import { ENV, Env } from './config/env';

/** Socket.IO across instances through Redis pub/sub. */
class RedisIoAdapter extends IoAdapter {
  constructor(app: NestExpressApplication, private readonly url: string) {
    super(app);
  }
  createIOServer(port: number, options?: ServerOptions) {
    const server = super.createIOServer(port, options);
    const pub = new Redis(this.url);
    server.adapter(createAdapter(pub, pub.duplicate()));
    return server;
  }
}

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { bufferLogs: true });
  const env = app.get<Env>(ENV);

  app.set('trust proxy', 1); // behind the load balancer: real client IP for rate limits
  app.use(helmet());
  app.useBodyParser('json', { limit: '100kb' });
  app.enableCors({
    origin: env.CORS_ORIGINS ? env.CORS_ORIGINS.split(',').map((s) => s.trim()) : false, // mobile apps send no Origin
    credentials: false,
  });
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true, transformOptions: { enableImplicitConversion: false } }),
  );
  app.useWebSocketAdapter(new RedisIoAdapter(app, env.REDIS_URL));
  app.enableShutdownHooks();

  if (env.NODE_ENV !== 'production') {
    const doc = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle('OLFA API')
        .setDescription('Serious Dating & Marriage Platform — REST API. Realtime chat: Socket.IO namespace /chat.')
        .setVersion('1.0')
        .addBearerAuth()
        .build(),
    );
    SwaggerModule.setup('docs', app, doc, { jsonDocumentUrl: 'docs/openapi.json' });
  }

  await app.listen(env.PORT, '0.0.0.0');
  Logger.log(`OLFA API listening on :${env.PORT} (${env.NODE_ENV})`, 'Bootstrap');
}
bootstrap();

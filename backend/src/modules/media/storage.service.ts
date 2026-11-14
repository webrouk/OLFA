import { CopyObjectCommand, DeleteObjectsCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { createPresignedPost } from '@aws-sdk/s3-presigned-post';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Inject, Injectable } from '@nestjs/common';
import { ENV, Env } from '../../config/env';

import { MAX_UPLOAD_BYTES } from './image-pipeline';

/**
 * Two buckets: PRIVATE (originals + pending variants, never public) and
 * PUBLIC (approved variants only, served through the CDN).
 */
@Injectable()
export class StorageService {
  readonly s3: S3Client;
  constructor(@Inject(ENV) private readonly env: Env) {
    this.s3 = new S3Client({
      region: env.S3_REGION,
      endpoint: env.S3_ENDPOINT,
      forcePathStyle: !!env.S3_ENDPOINT,
      credentials: { accessKeyId: env.S3_ACCESS_KEY_ID, secretAccessKey: env.S3_SECRET_ACCESS_KEY },
    });
  }

  /** Browser/app uploads straight to private storage; size and type enforced by the signature. */
  presignUpload(key: string, mime: string, maxBytes = MAX_UPLOAD_BYTES) {
    return createPresignedPost(this.s3, {
      Bucket: this.env.S3_PRIVATE_BUCKET,
      Key: key,
      Expires: 300,
      Conditions: [['content-length-range', 1, maxBytes], ['eq', '$Content-Type', mime]],
      Fields: { 'Content-Type': mime },
    });
  }

  head(key: string) {
    return this.s3.send(new HeadObjectCommand({ Bucket: this.env.S3_PRIVATE_BUCKET, Key: key }));
  }

  async getPrivate(key: string): Promise<Buffer> {
    const r = await this.s3.send(new GetObjectCommand({ Bucket: this.env.S3_PRIVATE_BUCKET, Key: key }));
    return Buffer.from(await r.Body!.transformToByteArray());
  }

  putPrivate(key: string, body: Buffer, contentType: string) {
    return this.s3.send(new PutObjectCommand({ Bucket: this.env.S3_PRIVATE_BUCKET, Key: key, Body: body, ContentType: contentType }));
  }

  /** Short-lived link for moderators to see a private object. */
  signedPrivateUrl(key: string, seconds = 300) {
    return getSignedUrl(this.s3, new GetObjectCommand({ Bucket: this.env.S3_PRIVATE_BUCKET, Key: key }), { expiresIn: seconds });
  }

  /** Copies an approved variant to the public (CDN) bucket. */
  publish(privateKey: string, publicKey: string) {
    return this.s3.send(
      new CopyObjectCommand({
        Bucket: this.env.S3_PUBLIC_BUCKET,
        Key: publicKey,
        CopySource: `${this.env.S3_PRIVATE_BUCKET}/${privateKey}`,
        CacheControl: 'public, max-age=31536000, immutable',
        MetadataDirective: 'REPLACE',
        ContentType: 'image/webp',
      }),
    );
  }

  async unpublish(publicKeys: string[]) {
    if (publicKeys.length === 0) return;
    await this.s3.send(new DeleteObjectsCommand({ Bucket: this.env.S3_PUBLIC_BUCKET, Delete: { Objects: publicKeys.map((Key) => ({ Key })) } }));
  }
}

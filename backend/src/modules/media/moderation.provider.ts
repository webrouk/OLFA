import { DetectModerationLabelsCommand, RekognitionClient } from '@aws-sdk/client-rekognition';
import { Inject, Injectable } from '@nestjs/common';
import { ENV, Env } from '../../config/env';

export interface ModerationResult {
  provider: string;
  flagged: boolean; // inappropriate content detected
  labels: { name: string; confidence: number }[];
  /** Human review is always required before a photo is published. */
  requiresHumanReview: true;
}

export interface ModerationProvider {
  scan(image: Buffer): Promise<ModerationResult>;
}
export const MODERATION_PROVIDER = Symbol('MODERATION_PROVIDER');

/** AWS Rekognition DetectModerationLabels. */
@Injectable()
export class RekognitionModerationProvider implements ModerationProvider {
  private readonly client: RekognitionClient;
  constructor(@Inject(ENV) env: Env) {
    this.client = new RekognitionClient({ region: env.S3_REGION, credentials: { accessKeyId: env.S3_ACCESS_KEY_ID, secretAccessKey: env.S3_SECRET_ACCESS_KEY } });
  }

  async scan(image: Buffer): Promise<ModerationResult> {
    const r = await this.client.send(new DetectModerationLabelsCommand({ Image: { Bytes: image }, MinConfidence: 60 }));
    const labels = (r.ModerationLabels ?? []).map((l) => ({ name: l.Name ?? 'unknown', confidence: Math.round(l.Confidence ?? 0) }));
    return { provider: 'rekognition', flagged: labels.some((l) => l.confidence >= 80), labels, requiresHumanReview: true };
  }
}

/**
 * No automated classifier configured: nothing is auto-approved; every photo
 * goes to the human review queue. (Safe default, not a pass-through.)
 */
@Injectable()
export class ManualOnlyModerationProvider implements ModerationProvider {
  async scan(): Promise<ModerationResult> {
    return { provider: 'manual', flagged: false, labels: [], requiresHumanReview: true };
  }
}

import { Inject, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'node:crypto';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode } from '../../common/errors';
import { AuditService, PrismaService, RateLimiter, SettingsService } from '../../common/infra';
import { checkOtp, generateOtp, hashOtp, newRefreshToken, OTP_POLICY, sha256, toE164 } from '../../domain/security';
import { isValidTimeZone } from '../../domain/quota-period';
import { RequestOtpDto, VerifyOtpDto } from './auth.dto';
import { SMS_PROVIDER, SmsProvider } from './sms.provider';
import { BansService } from '../integrity/integrity.module';
import { AppLocaleCode } from '../../domain/locale';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly limiter: RateLimiter,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    @Inject(SMS_PROVIDER) private readonly sms: SmsProvider,
    @Inject(ENV) private readonly env: Env,
    private readonly bans: BansService,
  ) {}

  /** Steps 1–3: validate phone, apply abuse limits, store a hashed OTP, send SMS. */
  async requestOtp(dto: RequestOtpDto, ipHash: string, locale: AppLocaleCode = 'en') {
    const phone = toE164(dto.dialCode, dto.nationalNumber);
    if (!phone) throw new AppError(ErrorCode.VALIDATION, 'Invalid phone number', { field: 'nationalNumber' });
    // A permanently banned number gets no code (and no SMS cost).
    await this.bans.assertNotBanned('PHONE', phone);

    const cooldown = await this.settings.get('otp.resendCooldownSeconds', OTP_POLICY.resendCooldownSeconds);
    const ttl = await this.settings.get('otp.ttlSeconds', OTP_POLICY.ttlSeconds);
    const maxAttempts = await this.settings.get('otp.maxVerifyAttempts', OTP_POLICY.maxVerifyAttempts);

    // Abuse prevention: per phone, per IP and per device windows (Redis, atomic).
    await this.limiter.hit(`otp:phone:${phone}`, OTP_POLICY.perPhoneMaxRequests, OTP_POLICY.perPhoneWindowSeconds);
    await this.limiter.hit(`otp:ip:${ipHash}`, OTP_POLICY.perIpMaxRequests, OTP_POLICY.perIpWindowSeconds);
    await this.limiter.hit(`otp:device:${dto.deviceId}`, OTP_POLICY.perIpMaxRequests, OTP_POLICY.perIpWindowSeconds);

    const last = await this.prisma.otpChallenge.findFirst({ where: { phoneE164: phone }, orderBy: { createdAt: 'desc' } });
    if (last) {
      const wait = Math.ceil((last.createdAt.getTime() + cooldown * 1000 - Date.now()) / 1000);
      if (wait > 0) throw new AppError(ErrorCode.OTP_COOLDOWN, 'Please wait before requesting a new code', { retryAfter: wait });
    }

    const code = generateOtp();
    const challenge = await this.prisma.otpChallenge.create({
      data: {
        phoneE164: phone,
        codeHash: hashOtp(this.env.OTP_HMAC_SECRET, phone, code),
        maxAttempts,
        ipHash,
        deviceId: dto.deviceId,
        expiresAt: new Date(Date.now() + ttl * 1000),
      },
    });
    const body = {
      ar: `رمز التحقق في أُلْفَة: ${code}. لا تشاركه مع أحد.`,
      en: `Your OLFA code is ${code}. Do not share it.`,
      fr: `Votre code OLFA est ${code}. Ne le partagez avec personne.`,
    }[locale];
    await this.sms.send(phone, body);
    return { challengeId: challenge.id, expiresInSeconds: ttl, resendAfterSeconds: cooldown };
  }

  /** Steps 4–6: verify, create the account if new, open a device session. */
  async verifyOtp(dto: VerifyOtpDto, meta: { ipHash: string; userAgent?: string; locale?: AppLocaleCode }) {
    const c = await this.prisma.otpChallenge.findUnique({ where: { id: dto.challengeId } });
    if (!c || c.deviceId !== dto.deviceId) throw new AppError(ErrorCode.OTP_INVALID);

    const result = checkOtp(
      { codeHash: c.codeHash, attempts: c.attempts, maxAttempts: c.maxAttempts, expiresAt: c.expiresAt, consumedAt: c.consumedAt },
      hashOtp(this.env.OTP_HMAC_SECRET, c.phoneE164, dto.code),
      new Date(),
    );
    if (result !== 'ok') {
      if (result === 'mismatch') {
        // Atomic increment; the challenge locks itself once attempts reach the max.
        const updated = await this.prisma.otpChallenge.update({ where: { id: c.id }, data: { attempts: { increment: 1 } } });
        throw new AppError(updated.attempts >= updated.maxAttempts ? ErrorCode.OTP_LOCKED : ErrorCode.OTP_INVALID, undefined, {
          attemptsLeft: Math.max(0, updated.maxAttempts - updated.attempts),
        });
      }
      throw new AppError(result === 'expired' ? ErrorCode.OTP_EXPIRED : result === 'locked' ? ErrorCode.OTP_LOCKED : ErrorCode.OTP_INVALID);
    }

    // Consume exactly once even under concurrent verifies.
    const consumed = await this.prisma.otpChallenge.updateMany({ where: { id: c.id, consumedAt: null }, data: { consumedAt: new Date() } });
    if (consumed.count !== 1) throw new AppError(ErrorCode.OTP_INVALID);

    const now = new Date();
    await this.bans.assertNotBanned('PHONE', c.phoneE164);
    // A device that belonged to a banned account cannot open a NEW account.
    const known = await this.prisma.user.findFirst({ where: { phoneE164: c.phoneE164, deletedAt: null }, select: { id: true } });
    if (!known) await this.bans.assertNotBanned('DEVICE', dto.deviceId);
    const country = await this.countryForDial(c.phoneE164);
    const { user, isNew } = await this.prisma.$transaction(async (tx) => {
      const existing = await tx.user.findFirst({ where: { phoneE164: c.phoneE164, deletedAt: null } });
      if (existing) {
        // Signing in during the 30-day deletion grace period restores the account.
        const restored = existing.deletionRequestedAt
          ? await tx.user.update({ where: { id: existing.id }, data: { deletionRequestedAt: null } })
          : existing;
        return { user: restored, isNew: false };
      }
      const created = await tx.user.create({
        data: {
          phoneE164: c.phoneE164,
          phoneCountry: country,
          phoneVerifiedAt: now,
          // the app's language (it follows the phone: ar / en / fr, otherwise en)
          locale: dto.locale ?? meta.locale ?? 'en',
          timezone: dto.timezone && isValidTimeZone(dto.timezone) ? dto.timezone : 'UTC',
        },
      });
      return { user: created, isNew: true };
    });

    if (user.status === 'BANNED') throw new AppError(ErrorCode.ACCOUNT_BANNED);
    if (user.status === 'SUSPENDED') throw new AppError(ErrorCode.ACCOUNT_NOT_ACTIVE);
    const tokens = await this.openSession(user.id, dto, meta);
    if (isNew) await this.audit.record({ actorType: 'USER', actorId: user.id, action: 'user.register', entityType: 'user', entityId: user.id, ipHash: meta.ipHash });
    const profile = await this.prisma.userProfile.findUnique({ where: { userId: user.id }, select: { userId: true } });
    const counselor = profile ? null : await this.prisma.counselorProfile.findUnique({ where: { userId: user.id }, select: { userId: true } });
    return { ...tokens, isNewUser: isNew, accountStatus: user.status, accountType: user.accountType, profileComplete: !!profile || !!counselor };
  }

  /** Refresh-token rotation with reuse detection (a replayed token revokes the family). */
  async refresh(refreshToken: string) {
    const hash = sha256(refreshToken);
    const s = await this.prisma.userSession.findUnique({ where: { refreshTokenHash: hash } });
    if (!s) throw new AppError(ErrorCode.UNAUTHORIZED);
    if (s.revokedAt) {
      await this.prisma.userSession.updateMany({
        where: { familyId: s.familyId, revokedAt: null },
        data: { revokedAt: new Date(), revokedReason: 'token_reuse' },
      });
      await this.audit.record({ actorType: 'SYSTEM', action: 'session.reuse_detected', entityType: 'user', entityId: s.userId });
      throw new AppError(ErrorCode.UNAUTHORIZED);
    }
    if (s.expiresAt < new Date()) throw new AppError(ErrorCode.UNAUTHORIZED);

    const next = newRefreshToken();
    const [, created] = await this.prisma.$transaction([
      this.prisma.userSession.update({ where: { id: s.id }, data: { revokedAt: new Date(), revokedReason: 'rotated' } }),
      this.prisma.userSession.create({
        data: {
          userId: s.userId,
          familyId: s.familyId,
          refreshTokenHash: next.hash,
          deviceId: s.deviceId,
          platform: s.platform,
          appVersion: s.appVersion,
          fcmToken: s.fcmToken,
          ipHash: s.ipHash,
          userAgent: s.userAgent,
          expiresAt: new Date(Date.now() + this.env.REFRESH_TTL_DAYS * 86_400_000),
        },
      }),
    ]);
    return { accessToken: await this.signAccess(s.userId, created.id), accessTokenExpiresIn: this.env.JWT_ACCESS_TTL_SECONDS, refreshToken: next.token };
  }

  async logout(sessionId: string) {
    await this.prisma.userSession.update({ where: { id: sessionId }, data: { revokedAt: new Date(), revokedReason: 'logout' } });
  }

  async listSessions(userId: string, currentSessionId: string) {
    const rows = await this.prisma.userSession.findMany({
      where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
      select: { id: true, platform: true, appVersion: true, createdAt: true, lastUsedAt: true },
      orderBy: { lastUsedAt: 'desc' },
    });
    return rows.map((r) => ({ ...r, current: r.id === currentSessionId }));
  }

  async revokeSession(userId: string, sessionId: string) {
    const r = await this.prisma.userSession.updateMany({ where: { id: sessionId, userId, revokedAt: null }, data: { revokedAt: new Date(), revokedReason: 'user_revoked' } });
    if (r.count === 0) throw new AppError(ErrorCode.NOT_FOUND);
  }

  async setPushToken(sessionId: string, fcmToken: string) {
    await this.prisma.userSession.update({ where: { id: sessionId }, data: { fcmToken } });
  }

  private async openSession(userId: string, dto: VerifyOtpDto, meta: { ipHash: string; userAgent?: string }) {
    // One live session per device: signing in again on the same device replaces it.
    await this.prisma.userSession.updateMany({ where: { userId, deviceId: dto.deviceId, revokedAt: null }, data: { revokedAt: new Date(), revokedReason: 'replaced' } });
    const rt = newRefreshToken();
    const session = await this.prisma.userSession.create({
      data: {
        userId,
        familyId: randomUUID(),
        refreshTokenHash: rt.hash,
        deviceId: dto.deviceId,
        platform: dto.platform,
        appVersion: dto.appVersion,
        ipHash: meta.ipHash,
        userAgent: meta.userAgent?.slice(0, 200),
        expiresAt: new Date(Date.now() + this.env.REFRESH_TTL_DAYS * 86_400_000),
      },
    });
    return { accessToken: await this.signAccess(userId, session.id), accessTokenExpiresIn: this.env.JWT_ACCESS_TTL_SECONDS, refreshToken: rt.token };
  }

  private signAccess(userId: string, sessionId: string) {
    return this.jwt.signAsync({ sub: userId, sid: sessionId, typ: 'access' }, { secret: this.env.JWT_ACCESS_SECRET, expiresIn: this.env.JWT_ACCESS_TTL_SECONDS });
  }

  private async countryForDial(e164: string): Promise<string> {
    const map: [string, string][] = [['+971', 'AE'], ['+966', 'SA'], ['+965', 'KW'], ['+974', 'QA'], ['+973', 'BH'], ['+968', 'OM'], ['+962', 'JO'], ['+212', 'MA'], ['+20', 'EG'], ['+44', 'GB'], ['+1', 'US']];
    return map.find(([d]) => e164.startsWith(d))?.[1] ?? 'ZZ';
  }
}

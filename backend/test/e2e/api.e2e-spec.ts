/**
 * End-to-end API tests against real PostgreSQL + Redis (docker compose).
 *   DATABASE_URL=… REDIS_URL=… npm run test:e2e
 * SMS and object storage are replaced with in-memory fakes; everything else
 * (guards, validation, SQL functions, quotas, matching) is the real code.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as argon2 from 'argon2';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../../src/app.module';
import { PrismaService } from '../../src/common/infra';
import { SMS_PROVIDER } from '../../src/modules/auth/sms.provider';
import { StorageService } from '../../src/modules/media/storage.service';

const sent: { to: string; body: string }[] = [];
const fakeSms = { send: async (to: string, body: string) => void sent.push({ to, body }) };
const fakeStorage = { publish: async () => undefined, unpublish: async () => undefined, signedPrivateUrl: async () => 'https://signed', head: async () => ({ ContentLength: 1000 }) };

let app: INestApplication;
let prisma: PrismaService;
const http = () => request(app.getHttpServer());

async function signUp(national: string, gender: 'MALE' | 'FEMALE', birth: string) {
  const deviceId = `device-${randomUUID()}`;
  const r1 = await http().post('/v1/auth/otp/request').send({ dialCode: '+971', nationalNumber: national, country: 'AE', deviceId }).expect(200);
  const code = sent[sent.length - 1].body.match(/\d{6}/)![0];
  const r2 = await http().post('/v1/auth/otp/verify').send({ challengeId: r1.body.challengeId, code, deviceId, platform: 'ios', timezone: 'Asia/Dubai' }).expect(200);
  const token = r2.body.accessToken as string;
  await http().post('/v1/me/profile').auth(token, { type: 'bearer' }).send({
    displayName: gender === 'MALE' ? 'Ahmed' : 'Sara', birthDate: birth, gender, countryCode: 'AE', city: 'Dubai',
    maritalStatus: 'NEVER_MARRIED', education: 'BACHELOR', occupation: 'Engineer', marriageTimeline: 'WITHIN_1_YEAR',
    bio: 'Looking for a serious relationship that leads to marriage.', interests: ['reading', 'travel'], ageConfirmed: true, termsVersion: '2026-11',
  }).expect(201);
  const me = await http().get('/v1/me').auth(token, { type: 'bearer' }).expect(200);
  return { token, id: me.body.id as string, refresh: r2.body.refreshToken as string };
}

/** Simulates processed photos + admin approval (storage faked). */
async function approve(userId: string, adminToken: string) {
  for (const position of [0, 1]) {
    const id = randomUUID();
    await prisma.userPhoto.create({ data: { id, userId, storageKey: `originals/${userId}/${id}`, position, rightsConfirmed: true, status: 'PENDING_REVIEW', variants: { thumb: 'v/t', card: 'v/c', full: 'v/f' } } });
  }
  return adminToken;
}

describe('OLFA API (e2e)', () => {
  let admin: string;
  let moderatorOnly: string;

  beforeAll(async () => {
    const mod = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(SMS_PROVIDER).useValue(fakeSms)
      .overrideProvider(StorageService).useValue(fakeStorage)
      .compile();
    app = mod.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
    await app.init();
    prisma = app.get(PrismaService);

    const mk = async (email: string, role: string) => {
      const a = await prisma.adminUser.create({ data: { email, name: role, passwordHash: await argon2.hash('correct horse battery') } });
      await prisma.adminUserRole.create({ data: { adminId: a.id, roleId: (await prisma.role.findUniqueOrThrow({ where: { key: role } })).id } });
      return (await http().post('/v1/admin/auth/login').send({ email, password: 'correct horse battery' }).expect(200)).body.accessToken as string;
    };
    admin = await mk(`admin-${randomUUID()}@olfa.test`, 'super_admin');
    moderatorOnly = await mk(`mod-${randomUUID()}@olfa.test`, 'moderator');
  });
  afterAll(() => app.close());

  describe('authentication', () => {
    it('rejects invalid phone numbers', () => http().post('/v1/auth/otp/request').send({ dialCode: '+971', nationalNumber: '12', country: 'AE', deviceId: 'device-123456' }).expect(400));

    it('never stores the OTP in clear text', async () => {
      await http().post('/v1/auth/otp/request').send({ dialCode: '+971', nationalNumber: '501110001', country: 'AE', deviceId: 'device-aaaaaaaa' }).expect(200);
      const code = sent[sent.length - 1].body.match(/\d{6}/)![0];
      const row = await prisma.otpChallenge.findFirstOrThrow({ where: { phoneE164: '+971501110001' }, orderBy: { createdAt: 'desc' } });
      expect(row.codeHash).not.toContain(code);
      expect(row.codeHash).toHaveLength(64);
    });

    it('enforces the resend cooldown', () =>
      http().post('/v1/auth/otp/request').send({ dialCode: '+971', nationalNumber: '501110001', country: 'AE', deviceId: 'device-aaaaaaaa' }).expect(429).expect((r) => expect(r.body.error.code).toBe('OTP_COOLDOWN')));

    it('wrong codes count down and then lock the challenge', async () => {
      const deviceId = 'device-locktest';
      const r = await http().post('/v1/auth/otp/request').send({ dialCode: '+971', nationalNumber: '501110002', country: 'AE', deviceId }).expect(200);
      for (let i = 0; i < 4; i++) await http().post('/v1/auth/otp/verify').send({ challengeId: r.body.challengeId, code: '000000', deviceId, platform: 'ios' }).expect(400);
      await http().post('/v1/auth/otp/verify').send({ challengeId: r.body.challengeId, code: '000000', deviceId, platform: 'ios' }).expect(429).expect((x) => expect(x.body.error.code).toBe('OTP_LOCKED'));
      const real = sent[sent.length - 1].body.match(/\d{6}/)![0];
      await http().post('/v1/auth/otp/verify').send({ challengeId: r.body.challengeId, code: real, deviceId, platform: 'ios' }).expect(429);
    });

    it('rotates refresh tokens and revokes the family on reuse', async () => {
      const u = await signUp('501110003', 'MALE', '1994-01-01');
      const r1 = await http().post('/v1/auth/refresh').send({ refreshToken: u.refresh }).expect(200);
      await http().post('/v1/auth/refresh').send({ refreshToken: u.refresh }).expect(401); // replay
      await http().post('/v1/auth/refresh').send({ refreshToken: r1.body.refreshToken }).expect(401); // family revoked
    });
  });

  describe('profiles & verification', () => {
    it('refuses under-18 profiles', async () => {
      const deviceId = 'device-minor01';
      const r = await http().post('/v1/auth/otp/request').send({ dialCode: '+971', nationalNumber: '501110004', country: 'AE', deviceId }).expect(200);
      const code = sent[sent.length - 1].body.match(/\d{6}/)![0];
      const t = (await http().post('/v1/auth/otp/verify').send({ challengeId: r.body.challengeId, code, deviceId, platform: 'android' }).expect(200)).body.accessToken;
      const birth = new Date(Date.now() - 17 * 365.25 * 86_400_000).toISOString().slice(0, 10);
      await http().post('/v1/me/profile').auth(t, { type: 'bearer' }).send({
        displayName: 'Minor', birthDate: birth, gender: 'FEMALE', countryCode: 'AE', city: 'Dubai', maritalStatus: 'NEVER_MARRIED', education: 'HIGH_SCHOOL',
        occupation: 'Student', marriageTimeline: 'NOT_SURE', bio: 'This should never be accepted by the server.', interests: ['reading'], ageConfirmed: true, termsVersion: '2026-11',
      }).expect(422).expect((x) => expect(x.body.error.code).toBe('UNDERAGE'));
    });

    it('rejects contact details in the bio', async () => {
      const u = await signUp('501110005', 'MALE', '1990-01-01');
      await http().patch('/v1/me/profile').auth(u.token, { type: 'bearer' }).send({ bio: 'Call me on +971 50 123 4567 for a chat please' }).expect(400);
    });

    it('pending accounts cannot use discovery', async () => {
      const u = await signUp('501110006', 'MALE', '1990-01-01');
      await http().get('/v1/discovery').auth(u.token, { type: 'bearer' }).expect(403).expect((x) => expect(x.body.error.code).toBe('ACCOUNT_NOT_ACTIVE'));
    });

    it('public profile never exposes phone or birth date', async () => {
      const a = await signUp('501110007', 'MALE', '1992-02-02');
      const b = await signUp('501110008', 'FEMALE', '1996-03-03');
      for (const u of [a, b]) {
        await approve(u.id, admin);
        await http().post('/v1/me/verification/submit').auth(u.token, { type: 'bearer' }).expect(200);
        const q = await http().get('/v1/admin/verification/queue').auth(admin, { type: 'bearer' }).expect(200);
        const req = q.body.find((x: { userId: string }) => x.userId === u.id);
        await http().post(`/v1/admin/verification/${req.id}/approve`).auth(admin, { type: 'bearer' }).send({}).expect(200);
      }
      const p = await http().get(`/v1/profiles/${b.id}`).auth(a.token, { type: 'bearer' }).expect(200);
      expect(p.body.phone).toBeUndefined();
      expect(p.body.birthDate).toBeUndefined();
      expect(p.body.isPhotosReviewed).toBe(true);
      expect(p.body.isIdentityVerified).toBe(false); // photo review ≠ identity verification
    });
  });

  describe('discovery, likes, quotas', () => {
    let man: Awaited<ReturnType<typeof signUp>>;
    const women: Awaited<ReturnType<typeof signUp>>[] = [];

    beforeAll(async () => {
      man = await signUp('502220000', 'MALE', '1993-05-05');
      await approve(man.id, admin);
      await http().post('/v1/me/verification/submit').auth(man.token, { type: 'bearer' });
      for (let i = 1; i <= 12; i++) {
        const w = await signUp(`50222${String(i).padStart(4, '0')}`, 'FEMALE', '1997-06-06');
        await approve(w.id, admin);
        await http().post('/v1/me/verification/submit').auth(w.token, { type: 'bearer' });
        women.push(w);
      }
      const q = await http().get('/v1/admin/verification/queue').auth(admin, { type: 'bearer' });
      for (const r of q.body) await http().post(`/v1/admin/verification/${r.id}/approve`).auth(admin, { type: 'bearer' }).send({});
    });

    it('discovery shows only the opposite gender and never repeats', async () => {
      const r1 = await http().get('/v1/discovery?limit=5').auth(man.token, { type: 'bearer' }).expect(200);
      expect(r1.body.items.every((p: { gender: string }) => p.gender === 'FEMALE')).toBe(true);
      const r2 = await http().get('/v1/discovery?limit=5').auth(man.token, { type: 'bearer' }).expect(200);
      const ids1 = new Set(r1.body.items.map((p: { id: string }) => p.id));
      expect(r2.body.items.some((p: { id: string }) => ids1.has(p.id))).toBe(false);
    });

    it('paid filters are refused for the free plan (402)', () =>
      http().get('/v1/discovery?educations=MASTER').auth(man.token, { type: 'bearer' }).expect(402).expect((r) => expect(r.body.error.code).toBe('ENTITLEMENT_REQUIRED')));

    it('mutual like creates exactly one match; duplicate like is refused', async () => {
      await http().post('/v1/likes').auth(man.token, { type: 'bearer' }).send({ userId: women[0].id }).expect(200).expect((r) => expect(r.body.matched).toBe(false));
      await http().post('/v1/likes').auth(man.token, { type: 'bearer' }).send({ userId: women[0].id }).expect(409);
      const back = await http().post('/v1/likes').auth(women[0].token, { type: 'bearer' }).send({ userId: man.id }).expect(200);
      expect(back.body.matched).toBe(true);
      expect(await prisma.match.count({ where: { OR: [{ userAId: man.id }, { userBId: man.id }] } })).toBe(1);
    });

    it('free plan: the 11th like of the day is refused (429), counters never exceed', async () => {
      const results = await Promise.all(women.slice(1).map((w) => http().post('/v1/likes').auth(man.token, { type: 'bearer' }).send({ userId: w.id })));
      const ok = results.filter((r) => r.status === 200).length;
      expect(ok).toBe(9); // 1 like already used above
      expect(results.filter((r) => r.status === 429).every((r) => r.body.error.code === 'QUOTA_EXCEEDED')).toBe(true);
      const ent = await http().get('/v1/me/entitlements').auth(man.token, { type: 'bearer' }).expect(200);
      expect(ent.body.likes).toEqual({ used: 10, limit: 10, remaining: 0 });
    });

    it('admin quota change applies without an app update', async () => {
      await http().put('/v1/admin/plans/FREE/entitlements').auth(admin, { type: 'bearer' }).send({ values: { daily_likes: 12 } }).expect(200);
      const ent = await http().get('/v1/me/entitlements').auth(man.token, { type: 'bearer' }).expect(200);
      expect(ent.body.likes.limit).toBe(12);
      await http().put('/v1/admin/plans/FREE/entitlements').auth(admin, { type: 'bearer' }).send({ values: { daily_likes: 10 } }).expect(200);
    });

    it('starting a conversation spends the single free credit', async () => {
      const [m] = (await http().get('/v1/matches').auth(man.token, { type: 'bearer' }).expect(200)).body;
      const c1 = await http().post(`/v1/matches/${m.id}/conversation`).auth(man.token, { type: 'bearer' }).expect(200);
      const c2 = await http().post(`/v1/matches/${m.id}/conversation`).auth(women[0].token, { type: 'bearer' }).expect(200);
      expect(c2.body.conversationId).toBe(c1.body.conversationId); // no second conversation, no second charge
      const msg = { clientMessageId: randomUUID(), body: 'Hello' };
      const s1 = await http().post(`/v1/conversations/${c1.body.conversationId}/messages`).auth(man.token, { type: 'bearer' }).send(msg).expect(201);
      const s2 = await http().post(`/v1/conversations/${c1.body.conversationId}/messages`).auth(man.token, { type: 'bearer' }).send(msg).expect(201);
      expect(s2.body.id).toBe(s1.body.id); // idempotent
    });
  });

  describe('authorization', () => {
    it('no token → 401', () => http().get('/v1/me').expect(401));
    it('user token on an admin route → 401', async () => {
      const u = await signUp('503330001', 'MALE', '1990-01-01');
      await http().get('/v1/admin/plans').auth(u.token, { type: 'bearer' }).expect(401);
    });
    it('moderator without plans.manage → 403', () => http().get('/v1/admin/plans').auth(moderatorOnly, { type: 'bearer' }).expect(403));
    it('cannot read someone else’s conversation (no IDOR)', async () => {
      const outsider = await signUp('503330002', 'FEMALE', '1995-01-01');
      const conv = await prisma.conversation.findFirstOrThrow();
      await prisma.user.update({ where: { id: outsider.id }, data: { status: 'ACTIVE' } });
      await http().get(`/v1/conversations/${conv.id}/messages`).auth(outsider.token, { type: 'bearer' }).expect(404);
    });
    it('unknown body fields are rejected (mass assignment)', async () => {
      const u = await signUp('503330003', 'MALE', '1990-01-01');
      await http().patch('/v1/me/profile').auth(u.token, { type: 'bearer' }).send({ status: 'ACTIVE' }).expect(400);
    });
    it('gender cannot be changed by the user', async () => {
      const u = await signUp('503330004', 'MALE', '1990-01-01');
      await http().patch('/v1/me/profile').auth(u.token, { type: 'bearer' }).send({ gender: 'FEMALE' }).expect(403);
    });
  });
});

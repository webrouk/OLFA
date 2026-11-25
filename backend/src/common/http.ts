import {
  applyDecorators,
  ArgumentsHost,
  CanActivate,
  Catch,
  createParamDecorator,
  ExceptionFilter,
  ExecutionContext,
  HttpException,
  Inject,
  Injectable,
  Logger,
  NestMiddleware,
  SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';
import { ENV, Env } from '../config/env';
import { restrictionDetails, restrictionOf } from '../domain/restriction';
import { hashIp } from '../domain/security';
import { AppError, ErrorCode, fromPgError } from './errors';
import { PrismaService, RateLimiter } from './infra';

// ───────────── request context ─────────────

export type AccountTypeName = 'MEMBER' | 'PSYCHOLOGIST' | 'FAMILY_COUNSELOR';
export interface AuthUser {
  id: string;
  sessionId: string;
  status: string;
  /** null until chosen during sign-up */
  accountType: AccountTypeName | null;
}
export interface AuthAdmin {
  id: string;
  permissions: string[];
}
export interface OlfaRequest extends Request {
  requestId: string;
  ipHash: string;
  user?: AuthUser;
  admin?: AuthAdmin;
}

@Injectable()
export class RequestContextMiddleware implements NestMiddleware {
  private readonly log = new Logger('HTTP');
  constructor(@Inject(ENV) private readonly env: Env) {}

  use(req: OlfaRequest, res: Response, next: NextFunction) {
    req.requestId = (req.headers['x-request-id'] as string) || randomUUID();
    req.ipHash = hashIp(this.env.IP_HASH_PEPPER, req.ip ?? '');
    res.setHeader('x-request-id', req.requestId);
    const start = Date.now();
    res.on('finish', () => {
      // No bodies, phone numbers or tokens in logs.
      this.log.log(
        JSON.stringify({
          rid: req.requestId,
          m: req.method,
          p: req.route?.path ?? req.path,
          s: res.statusCode,
          ms: Date.now() - start,
          u: req.user?.id,
        }),
      );
    });
    next();
  }
}

// ───────────── errors ─────────────

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly log = new Logger('Error');

  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();
    const req = host.switchToHttp().getRequest<OlfaRequest>();
    let err: AppError;
    if (exception instanceof AppError) err = exception;
    else if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse() as { message?: string | string[] };
      const code =
        status === 400 ? ErrorCode.VALIDATION
        : status === 401 ? ErrorCode.UNAUTHORIZED
        : status === 403 ? ErrorCode.FORBIDDEN
        : status === 404 ? ErrorCode.NOT_FOUND
        : status === 429 ? ErrorCode.RATE_LIMITED
        : ErrorCode.INTERNAL;
      err = new AppError(code, Array.isArray(body?.message) ? body.message.join('; ') : body?.message ?? exception.message);
    } else {
      err = fromPgError(exception) ?? new AppError(ErrorCode.INTERNAL, 'Internal error');
      if (err.code === ErrorCode.INTERNAL) this.log.error(`[${req?.requestId}] ${(exception as Error)?.stack ?? exception}`);
    }
    res.status(err.status).json({
      error: {
        code: err.code,
        message: err.code === ErrorCode.INTERNAL ? 'Internal error' : err.message,
        ...(err.details ? { details: err.details } : {}),
        requestId: req?.requestId,
      },
    });
  }
}

// ───────────── auth decorators ─────────────

export const IS_PUBLIC = 'olfa:public';
export const Public = () => SetMetadata(IS_PUBLIC, true);

/** Allows routes that a not-yet-approved account may call (profile setup). */
export const ALLOW_PENDING = 'olfa:allowPending';
export const AllowPending = () => SetMetadata(ALLOW_PENDING, true);

/**
 * Restricts a route (or controller) to account types: marriage features are
 * for MEMBER accounts, the counselor workspace for professionals. Accounts
 * that have not chosen a type yet are refused too.
 */
export const ACCOUNT_TYPES = 'olfa:accountTypes';
export const AccountTypes = (...types: AccountTypeName[]) => SetMetadata(ACCOUNT_TYPES, types);
export const MembersOnly = () => AccountTypes('MEMBER');
export const ProfessionalsOnly = () => AccountTypes('PSYCHOLOGIST', 'FAMILY_COUNSELOR');

export const ADMIN_ROUTE = 'olfa:admin';
export const PERMISSIONS = 'olfa:permissions';
export const ADMIN_MFA_SETUP = 'olfa:adminMfaSetup';
/** Admin route reachable before two-factor sign-in is set up (me, TOTP enrolment). */
export const AdminMfaSetup = () => SetMetadata(ADMIN_MFA_SETUP, true);
/** Admin route requiring every listed permission. */
export const RequirePermissions = (...perms: string[]) =>
  applyDecorators(SetMetadata(ADMIN_ROUTE, true), SetMetadata(PERMISSIONS, perms));

export const CurrentUser = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthUser => {
  const u = ctx.switchToHttp().getRequest<OlfaRequest>().user;
  if (!u) throw new AppError(ErrorCode.UNAUTHORIZED);
  return u;
});

export const CurrentAdmin = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthAdmin => {
  const a = ctx.switchToHttp().getRequest<OlfaRequest>().admin;
  if (!a) throw new AppError(ErrorCode.UNAUTHORIZED);
  return a;
});

export const Req = createParamDecorator((_: unknown, ctx: ExecutionContext) => ctx.switchToHttp().getRequest<OlfaRequest>());

export const RATE_LIMIT = 'olfa:rateLimit';
/** Per-user (or per-IP when anonymous) fixed-window limit for a route. */
export const RateLimit = (limit: number, windowSeconds: number) => SetMetadata(RATE_LIMIT, { limit, windowSeconds });

// ───────────── guards ─────────────

/**
 * Global guard: user JWT by default; admin JWT + RBAC on @RequirePermissions
 * routes; nothing on @Public routes. Also enforces account status and per-route
 * rate limits.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
    private readonly limiter: RateLimiter,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    if (ctx.getType() !== 'http') return true; // WebSocket auth is handled in the gateway
    const req = ctx.switchToHttp().getRequest<OlfaRequest>();
    const meta = <T>(k: string) => this.reflector.getAllAndOverride<T>(k, [ctx.getHandler(), ctx.getClass()]);

    if (meta<boolean>(ADMIN_ROUTE)) {
      await this.authenticateAdmin(req, meta<string[]>(PERMISSIONS) ?? [], meta<boolean>(ADMIN_MFA_SETUP) ?? false);
    } else if (!meta<boolean>(IS_PUBLIC)) {
      await this.authenticateUser(req, meta<boolean>(ALLOW_PENDING) ?? false);
      const types = meta<AccountTypeName[]>(ACCOUNT_TYPES);
      if (types && (!req.user!.accountType || !types.includes(req.user!.accountType))) throw new AppError(ErrorCode.WRONG_ACCOUNT_TYPE);
    }

    const rl = meta<{ limit: number; windowSeconds: number }>(RATE_LIMIT);
    if (rl) {
      const who = req.user?.id ?? req.admin?.id ?? req.ipHash;
      await this.limiter.hit(`${ctx.getClass().name}.${ctx.getHandler().name}:${who}`, rl.limit, rl.windowSeconds);
    }
    return true;
  }

  private bearer(req: Request): string {
    const h = req.headers.authorization ?? '';
    if (!h.startsWith('Bearer ')) throw new AppError(ErrorCode.UNAUTHORIZED);
    return h.slice(7);
  }

  private async authenticateUser(req: OlfaRequest, allowPending: boolean) {
    let payload: { sub: string; sid: string; typ: string };
    try {
      payload = await this.jwt.verifyAsync(this.bearer(req), { secret: this.env.JWT_ACCESS_SECRET });
    } catch {
      throw new AppError(ErrorCode.UNAUTHORIZED);
    }
    if (payload.typ !== 'access') throw new AppError(ErrorCode.UNAUTHORIZED);
    // Session must still be live (logout / revoke take effect immediately).
    const session = await this.prisma.userSession.findUnique({
      where: { id: payload.sid },
      select: { revokedAt: true, user: { select: { id: true, status: true, deletedAt: true, frozenAt: true, lastActiveAt: true, accountType: true, suspendedUntil: true, restrictionReason: true, restrictedAt: true } } },
    });
    if (!session || session.revokedAt || session.user.deletedAt || session.user.id !== payload.sub) {
      throw new AppError(ErrorCode.UNAUTHORIZED);
    }
    let status = session.user.status;
    // Admin restrictions → the app shows the closed-account screen from these details.
    const r = restrictionOf(session.user);
    if (r.kind !== 'none') {
      const appealToken = await this.jwt.signAsync({ sub: payload.sub, typ: 'appeal' }, { secret: this.env.JWT_ACCESS_SECRET, expiresIn: 7200 });
      throw new AppError(r.kind === 'banned' ? ErrorCode.ACCOUNT_BANNED : ErrorCode.ACCOUNT_SUSPENDED, undefined, { ...restrictionDetails(r), appealToken });
    }
    if (status === 'SUSPENDED') {
      // the suspension date has passed: active again (the daily job does the same in bulk)
      await this.prisma.user.updateMany({ where: { id: payload.sub, status: 'SUSPENDED' }, data: { status: 'ACTIVE', suspendedUntil: null } });
      status = 'ACTIVE';
    }
    if (status === 'DELETED') throw new AppError(ErrorCode.ACCOUNT_NOT_ACTIVE);
    if (!allowPending && status !== 'ACTIVE' && status !== 'RESTRICTED') throw new AppError(ErrorCode.ACCOUNT_NOT_ACTIVE);
    // A frozen account can only reach account routes (me, reactivate, settings, deletion).
    if (session.user.frozenAt && !allowPending) throw new AppError(ErrorCode.ACCOUNT_FROZEN);
    req.user = { id: payload.sub, sessionId: payload.sid, status, accountType: (session.user.accountType as AccountTypeName | null) ?? null };
    // Presence: at most one write per user per 2 minutes (cheap at scale).
    const seen = session.user.lastActiveAt?.getTime() ?? 0;
    if (!session.user.frozenAt && Date.now() - seen > 120_000) {
      void this.prisma.user.updateMany({ where: { id: payload.sub }, data: { lastActiveAt: new Date() } }).catch(() => undefined);
    }
  }

  private async authenticateAdmin(req: OlfaRequest, required: string[], mfaSetup = false) {
    let payload: { sub: string; typ: string; mfa?: boolean };
    try {
      payload = await this.jwt.verifyAsync(this.bearer(req), { secret: this.env.ADMIN_JWT_SECRET });
    } catch {
      throw new AppError(ErrorCode.UNAUTHORIZED);
    }
    if (payload.typ !== 'admin') throw new AppError(ErrorCode.UNAUTHORIZED);
    // Without a second factor an admin session can only finish setting it up.
    if (this.env.ADMIN_REQUIRE_TOTP && !payload.mfa && !mfaSetup) throw new AppError(ErrorCode.FORBIDDEN, 'Two-factor sign-in is required', { totpSetupRequired: true });
    const admin = await this.prisma.adminUser.findUnique({
      where: { id: payload.sub },
      select: { isActive: true, roles: { select: { role: { select: { permissions: { select: { permission: { select: { key: true } } } } } } } } },
    });
    if (!admin?.isActive) throw new AppError(ErrorCode.UNAUTHORIZED);
    const perms = new Set(admin.roles.flatMap((r) => r.role.permissions.map((p) => p.permission.key)));
    if (!required.every((p) => perms.has(p))) throw new AppError(ErrorCode.FORBIDDEN);
    req.admin = { id: payload.sub, permissions: [...perms] };
  }
}

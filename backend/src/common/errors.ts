import { HttpStatus } from '@nestjs/common';

/** Stable error codes shared with the mobile app (see Flutter ApiErrorMapper). */
export enum ErrorCode {
  VALIDATION = 'VALIDATION',
  UNAUTHORIZED = 'UNAUTHORIZED',
  FORBIDDEN = 'FORBIDDEN',
  NOT_FOUND = 'NOT_FOUND',
  CONFLICT = 'CONFLICT',
  RATE_LIMITED = 'RATE_LIMITED',
  OTP_INVALID = 'OTP_INVALID',
  OTP_EXPIRED = 'OTP_EXPIRED',
  OTP_LOCKED = 'OTP_LOCKED',
  OTP_COOLDOWN = 'OTP_COOLDOWN',
  QUOTA_EXCEEDED = 'QUOTA_EXCEEDED',
  ENTITLEMENT_REQUIRED = 'ENTITLEMENT_REQUIRED',
  DUPLICATE = 'DUPLICATE',
  NOT_ELIGIBLE = 'NOT_ELIGIBLE',
  BLOCKED = 'BLOCKED',
  ACCOUNT_NOT_ACTIVE = 'ACCOUNT_NOT_ACTIVE',
  UNDERAGE = 'UNDERAGE',
  UPLOAD_INVALID = 'UPLOAD_INVALID',
  INTERNAL = 'INTERNAL',
}

const STATUS: Record<ErrorCode, HttpStatus> = {
  VALIDATION: HttpStatus.BAD_REQUEST,
  UNAUTHORIZED: HttpStatus.UNAUTHORIZED,
  FORBIDDEN: HttpStatus.FORBIDDEN,
  NOT_FOUND: HttpStatus.NOT_FOUND,
  CONFLICT: HttpStatus.CONFLICT,
  RATE_LIMITED: HttpStatus.TOO_MANY_REQUESTS,
  OTP_INVALID: HttpStatus.BAD_REQUEST,
  OTP_EXPIRED: HttpStatus.BAD_REQUEST,
  OTP_LOCKED: HttpStatus.TOO_MANY_REQUESTS,
  OTP_COOLDOWN: HttpStatus.TOO_MANY_REQUESTS,
  QUOTA_EXCEEDED: HttpStatus.TOO_MANY_REQUESTS,
  ENTITLEMENT_REQUIRED: HttpStatus.PAYMENT_REQUIRED,
  DUPLICATE: HttpStatus.CONFLICT,
  NOT_ELIGIBLE: HttpStatus.UNPROCESSABLE_ENTITY,
  BLOCKED: HttpStatus.FORBIDDEN,
  ACCOUNT_NOT_ACTIVE: HttpStatus.FORBIDDEN,
  UNDERAGE: HttpStatus.UNPROCESSABLE_ENTITY,
  UPLOAD_INVALID: HttpStatus.BAD_REQUEST,
  INTERNAL: HttpStatus.INTERNAL_SERVER_ERROR,
};

export class AppError extends Error {
  constructor(
    public readonly code: ErrorCode,
    message?: string,
    public readonly details?: Record<string, unknown>,
  ) {
    super(message ?? code);
  }
  get status(): HttpStatus {
    return STATUS[this.code];
  }
}

/** Maps SQLSTATEs raised by olfa_* SQL functions and constraint violations. */
export function fromPgError(e: unknown): AppError | null {
  const err = e as { code?: string; meta?: { code?: string }; message?: string };
  const code = err?.meta?.code ?? err?.code ?? (err?.message?.match(/SQLSTATE[: ]+(\w{5})/)?.[1]);
  switch (code) {
    case 'OLQ01':
      return new AppError(ErrorCode.QUOTA_EXCEEDED);
    case 'OLL01':
      return new AppError(ErrorCode.DUPLICATE);
    case 'OLL02':
      return new AppError(ErrorCode.NOT_ELIGIBLE);
    case 'OLL03':
      return new AppError(ErrorCode.BLOCKED);
    case '23505':
    case 'P2002':
      return new AppError(ErrorCode.CONFLICT);
    case '23503':
    case 'P2003':
      return new AppError(ErrorCode.NOT_FOUND);
    case 'P2025':
      return new AppError(ErrorCode.NOT_FOUND);
    default:
      return null;
  }
}

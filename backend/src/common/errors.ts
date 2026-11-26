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
  ACCOUNT_FROZEN = 'ACCOUNT_FROZEN',
  UNDERAGE = 'UNDERAGE',
  UPLOAD_INVALID = 'UPLOAD_INVALID',
  CONVERSATION_CLOSED = 'CONVERSATION_CLOSED',
  CONVERSATION_LOCKED = 'CONVERSATION_LOCKED',
  REMATCH_USED = 'REMATCH_USED',
  INVALID_STATE = 'INVALID_STATE',
  NOT_PAID = 'NOT_PAID',
  ACCOUNT_TYPE_LOCKED = 'ACCOUNT_TYPE_LOCKED',
  WRONG_ACCOUNT_TYPE = 'WRONG_ACCOUNT_TYPE',
  ACCOUNT_BANNED = 'ACCOUNT_BANNED',
  ACCOUNT_SUSPENDED = 'ACCOUNT_SUSPENDED',
  SLOT_TAKEN = 'SLOT_TAKEN',
  SELFIE_REQUIRED = 'SELFIE_REQUIRED',
  SELFIE_CHECKS_FAILED = 'SELFIE_CHECKS_FAILED',
  SLOT_UNAVAILABLE = 'SLOT_UNAVAILABLE',
  INSUFFICIENT_BALANCE = 'INSUFFICIENT_BALANCE',
  REVIEW_REQUIRED = 'REVIEW_REQUIRED',
  STORE_VERIFICATION_FAILED = 'STORE_VERIFICATION_FAILED',
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
  ACCOUNT_FROZEN: HttpStatus.FORBIDDEN,
  UNDERAGE: HttpStatus.UNPROCESSABLE_ENTITY,
  UPLOAD_INVALID: HttpStatus.BAD_REQUEST,
  CONVERSATION_CLOSED: HttpStatus.FORBIDDEN,
  CONVERSATION_LOCKED: HttpStatus.PAYMENT_REQUIRED,
  REMATCH_USED: HttpStatus.CONFLICT,
  INVALID_STATE: HttpStatus.CONFLICT,
  NOT_PAID: HttpStatus.PAYMENT_REQUIRED,
  ACCOUNT_TYPE_LOCKED: HttpStatus.CONFLICT,
  WRONG_ACCOUNT_TYPE: HttpStatus.FORBIDDEN,
  ACCOUNT_BANNED: HttpStatus.FORBIDDEN,
  ACCOUNT_SUSPENDED: HttpStatus.FORBIDDEN,
  SLOT_TAKEN: HttpStatus.CONFLICT,
  SELFIE_REQUIRED: HttpStatus.UNPROCESSABLE_ENTITY,
  SELFIE_CHECKS_FAILED: HttpStatus.UNPROCESSABLE_ENTITY,
  SLOT_UNAVAILABLE: HttpStatus.UNPROCESSABLE_ENTITY,
  INSUFFICIENT_BALANCE: HttpStatus.UNPROCESSABLE_ENTITY,
  REVIEW_REQUIRED: HttpStatus.CONFLICT,
  STORE_VERIFICATION_FAILED: HttpStatus.UNPROCESSABLE_ENTITY,
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
    case 'OLQ01': {
      // "quota exceeded: <key>" → tell the client which quota ran out
      const quota = err?.message?.match(/quota exceeded: ([\w:-]+)/)?.[1];
      return new AppError(ErrorCode.QUOTA_EXCEEDED, undefined, quota && !quota.startsWith('msg:') ? { quota } : undefined);
    }
    case 'OLL01':
      return new AppError(ErrorCode.DUPLICATE);
    case 'OLL02':
      return new AppError(ErrorCode.NOT_ELIGIBLE);
    case 'OLL03':
      return new AppError(ErrorCode.BLOCKED);
    // conversation lifecycle & consultations (see migrations 20261114140000/150000)
    case 'P0010':
      return new AppError(ErrorCode.CONVERSATION_CLOSED);
    case 'P0011':
      return new AppError(ErrorCode.NOT_FOUND);
    case 'P0001':
    case 'P0012':
    case 'P0013':
    case 'P0014':
    case 'P0015':
      return new AppError(ErrorCode.INVALID_STATE);
    case 'P0002':
      return new AppError(ErrorCode.NOT_PAID);
    case 'P0003':
      return new AppError(ErrorCode.FORBIDDEN);
    // account types, wallet, reviews (migration 20261114180000)
    case 'P0030':
      return new AppError(ErrorCode.ACCOUNT_TYPE_LOCKED);
    case 'P0031':
      return new AppError(ErrorCode.WRONG_ACCOUNT_TYPE);
    case 'P0040':
    case 'P0042':
      return new AppError(ErrorCode.INVALID_STATE);
    case 'P0041':
      return new AppError(ErrorCode.INSUFFICIENT_BALANCE);
    case 'P0050':
      return new AppError(ErrorCode.REVIEW_REQUIRED);
    // discovery ads (migration 20261125160000): show_ads on a paid plan
    case 'P0060':
      return new AppError(ErrorCode.VALIDATION, 'paid plans never show ads');
    // managed accounts & in-chat compatibility (migration 20261126090000)
    case 'P0072':
      return new AppError(ErrorCode.WRONG_ACCOUNT_TYPE, 'only member accounts can be managed');
    case 'P0073':
      return new AppError(ErrorCode.VALIDATION, 'invalid compatibility question');
    case 'P0074':
      return new AppError(ErrorCode.INVALID_STATE, 'answer not accepted');
    case 'P0075':
      return new AppError(ErrorCode.INVALID_STATE, 'both people must finish first');
    // counselor plans (migration 20261127090000)
    case 'P0076':
      return new AppError(ErrorCode.WRONG_ACCOUNT_TYPE, 'this plan is for another account type');
    case 'P0077':
      return new AppError(ErrorCode.VALIDATION, 'invalid counselor plan feature');
    // escrow / scheduling / support (migration 20261124160000)
    case '23P01': // exclusion constraint: the counselor is already booked at that time
      return new AppError(ErrorCode.SLOT_TAKEN);
    case 'P0021':
      return new AppError(ErrorCode.VALIDATION, 'too many attachments');
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

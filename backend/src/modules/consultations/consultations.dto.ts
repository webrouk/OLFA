import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ConsultationService, CounselorKind, Gender } from '@prisma/client';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, ArrayUnique, Equals, IsArray, IsBoolean, IsDateString, IsEnum, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Matches, Max, MaxLength, Min, MinLength, ValidateIf, ValidateNested } from 'class-validator';
import ref from '../../reference/reference.json';
import { SUPPORTED_CURRENCIES } from '../../domain/payments';

/** Languages a consultation can be delivered in (ISO 639-1). */
export const SERVICE_LANGUAGES = ['ar', 'en', 'fr', 'tr', 'ur', 'fa', 'de', 'es', 'id', 'ms'] as const;
const NO_CONTACT = /^(?![\s\S]*(\+?\d[\d\s]{7,}|@|https?:\/\/|www\.))[\s\S]*$/i;

export class CounselorApplyDto {
  @ApiProperty({ enum: CounselorKind }) @IsEnum(CounselorKind) kind: CounselorKind;
  @ApiProperty() @IsString() @Length(2, 60) displayName: string;
  @ApiProperty() @IsString() @Length(5, 120) headline: string;
  @ApiProperty() @IsString() @MinLength(80) @MaxLength(1500) @Matches(NO_CONTACT, { message: 'contact details are not allowed in bio' }) bio: string;
  @ApiProperty() @Type(() => Number) @IsInt() @Min(0) @Max(60) yearsExperience: number;
  @ApiProperty() @IsString() @Length(3, 80) licenseNumber: string;
  @ApiProperty() @IsString() @Length(3, 120) licenseAuthority: string;
  @ApiProperty() @IsIn(ref.countries) licenseCountry: string;
  @ApiProperty({ type: [String], description: 'Keys returned by POST v1/counselors/me/credentials/upload-url' })
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(5) @IsString({ each: true }) @Matches(/^credentials\/[0-9a-f-]{36}\/[0-9a-f-]{36}$/, { each: true }) credentialKeys: string[];
  @ApiProperty({ type: [String], enum: SERVICE_LANGUAGES }) @IsArray() @ArrayMinSize(1) @ArrayUnique() @IsIn(SERVICE_LANGUAGES, { each: true }) languages: string[];
  @ApiProperty({ enum: ConsultationService, isArray: true }) @IsArray() @ArrayMinSize(1) @ArrayUnique() @IsEnum(ConsultationService, { each: true }) services: ConsultationService[];
  @ApiPropertyOptional({ enum: Gender, description: 'Clients may prefer a counselor of a given gender' }) @IsOptional() @IsEnum(Gender) gender?: Gender;
  @ApiPropertyOptional({ description: 'Country of practice' }) @IsOptional() @IsIn(ref.countries) countryCode?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(2, 80) city?: string;
  /**
   * The professional policy: 15% commission (platform development, marketing,
   * advertising and promoting the professional), no moving clients or payments
   * outside OLFA, fair review before any sanction, permanent ban for proven
   * circumvention with a block on re-registering.
   */
  @ApiProperty({ description: 'Must be true: accepts the professional policy' }) @Equals(true) acceptPolicy: true;
  @ApiProperty({ example: '2026-11' }) @IsString() @Length(1, 20) policyVersion: string;
}

export class CredentialUploadDto {
  @ApiProperty({ enum: ['application/pdf', 'image/jpeg', 'image/png'] }) @IsIn(['application/pdf', 'image/jpeg', 'image/png']) mime: string;
}

export class OfferingDto {
  @ApiProperty({ enum: ConsultationService }) @IsEnum(ConsultationService) service: ConsultationService;
  @ApiProperty({ enum: SERVICE_LANGUAGES }) @IsIn(SERVICE_LANGUAGES) language: string;
  @ApiProperty({ enum: [30, 45, 60, 90] }) @Type(() => Number) @IsIn([30, 45, 60, 90]) durationMinutes: number;
  @ApiProperty({ description: 'Integer minor units (e.g. fils, cents)' }) @Type(() => Number) @IsInt() @Min(1) @Max(10_000_000) priceMinor: number;
  @ApiProperty({ enum: SUPPORTED_CURRENCIES }) @IsIn(SUPPORTED_CURRENCIES) currency: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() active?: boolean;
}

export class CounselorListQuery {
  @ApiPropertyOptional({ enum: CounselorKind }) @IsOptional() @IsEnum(CounselorKind) kind?: CounselorKind;
  @ApiPropertyOptional({ enum: ConsultationService }) @IsOptional() @IsEnum(ConsultationService) service?: ConsultationService;
  @ApiPropertyOptional({ enum: SERVICE_LANGUAGES }) @IsOptional() @IsIn(SERVICE_LANGUAGES) language?: string;
  @ApiPropertyOptional({ enum: [30, 45, 60, 90] }) @IsOptional() @Type(() => Number) @IsIn([30, 45, 60, 90]) durationMinutes?: number;
  @ApiPropertyOptional() @IsOptional() @IsString() cursor?: string;
}

export class BookDto {
  @ApiProperty() @IsUUID() offeringId: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) @Matches(NO_CONTACT, { message: 'contact details are not allowed' }) note?: string;
  /** One of GET /counselors/:id/slots (required when the counselor publishes a schedule). */
  @ApiPropertyOptional() @IsOptional() @IsDateString() slot?: string;
  /** Free-text wish for counselors without a published schedule. */
  @ApiPropertyOptional() @IsOptional() @IsDateString() preferredTime?: string;
}

export class ConfirmDto {
  /** Omitted = the time the client picked from the counselor's schedule. */
  @ApiPropertyOptional() @IsOptional() @IsDateString() scheduledAt?: string;
}

export class ReasonDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) reason?: string;
}

const SCORE = () => (t: object, k: string) => {
  ApiProperty({ minimum: 1, maximum: 5 })(t, k);
  Type(() => Number)(t, k);
  IsInt()(t, k);
  Min(1)(t, k);
  Max(5)(t, k);
};
const YNU = ['NO', 'YES', 'UNSURE'] as const;

/**
 * Mandatory questionnaire after every completed consultation (v1). Quality
 * questions plus direct and indirect questions about moving the relationship
 * outside OLFA. Answers are confidential: counselors never see who answered what.
 */
const happened = (o: ReviewDto) => o.sessionHappened !== false;

export class ReviewDto {
  /**
   * "Did the consultation take place?" Yes → the questionnaire below is required and
   * the held fee is released to the counselor. No → only `disputeReason`; the fee stays
   * held for support to decide (refund or release). Missing = yes (older apps).
   */
  @ApiPropertyOptional() @IsOptional() @IsBoolean() sessionHappened?: boolean;
  @ApiPropertyOptional() @ValidateIf((o: ReviewDto) => o.sessionHappened === false) @IsString() @Length(3, 500) disputeReason?: string;
  @ValidateIf(happened) @SCORE() rating: number; // overall
  @ValidateIf(happened) @SCORE() quality: number; // professionalism & respect
  @ValidateIf(happened) @SCORE() commitment: number; // punctuality & commitment
  @ValidateIf(happened) @SCORE() effectiveness: number; // usefulness of the session
  @ValidateIf(happened) @SCORE() outcome: number; // how far your goals were reached
  @ValidateIf(happened) @ApiProperty({ enum: ['BOOKED_IN_APP', 'PLAN_IN_APP', 'AGREED_OUTSIDE', 'NOT_DISCUSSED', 'NO'] }) @IsIn(['BOOKED_IN_APP', 'PLAN_IN_APP', 'AGREED_OUTSIDE', 'NOT_DISCUSSED', 'NO']) nextSession: 'BOOKED_IN_APP' | 'PLAN_IN_APP' | 'AGREED_OUTSIDE' | 'NOT_DISCUSSED' | 'NO';
  @ValidateIf(happened) @ApiProperty({ enum: ['OLFA', 'DIRECT', 'OTHER_APP', 'UNDECIDED'] }) @IsIn(['OLFA', 'DIRECT', 'OTHER_APP', 'UNDECIDED']) nextChannel: 'OLFA' | 'DIRECT' | 'OTHER_APP' | 'UNDECIDED';
  @ValidateIf(happened) @ApiProperty({ enum: YNU }) @IsIn(YNU) contactShared: (typeof YNU)[number];
  @ValidateIf(happened) @ApiProperty({ enum: YNU }) @IsIn(YNU) offPlatformPayment: (typeof YNU)[number];
  @ValidateIf(happened) @ApiProperty({ enum: YNU }) @IsIn(YNU) externalChannel: (typeof YNU)[number];
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) @Matches(NO_CONTACT, { message: 'contact details are not allowed' }) comment?: string;
}

export class AdminRejectDto {
  @ApiProperty() @IsString() @Length(5, 300) reason: string;
}

export class AdminQueueQuery {
  @ApiPropertyOptional({ enum: ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'] }) @IsOptional() @IsIn(['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED']) status?: string;
}


export class ScheduleDto {
  @ApiProperty() @IsString() @MaxLength(64) timezone: string;
  @ApiProperty() @IsInt() @Min(0) @Max(60) bufferMinutes: number;
  @ApiProperty() @IsInt() @Min(0) @Max(168) minNoticeHours: number;
  @ApiProperty() @IsInt() @Min(1) @Max(90) maxDaysAhead: number;
  @ApiProperty() @IsBoolean() accepting: boolean;
}

export class WindowDto {
  @ApiProperty({ minimum: 1, maximum: 7 }) @IsInt() @Min(1) @Max(7) weekday: number;
  @ApiProperty() @IsInt() @Min(0) @Max(1439) startMinute: number;
  @ApiProperty() @IsInt() @Min(1) @Max(1440) endMinute: number;
}

export class AvailabilityDto {
  @ApiProperty({ type: [WindowDto] }) @IsArray() @ArrayMaxSize(42) @ValidateNested({ each: true }) @Type(() => WindowDto) windows: WindowDto[];
}

export class TimeOffDto {
  @ApiProperty() @IsDateString() startsAt: string;
  @ApiProperty() @IsDateString() endsAt: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(120) note?: string;
}

export class SlotsQuery {
  @ApiProperty() @IsUUID() offeringId: string;
}

export class RescheduleDto {
  @ApiProperty() @IsDateString() scheduledAt: string;
}

export class ReplyDto {
  @ApiProperty() @IsString() @Length(2, 1000) @Matches(NO_CONTACT, { message: 'contact details are not allowed' }) reply: string;
}

export class EscrowDecisionDto {
  @ApiProperty({ enum: ['RELEASE', 'REFUND'] }) @IsIn(['RELEASE', 'REFUND']) decision: 'RELEASE' | 'REFUND';
  @ApiProperty() @IsString() @Length(5, 300) reason: string;
}

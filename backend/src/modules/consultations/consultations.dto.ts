import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ConsultationService, CounselorKind, Gender } from '@prisma/client';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, ArrayUnique, Equals, IsArray, IsBoolean, IsDateString, IsEnum, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';
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
  @ApiPropertyOptional() @IsOptional() @IsDateString() preferredTime?: string;
}

export class ConfirmDto {
  @ApiProperty() @IsDateString() scheduledAt: string;
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
export class ReviewDto {
  @SCORE() rating: number; // overall
  @SCORE() quality: number; // professionalism & respect
  @SCORE() commitment: number; // punctuality & commitment
  @SCORE() effectiveness: number; // usefulness of the session
  @SCORE() outcome: number; // how far your goals were reached
  @ApiProperty({ enum: ['BOOKED_IN_APP', 'PLAN_IN_APP', 'AGREED_OUTSIDE', 'NOT_DISCUSSED', 'NO'] }) @IsIn(['BOOKED_IN_APP', 'PLAN_IN_APP', 'AGREED_OUTSIDE', 'NOT_DISCUSSED', 'NO']) nextSession: 'BOOKED_IN_APP' | 'PLAN_IN_APP' | 'AGREED_OUTSIDE' | 'NOT_DISCUSSED' | 'NO';
  @ApiProperty({ enum: ['OLFA', 'DIRECT', 'OTHER_APP', 'UNDECIDED'] }) @IsIn(['OLFA', 'DIRECT', 'OTHER_APP', 'UNDECIDED']) nextChannel: 'OLFA' | 'DIRECT' | 'OTHER_APP' | 'UNDECIDED';
  @ApiProperty({ enum: YNU }) @IsIn(YNU) contactShared: (typeof YNU)[number];
  @ApiProperty({ enum: YNU }) @IsIn(YNU) offPlatformPayment: (typeof YNU)[number];
  @ApiProperty({ enum: YNU }) @IsIn(YNU) externalChannel: (typeof YNU)[number];
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) @Matches(NO_CONTACT, { message: 'contact details are not allowed' }) comment?: string;
}

export class AdminRejectDto {
  @ApiProperty() @IsString() @Length(5, 300) reason: string;
}

export class AdminQueueQuery {
  @ApiPropertyOptional({ enum: ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'] }) @IsOptional() @IsIn(['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED']) status?: string;
}


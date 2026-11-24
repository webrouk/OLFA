import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { EducationLevel, Gender, MaritalStatus, MarriageTimeline } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayUnique,
  Equals,
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsIn,
  IsInt,
  IsISO31661Alpha2,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

import ref from '../../reference/reference.json';

const NAME = /^[\p{L}\p{M}' .-]+$/u; // letters (any script), spaces, apostrophes, dots, hyphens
const NO_CONTACT = /^(?![\s\S]*(\+?\d[\d\s]{7,}|@|https?:\/\/|www\.))[\s\S]*$/i; // no phone / email / links in bio

export class CreateProfileDto {
  @ApiProperty() @IsString() @Length(2, 40) @Matches(NAME, { message: 'displayName must contain letters only' }) displayName: string;
  @ApiProperty({ example: '1995-04-20' }) @IsDateString({ strict: true }) birthDate: string;
  @ApiProperty({ enum: Gender }) @IsEnum(Gender) gender: Gender;
  @ApiProperty({ example: 'AE', description: 'Country of residence' }) @IsIn(ref.countries) countryCode: string;
  @ApiPropertyOptional({ example: 'AE', description: 'Defaults to the residence country\'s nationality' }) @IsOptional() @IsIn(ref.nationalities) nationality?: string;
  @ApiProperty() @IsString() @Length(2, 80) city: string;
  @ApiProperty({ enum: MaritalStatus }) @IsEnum(MaritalStatus) maritalStatus: MaritalStatus;
  @ApiProperty({ enum: EducationLevel }) @IsEnum(EducationLevel) education: EducationLevel;
  @ApiProperty({ example: 'software_engineer', description: 'Key from shared/reference/occupations.tsv' }) @IsIn(ref.occupations) occupation: string;
  @ApiPropertyOptional({ minimum: 120, maximum: 230, description: 'cm, optional' }) @IsOptional() @Type(() => Number) @IsInt() @Min(120) @Max(230) heightCm?: number;
  @ApiPropertyOptional({ minimum: 35, maximum: 250, description: 'kg, optional' }) @IsOptional() @Type(() => Number) @IsInt() @Min(35) @Max(250) weightKg?: number;
  @ApiProperty({ enum: MarriageTimeline }) @IsEnum(MarriageTimeline) marriageTimeline: MarriageTimeline;
  @ApiProperty({ example: 'islam', description: 'Key from shared/reference/religions.tsv ("undisclosed" keeps it private)' }) @IsIn(ref.religions) religion: string;
  @ApiPropertyOptional({ example: 'sunni', description: 'Must belong to the religion (validated by the API and a DB foreign key)' }) @IsOptional() @IsString() @MaxLength(40) sect?: string | null;
  @ApiPropertyOptional({ description: 'Explicit consent to store religion (special-category data); required unless "undisclosed"' }) @IsOptional() @IsBoolean() religionConsent?: boolean;
  @ApiProperty() @IsString() @MinLength(20) @MaxLength(500) @Matches(NO_CONTACT, { message: 'contact details are not allowed in bio' }) bio: string;
  @ApiProperty({ type: [String], example: ['reading', 'travel'] })
  @IsArray() @ArrayUnique() @ArrayMaxSize(8) @IsString({ each: true }) interests: string[];
  @ApiPropertyOptional() @IsOptional() @IsBoolean() hasChildren?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() wantsChildren?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() smoking?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() willingToRelocate?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() showLocation?: boolean;
  @ApiProperty({ description: 'User confirms they are 18+' }) @Equals(true) ageConfirmed: true;
  @ApiProperty({ description: 'Accepted terms version' }) @IsString() @Length(1, 20) termsVersion: string;
}

/** Gender and birth date cannot be changed by the user after creation. */
export class UpdateProfileDto extends PartialType(CreateProfileDto) {}

export class PreferencesDto {
  @ApiProperty() @Type(() => Number) @IsInt() @Min(18) @Max(99) ageMin: number;
  @ApiProperty() @Type(() => Number) @IsInt() @Min(18) @Max(99) ageMax: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() sameCountryOnly?: boolean;
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(20) @IsIn(ref.countries, { each: true }) countryCodes?: string[];
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(10) @IsString({ each: true }) @MaxLength(80, { each: true }) cities?: string[];
  @ApiPropertyOptional({ enum: MaritalStatus, isArray: true }) @IsOptional() @IsArray() @IsEnum(MaritalStatus, { each: true }) maritalStatuses?: MaritalStatus[];
  @ApiPropertyOptional({ enum: EducationLevel, isArray: true }) @IsOptional() @IsArray() @IsEnum(EducationLevel, { each: true }) educationLevels?: EducationLevel[];
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(10) @IsIn(ref.occupations, { each: true }) occupations?: string[];
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsBoolean() wantsChildren?: boolean | null;
  @ApiPropertyOptional({ type: [String], description: 'Accepted religions (empty = any)' }) @IsOptional() @IsArray() @ArrayMaxSize(10) @IsIn(ref.religions, { each: true }) religions?: string[];
  @ApiPropertyOptional({ type: [String], example: ['islam.sunni'], description: '"religion.sect" (empty = any)' }) @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @MaxLength(71, { each: true }) sects?: string[];
}

/** Chosen once during sign-up (locked when the profile exists). */
export class AccountTypeDto {
  @ApiProperty({ enum: ['MEMBER', 'PSYCHOLOGIST', 'FAMILY_COUNSELOR'] }) @IsIn(['MEMBER', 'PSYCHOLOGIST', 'FAMILY_COUNSELOR']) accountType: 'MEMBER' | 'PSYCHOLOGIST' | 'FAMILY_COUNSELOR';
}

/** Device location; the server rounds to ~1 km and never returns it. */
export class LocationDto {
  @ApiProperty() @Type(() => Number) @IsLatitude() latitude: number;
  @ApiProperty() @Type(() => Number) @IsLongitude() longitude: number;
  @ApiPropertyOptional({ description: 'Country detected on the device (reverse geocoding)' }) @IsOptional() @IsIn(ref.countries) countryCode?: string;
}

/** Privacy settings (all optional — send only what changes). */
export class PrivacyDto {
  @ApiPropertyOptional({ description: 'Show me in discovery' }) @IsOptional() @IsBoolean() discoverable?: boolean;
  @ApiPropertyOptional({ description: 'Reciprocal' }) @IsOptional() @IsBoolean() showOnline?: boolean;
  @ApiPropertyOptional({ description: 'Reciprocal' }) @IsOptional() @IsBoolean() readReceipts?: boolean;
  @ApiPropertyOptional({ description: 'Premium' }) @IsOptional() @IsBoolean() incognito?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() blurPhotos?: boolean;
  @ApiPropertyOptional({ description: 'Show city and distance' }) @IsOptional() @IsBoolean() showCity?: boolean;
}

export class LocaleDto {
  @ApiProperty({ enum: ['ar', 'en'] }) @IsIn(['ar', 'en']) locale: 'ar' | 'en';
}

export class FreezeDto {
  @ApiPropertyOptional({ enum: ['break', 'met_someone', 'busy', 'privacy', 'other'] }) @IsOptional() @IsIn(['break', 'met_someone', 'busy', 'privacy', 'other']) reason?: string;
}

export class DeleteAccountDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(40) reason?: string;
}

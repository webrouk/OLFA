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
  IsInt,
  IsISO31661Alpha2,
  IsOptional,
  IsString,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

const NAME = /^[\p{L}\p{M}' .-]+$/u; // letters (any script), spaces, apostrophes, dots, hyphens
const NO_CONTACT = /^(?![\s\S]*(\+?\d[\d\s]{7,}|@|https?:\/\/|www\.))[\s\S]*$/i; // no phone / email / links in bio

export class CreateProfileDto {
  @ApiProperty() @IsString() @Length(2, 40) @Matches(NAME, { message: 'displayName must contain letters only' }) displayName: string;
  @ApiProperty({ example: '1995-04-20' }) @IsDateString({ strict: true }) birthDate: string;
  @ApiProperty({ enum: Gender }) @IsEnum(Gender) gender: Gender;
  @ApiProperty({ example: 'AE' }) @IsISO31661Alpha2() countryCode: string;
  @ApiProperty() @IsString() @Length(2, 80) city: string;
  @ApiProperty({ enum: MaritalStatus }) @IsEnum(MaritalStatus) maritalStatus: MaritalStatus;
  @ApiProperty({ enum: EducationLevel }) @IsEnum(EducationLevel) education: EducationLevel;
  @ApiProperty() @IsString() @Length(2, 80) occupation: string;
  @ApiProperty({ enum: MarriageTimeline }) @IsEnum(MarriageTimeline) marriageTimeline: MarriageTimeline;
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
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(20) @IsISO31661Alpha2({ each: true }) countryCodes?: string[];
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(10) @IsString({ each: true }) @MaxLength(80, { each: true }) cities?: string[];
  @ApiPropertyOptional({ enum: MaritalStatus, isArray: true }) @IsOptional() @IsArray() @IsEnum(MaritalStatus, { each: true }) maritalStatuses?: MaritalStatus[];
  @ApiPropertyOptional({ enum: EducationLevel, isArray: true }) @IsOptional() @IsArray() @IsEnum(EducationLevel, { each: true }) educationLevels?: EducationLevel[];
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(10) @IsString({ each: true }) @MaxLength(80, { each: true }) occupations?: string[];
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsBoolean() wantsChildren?: boolean | null;
}

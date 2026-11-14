import { Inject, Injectable } from '@nestjs/common';
import { EducationLevel, MaritalStatus, Prisma } from '@prisma/client';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService, SettingsService } from '../../common/infra';
import { compatibility, DEFAULT_WEIGHTS, Member, mutuallyCompatible, parseWeights, rankCandidates, Weights } from '../../domain/matching';
import { dayWindow } from '../../domain/quota-period';
import { ageOn } from '../../domain/security';
import { profileInclude, toPublicProfile } from '../profiles/profile.mapper';
import { EntitlementsService } from '../quotas/quotas.module';

const CANDIDATES_SQL = readFileSync(join(__dirname, 'sql', 'candidates.sql'), 'utf8');

export interface DiscoveryFilters {
  limit: number;
  ageMin?: number;
  ageMax?: number;
  countryCode?: string;
  city?: string;
  interests?: string[];
  // paid
  maritalStatuses?: MaritalStatus[];
  educations?: EducationLevel[];
  occupation?: string;
  minCompatibility?: number;
}

export function usesPaidFilters(f: DiscoveryFilters, basicInterests: Set<string>): boolean {
  return (
    !!f.maritalStatuses?.length ||
    !!f.educations?.length ||
    !!f.occupation ||
    f.minCompatibility != null ||
    (f.interests?.length ?? 0) > 1 ||
    (f.interests ?? []).some((k) => !basicInterests.has(k))
  );
}

type CandidateRow = {
  id: string;
  birth_date: Date;
  gender: Member['profile']['gender'];
  country_code: string;
  city: string;
  marital_status: Member['profile']['maritalStatus'];
  education: Member['profile']['education'];
  occupation: string;
  marriage_timeline: Member['profile']['marriageTimeline'];
  has_children: boolean | null;
  wants_children: boolean | null;
  smoking: boolean | null;
  willing_to_relocate: boolean | null;
  age_min: number;
  age_max: number;
  same_country_only: boolean;
  country_codes: string[];
  cities: string[];
  marital_statuses: MaritalStatus[];
  education_levels: EducationLevel[];
  occupations: string[];
  pref_wants_children: boolean | null;
  interests: string[];
};

@Injectable()
export class MatchingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly entitlements: EntitlementsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async weights(): Promise<Weights> {
    try {
      return parseWeights(await this.settings.get<unknown>('matching.weights', DEFAULT_WEIGHTS));
    } catch {
      return DEFAULT_WEIGHTS; // never let a bad admin value break discovery
    }
  }

  /** Loads a user as a matching Member (profile + preferences + interests). */
  async member(userId: string): Promise<Member | null> {
    const u = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { profile: true, preferences: true, interests: { select: { interest: { select: { key: true } } } } },
    });
    if (!u?.profile || !u.preferences) return null;
    const p = u.profile;
    const pr = u.preferences;
    return {
      profile: {
        id: userId,
        gender: p.gender,
        age: ageOn(p.birthDate, new Date()),
        countryCode: p.countryCode,
        city: p.city,
        maritalStatus: p.maritalStatus,
        education: p.education,
        occupation: p.occupation,
        interests: u.interests.map((i) => i.interest.key),
        marriageTimeline: p.marriageTimeline,
        hasChildren: p.hasChildren,
        wantsChildren: p.wantsChildren,
        smoking: p.smoking,
        willingToRelocate: p.willingToRelocate,
      },
      prefs: {
        ageMin: pr.ageMin,
        ageMax: pr.ageMax,
        sameCountryOnly: pr.sameCountryOnly,
        countryCodes: pr.countryCodes,
        cities: pr.cities,
        maritalStatuses: pr.maritalStatuses,
        educationLevels: pr.educationLevels,
        occupations: pr.occupations,
        wantsChildren: pr.wantsChildren,
      },
    };
  }

  /** Used by the like flow: preference check + score for the match row. */
  async pairCheck(a: string, b: string): Promise<{ compatible: boolean; score: number }> {
    const [ma, mb] = await Promise.all([this.member(a), this.member(b)]);
    if (!ma || !mb) return { compatible: false, score: 0 };
    return { compatible: mutuallyCompatible(ma, mb), score: compatibility(ma, mb, await this.weights()).score };
  }

  /**
   * Discovery: SQL coarse filter → mutual hard filters → score → rank →
   * de-duplicate → record "shown" → public profiles.
   */
  async discover(viewerId: string, f: DiscoveryFilters) {
    const viewer = await this.member(viewerId);
    if (!viewer) throw new AppError(ErrorCode.VALIDATION, 'Complete your profile first');

    const ent = await this.entitlements.forUser(viewerId);
    const basic = new Set((await this.prisma.interest.findMany({ where: { isBasic: true }, select: { key: true } })).map((i) => i.key));
    if (usesPaidFilters(f, basic) && !ent.advancedFilters) throw new AppError(ErrorCode.ENTITLEMENT_REQUIRED, 'Advanced filters require Plus or Premium', { feature: 'advancedFilters' });

    // Requested filters can only narrow the user's saved preferences.
    const ageMin = Math.max(viewer.prefs.ageMin, f.ageMin ?? 18);
    const ageMax = Math.min(viewer.prefs.ageMax, f.ageMax ?? 99);
    if (ageMin > ageMax) return { items: [], weightsVersion: (await this.weights()).version };
    const today = new Date();
    const yearsAgo = (n: number, extraDay = 0) => new Date(Date.UTC(today.getUTCFullYear() - n, today.getUTCMonth(), today.getUTCDate() + extraDay));
    const minBirth = yearsAgo(ageMax + 1, 1); // oldest allowed
    const maxBirth = yearsAgo(ageMin); // youngest allowed

    let countries: string[] | null = null;
    if (viewer.prefs.sameCountryOnly) countries = [viewer.profile.countryCode];
    else if (viewer.prefs.countryCodes.length) countries = viewer.prefs.countryCodes;
    if (f.countryCode) countries = countries ? countries.filter((c) => c === f.countryCode) : [f.countryCode];
    if (countries && countries.length === 0) return { items: [], weightsVersion: (await this.weights()).version };

    const viewerBirth = (await this.prisma.userProfile.findUniqueOrThrow({ where: { userId: viewerId }, select: { birthDate: true } })).birthDate;
    const minPhotos = await this.settings.get('profile.minPhotos', 2);
    const cooldownH = await this.settings.get('matching.shownCooldownHours', 24);
    const pool = Math.min(400, f.limit * 20);

    const rows = await this.prisma.$queryRawUnsafe<CandidateRow[]>(
      CANDIDATES_SQL, // static SQL file; every value below is a bind parameter
      viewerId,
      viewer.profile.gender,
      minBirth,
      maxBirth,
      viewerBirth,
      countries,
      minPhotos,
      cooldownH,
      pool,
    );

    const candidates: Member[] = rows
      .filter((r) => !f.city || r.city.trim().toLocaleLowerCase() === f.city.trim().toLocaleLowerCase())
      .filter((r) => !f.interests?.length || f.interests.some((k) => r.interests.includes(k)))
      .filter((r) => !f.maritalStatuses?.length || f.maritalStatuses.includes(r.marital_status))
      .filter((r) => !f.educations?.length || f.educations.includes(r.education))
      .filter((r) => !f.occupation || r.occupation.toLocaleLowerCase().includes(f.occupation.toLocaleLowerCase()))
      .map((r) => ({
        profile: {
          id: r.id,
          gender: r.gender,
          age: ageOn(r.birth_date, today),
          countryCode: r.country_code,
          city: r.city,
          maritalStatus: r.marital_status,
          education: r.education,
          occupation: r.occupation,
          interests: r.interests,
          marriageTimeline: r.marriage_timeline,
          hasChildren: r.has_children,
          wantsChildren: r.wants_children,
          smoking: r.smoking,
          willingToRelocate: r.willing_to_relocate,
        },
        prefs: {
          ageMin: r.age_min,
          ageMax: r.age_max,
          sameCountryOnly: r.same_country_only,
          countryCodes: r.country_codes.map((c) => c.trim()),
          cities: r.cities,
          maritalStatuses: r.marital_statuses,
          educationLevels: r.education_levels,
          occupations: r.occupations,
          wantsChildren: r.pref_wants_children,
        },
      }));

    const weights = await this.weights();
    const tz = (await this.prisma.user.findUniqueOrThrow({ where: { id: viewerId }, select: { timezone: true } })).timezone;
    const ranked = rankCandidates(viewer, candidates, { weights, minScore: f.minCompatibility, dayKey: dayWindow(today, tz).dayKey, limit: f.limit });
    if (ranked.length === 0) return { items: [], weightsVersion: weights.version };

    const ids = ranked.map((r) => r.member.profile.id);
    await this.prisma.$transaction([
      ...ranked.map((r) =>
        this.prisma.compatibilityScore.upsert({
          where: { viewerId_candidateId: { viewerId, candidateId: r.member.profile.id } },
          create: { viewerId, candidateId: r.member.profile.id, score: r.result.score, breakdown: r.result.breakdown as unknown as Prisma.InputJsonValue, weightsVersion: weights.version },
          update: { score: r.result.score, breakdown: r.result.breakdown as unknown as Prisma.InputJsonValue, weightsVersion: weights.version, computedAt: today },
        }),
      ),
      this.prisma.discoveryHistory.createMany({ data: ids.map((candidateId) => ({ viewerId, candidateId, action: 'SHOWN' as const })) }),
    ]);

    const users = await this.prisma.user.findMany({ where: { id: { in: ids } }, include: profileInclude });
    const byId = new Map(users.map((u) => [u.id, u]));
    return {
      items: ranked.map((r) => toPublicProfile(byId.get(r.member.profile.id)!, this.env.CDN_BASE_URL, { compatibility: r.result.score })),
      weightsVersion: weights.version,
    };
  }
}

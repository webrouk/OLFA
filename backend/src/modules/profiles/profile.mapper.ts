import { Prisma } from '@prisma/client';
import { ageOn } from '../../domain/security';

/** Everything needed to render a profile; loaded with this include. */
export const profileInclude = {
  profile: true,
  interests: { include: { interest: { select: { key: true } } } },
  photos: { where: { deletedAt: null }, orderBy: { position: 'asc' } },
  verifications: { where: { revokedAt: null }, select: { type: true } },
} satisfies Prisma.UserInclude;

export type UserWithProfile = Prisma.UserGetPayload<{ include: typeof profileInclude }>;

type Variants = { thumb?: string; card?: string; full?: string };

const url = (cdn: string, key?: string) => (key ? `${cdn}/${key}` : null);

/**
 * PUBLIC view: no phone, no exact birth date, no status, no non-approved
 * photos, location only if the owner allows it. Photos are CDN variants only.
 */
export function toPublicProfile(u: UserWithProfile, cdn: string, extra: { compatibility?: number; distanceKm?: number | null } = {}) {
  const p = u.profile!;
  const photos = u.photos
    .filter((ph) => ph.status === 'APPROVED')
    .map((ph) => {
      const v = (ph.variants ?? {}) as Variants;
      return { id: ph.id, position: ph.position, thumbUrl: url(cdn, v.thumb), cardUrl: url(cdn, v.card), fullUrl: url(cdn, v.full) };
    });
  const badges = new Set(u.verifications.map((v) => v.type));
  return {
    id: u.id,
    displayName: p.displayName,
    age: ageOn(p.birthDate, new Date()),
    gender: p.gender,
    countryCode: p.showLocation ? p.countryCode : null,
    city: p.showLocation ? p.city : null,
    showLocation: p.showLocation,
    nationality: p.nationality,
    distanceKm: p.showLocation ? extra.distanceKm ?? null : null, // rounded; never coordinates
    maritalStatus: p.maritalStatus,
    education: p.education,
    occupation: p.occupation,
    marriageTimeline: p.marriageTimeline,
    bio: p.bio,
    interests: u.interests.map((i) => i.interest.key),
    photos,
    isPhotosReviewed: badges.has('PROFILE_REVIEW'),
    isLivenessVerified: badges.has('LIVENESS'),
    isIdentityVerified: badges.has('IDENTITY'), // only from a real ID check
    completeness: p.completeness,
    compatibility: extra.compatibility ?? null,
  };
}

/** OWNER view: public view + private fields and every photo with its review state. */
export function toOwnProfile(u: UserWithProfile, cdn: string) {
  const base = u.profile ? toPublicProfile(u, cdn) : null;
  return {
    id: u.id,
    accountStatus: u.status,
    locale: u.locale,
    timezone: u.timezone,
    phone: u.phoneE164, // owner only
    profile: base && {
      ...base,
      countryCode: u.profile!.countryCode,
      city: u.profile!.city,
      birthDate: u.profile!.birthDate.toISOString().slice(0, 10),
      hasChildren: u.profile!.hasChildren,
      wantsChildren: u.profile!.wantsChildren,
      smoking: u.profile!.smoking,
      willingToRelocate: u.profile!.willingToRelocate,
      locationCountry: u.profile!.locationCountry, // owner only; coordinates are never returned
      photos: u.photos.map((ph) => {
        const v = (ph.variants ?? {}) as Variants;
        return { id: ph.id, position: ph.position, status: ph.status, rejectReason: ph.rejectReason, thumbUrl: ph.status === 'APPROVED' ? url(cdn, v.thumb) : null };
      }),
    },
  };
}

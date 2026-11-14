import { Prisma } from '@prisma/client';
import { ageOn } from '../../domain/security';
import { isOnlineVisible, photosBlurred, PrivacyPrefs, privacyOf } from '../../domain/privacy';

/** Everything needed to render a profile; loaded with this include. */
export const profileInclude = {
  profile: true,
  interests: { include: { interest: { select: { key: true } } } },
  photos: { where: { deletedAt: null }, orderBy: { position: 'asc' } },
  verifications: { where: { revokedAt: null }, select: { type: true } },
  privacy: true,
} satisfies Prisma.UserInclude;

export type UserWithProfile = Prisma.UserGetPayload<{ include: typeof profileInclude }>;

type Variants = { thumb?: string; card?: string; full?: string; blur?: string };

/** How the viewer relates to the profile (drives privacy rules). */
export interface ViewContext {
  compatibility?: number;
  distanceKm?: number | null;
  viewer?: PrivacyPrefs; // the viewer's own privacy (reciprocal rules)
  matched?: boolean;
}

const url = (cdn: string, key?: string) => (key ? `${cdn}/${key}` : null);

/**
 * PUBLIC view: no phone, no exact birth date, no status, no non-approved
 * photos, location only if the owner allows it. Photos are CDN variants only.
 */
export function toPublicProfile(u: UserWithProfile, cdn: string, extra: ViewContext = {}, isSelf = false) {
  const p = u.profile!;
  const priv = privacyOf(u.privacy);
  // Blurred until matched: only the pre-blurred variant leaves the server.
  const blurred = photosBlurred(priv, extra.matched ?? false, isSelf);
  // New account awaiting moderation: others see only the basics — never unreviewed photos or text.
  const underReview = !isSelf && u.status === 'PENDING_VERIFICATION';
  const photos = underReview ? [] : u.photos
    .filter((ph) => ph.status === 'APPROVED')
    .map((ph) => {
      const v = (ph.variants ?? {}) as Variants;
      return blurred
        ? { id: ph.id, position: ph.position, thumbUrl: url(cdn, v.blur), cardUrl: url(cdn, v.blur), fullUrl: null, blurred: true }
        : { id: ph.id, position: ph.position, thumbUrl: url(cdn, v.thumb), cardUrl: url(cdn, v.card), fullUrl: url(cdn, v.full) };
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
    bio: underReview ? null : p.bio,
    interests: u.interests.map((i) => i.interest.key),
    photos,
    isPhotosReviewed: badges.has('PROFILE_REVIEW'),
    isLivenessVerified: badges.has('LIVENESS'),
    isIdentityVerified: badges.has('IDENTITY'), // only from a real ID check
    completeness: p.completeness,
    compatibility: extra.compatibility ?? null,
    photosBlurred: blurred,
    underReview,
    // reciprocal presence; never a precise last-seen time
    online: isSelf ? null : isOnlineVisible(extra.viewer ?? privacyOf(null), priv, u.lastActiveAt),
  };
}

/** OWNER view: public view + private fields and every photo with its review state. */
export function toOwnProfile(u: UserWithProfile, cdn: string) {
  const base = u.profile ? toPublicProfile(u, cdn, {}, true) : null;
  return {
    id: u.id,
    accountStatus: u.status,
    locale: u.locale,
    timezone: u.timezone,
    phone: u.phoneE164, // owner only
    frozenAt: u.frozenAt,
    privacy: { ...privacyOf(u.privacy), showCity: u.profile?.showLocation ?? true },
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

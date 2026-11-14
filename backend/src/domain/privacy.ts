/**
 * Privacy rules applied to what one member sees of another. Pure functions so
 * every endpoint (discovery, profiles, matches, likes, chat) behaves the same.
 */
export interface PrivacyPrefs {
  discoverable: boolean;
  showOnline: boolean;
  readReceipts: boolean;
  incognito: boolean;
  blurPhotos: boolean;
}

export const DEFAULT_PRIVACY: PrivacyPrefs = { discoverable: true, showOnline: true, readReceipts: true, incognito: false, blurPhotos: false };

export const ONLINE_WINDOW_MS = 5 * 60_000;

export function privacyOf(row: Partial<PrivacyPrefs> | null | undefined): PrivacyPrefs {
  return { ...DEFAULT_PRIVACY, ...Object.fromEntries(Object.entries(row ?? {}).filter(([, v]) => typeof v === 'boolean')) };
}

/** Reciprocal: you only see others' online status if you show yours. */
export function isOnlineVisible(viewer: PrivacyPrefs, target: PrivacyPrefs, targetLastActive: Date | null | undefined, now = Date.now()): boolean {
  if (!viewer.showOnline || !target.showOnline || !targetLastActive) return false;
  return now - targetLastActive.getTime() < ONLINE_WINDOW_MS;
}

/** Reciprocal: read receipts flow only when both people keep them on. */
export function readReceiptsVisible(sender: PrivacyPrefs, reader: PrivacyPrefs): boolean {
  return sender.readReceipts && reader.readReceipts;
}

/** Photos stay blurred for non-matches when the owner asks for it. */
export function photosBlurred(target: PrivacyPrefs, matched: boolean, isSelf = false): boolean {
  return target.blurPhotos && !matched && !isSelf;
}

/**
 * Incognito (Premium): visible in discovery only to people the user liked.
 * Effective only while the plan includes it.
 */
export function visibleInDiscovery(target: PrivacyPrefs, targetHasIncognito: boolean, targetLikedViewer: boolean): boolean {
  if (!target.discoverable) return false;
  if (target.incognito && targetHasIncognito) return targetLikedViewer;
  return true;
}

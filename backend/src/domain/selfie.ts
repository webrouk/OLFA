/**
 * Selfie verification (first sign-up, right after the profile photos).
 *
 * Criteria — the same list is shown in the app, checked automatically where a
 * machine can check it, and confirmed by a human reviewer for the rest:
 *
 *  C1 live      Taken now, in the app, with the front camera (no gallery, no upload of an old photo):
 *               a one-time challenge (10 min) + a random hand gesture the person must show.
 *  C2 oneFace   Exactly one face in the picture.                         [device + reviewer]
 *  C3 visible   The whole face is visible, centred and close enough
 *               (face ≥ 25 % of the picture width), eyes open,
 *               no sunglasses / mask / hand over the face.               [device + reviewer]
 *  C4 straight  Looking at the camera: head turned / tilted ≤ 20°.        [device]
 *  C5 quality   Sharp and well lit (not too dark, not burnt out), at least
 *               480 px on the short side, no filters or edits.           [server + reviewer]
 *  C6 gesture   Shows the requested gesture.                             [reviewer]
 *  C7 samePerson The same person as in the profile photos.               [reviewer]
 *  C8 real      A real person in front of the camera — not a photo of a screen,
 *               a printed picture or another person.                     [reviewer]
 *
 * The selfie is private: only the verification team sees it, it is never shown
 * to members, and it is deleted after the decision (setting verification.selfieRetentionDays).
 */
export const SELFIE_CRITERIA = ['live', 'oneFace', 'visible', 'straight', 'quality', 'gesture', 'samePerson', 'real'] as const;
export type SelfieCriterion = (typeof SELFIE_CRITERIA)[number];

export const SELFIE_GESTURES = ['thumb_up', 'victory', 'open_palm', 'point_up', 'hand_on_chin'] as const;
export type SelfieGesture = (typeof SELFIE_GESTURES)[number];

/** Reviewer reasons for refusing a selfie (the app shows text + how to fix, by code). */
export const SELFIE_REJECT_CODES = ['selfie_no_face', 'selfie_multiple_faces', 'selfie_face_covered', 'selfie_blurry', 'selfie_dark', 'selfie_gesture_wrong', 'selfie_not_match', 'selfie_not_live'] as const;

export const SELFIE_LIMITS = {
  challengeMinutes: 10,
  minFaceRatio: 0.25,
  maxAngle: 20,
  minEyeOpen: 0.4,
  minShortSide: 480,
  maxBytes: 6 * 1024 * 1024,
  minBrightness: 45, // mean luminance 0–255
  maxBrightness: 225,
  minEntropy: 4, // a blank / flat image has very low entropy
} as const;

/** What the phone measured (ML Kit face detection) before uploading. */
export interface DeviceChecks {
  faces: number;
  faceRatio: number; // face box width / picture width
  yaw: number; // degrees, left-right turn
  roll: number; // degrees, tilt
  leftEyeOpen?: number | null; // 0..1
  rightEyeOpen?: number | null;
}

export interface ImageStats {
  width: number;
  height: number;
  format: string;
  brightness: number;
  entropy: number;
}

/** Criteria the automatic checks found unmet (empty = passes to the reviewer). */
export function failedSelfieChecks(d: DeviceChecks, img: ImageStats): SelfieCriterion[] {
  const out = new Set<SelfieCriterion>();
  const L = SELFIE_LIMITS;
  if (d.faces !== 1) out.add('oneFace');
  if (d.faces >= 1) {
    if (!(d.faceRatio >= L.minFaceRatio)) out.add('visible');
    const eyes = [d.leftEyeOpen, d.rightEyeOpen].filter((x): x is number => typeof x === 'number');
    if (eyes.length > 0 && Math.min(...eyes) < L.minEyeOpen) out.add('visible');
    if (Math.abs(d.yaw) > L.maxAngle || Math.abs(d.roll) > L.maxAngle) out.add('straight');
  }
  if (img.format !== 'jpeg') out.add('quality');
  if (Math.min(img.width, img.height) < L.minShortSide) out.add('quality');
  if (img.brightness < L.minBrightness || img.brightness > L.maxBrightness) out.add('quality');
  if (img.entropy < L.minEntropy) out.add('quality');
  return SELFIE_CRITERIA.filter((c) => out.has(c));
}

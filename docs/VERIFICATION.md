# التحقق في ألفة — Verification

## Order at first sign-up

1. Phone number + OTP, age 18+
2. Gender, account type, details, partner preferences (members), location
3. **Profile photos** (at least 2)
4. **Verification selfie** — mandatory, right after the photos (`/setup/selfie`)
5. The profile is sent for review (`POST /me/verification/submit` refuses with `SELFIE_REQUIRED` until a selfie is waiting or approved)
6. The verification team reviews the **profile, photos and selfie together**. Approval publishes the photos and grants two badges: *Photos reviewed* (PROFILE_REVIEW) and *Real person* (LIVENESS). The account becomes active.

Professionals take the same selfie. It appears in the queue as a stand-alone `LIVENESS` request next to their professional application.

## Selfie criteria

The same eight criteria appear in the app, in `backend/src/domain/selfie.ts` and in `mobile/lib/features/verification/domain/selfie_criteria.dart`.

| # | Criterion | What is required | Checked by |
|---|---|---|---|
| C1 | **live** | Taken now, in the app, with the front camera. The gallery cannot be used. Each capture has a one-time challenge (valid 10 min, single use) with a **random hand gesture**. | App + server (challenge, expiry, single use) |
| C2 | **oneFace** | Exactly one face in the picture | Phone (ML Kit, on device) + server re-check of the reported values + reviewer |
| C3 | **visible** | Whole face visible, face ≥ 25 % of the picture width, eyes open (≥ 0.4), nothing covering the face (sunglasses, mask, hand) | Phone + server + reviewer |
| C4 | **straight** | Looking at the camera: head turn (yaw) and tilt (roll) ≤ 20° | Phone + server |
| C5 | **quality** | JPEG, short side ≥ 480 px, ≤ 6 MB, mean brightness 45–225, entropy ≥ 4 (not blank), no filters or edits | Server (sharp) + phone + reviewer |
| C6 | **gesture** | Shows the gesture that was asked for (`thumb_up`, `victory`, `open_palm`, `point_up`, `hand_on_chin`) | Reviewer |
| C7 | **samePerson** | The same person as in the profile photos | Reviewer |
| C8 | **real** | A real person in front of the camera — not a photo of a screen, a printed picture or someone else | Reviewer |

- The automatic checks refuse clear failures straight away with `SELFIE_CHECKS_FAILED { failed: [criteria] }`. The app shows each unmet criterion and how to fix it, then asks for a new capture with a new gesture.
- Only selfies that pass the automatic checks reach the team. The reviewer confirms C2, C3 and C5 again, and decides C6–C8.

### Reviewer reject codes (selfie)

| Code | Criterion | The app shows |
|---|---|---|
| `selfie_no_face`, `selfie_face_covered` | C3 | how to show the whole face |
| `selfie_multiple_faces` | C2 | only you in the picture |
| `selfie_blurry`, `selfie_dark` | C5 | light / hold still / no filters |
| `selfie_gesture_wrong` | C6 | show the requested gesture |
| `selfie_not_match` | C7 | photos must show you |
| `selfie_not_live` | C1, C8 | live selfie, not a photo of a picture or screen |

A selfie reject code also rejects the waiting selfie. The app then shows **Take a new selfie**. Once the new selfie passes, the profile goes back to review on its own.

## Privacy

- The selfie is uploaded straight to **private storage** with a presigned upload (image/jpeg, ≤ 6 MB). It is never published to the CDN and never shown to members.
- Location and device metadata are removed on the phone. The server removes any metadata that is left.
- Reviewers see it through a short-lived signed link (5 minutes).
- It is **deleted after the decision**: `verification.selfieRetentionDays` (default 30) after review. Abandoned captures are deleted after one day. Only the decision is kept.
- On-device face detection (Google ML Kit) runs locally. The picture is not sent to Google.
- **Female reviewer.** A person can ask that a woman from the team reviews their selfie (`preferFemaleReviewer`). The queue shows this flag so the admin panel can route the selfie accordingly.

## Settings

| Key | Default | Meaning |
|---|---|---|
| `verification.selfieRequired` | 1 | Selfie mandatory at first verification |
| `verification.selfieRetentionDays` | 30 | Days a reviewed selfie is kept |

## Honest limits

- This is **not identity verification**. No official ID is checked, and the *Identity verified* badge is only set by an ID-check provider (none is connected yet).
- Automated checks cannot prove a person is live. That decision rests on the random gesture and the human reviewer. A dedicated liveness/face-match provider can be added later behind the same endpoints.

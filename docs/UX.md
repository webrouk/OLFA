# Navigation, consistency and performance rules (mobile)

## Tabs (one shell for members and professionals: `AppShell` in `core/routing/app_router.dart`)

| Rule | How |
| --- | --- |
| Same bar everywhere | `OlfaNavItems.member/professional` feed both the floating bottom bar (phones) and the side rail (≥ 840 px: tablets, landscape) |
| Active tab is obvious | Burgundy icon, label and tint. Inactive tabs use the muted text colour (≥ 4.5:1), not the disabled one. Semantics mark the tab as selected |
| Each tab keeps its state | `StatefulShellRoute.indexedStack`: each tab keeps its own page stack, scroll position and loaded data |
| Re-tap the open tab | Goes back to the tab's first page and scrolls to the top (`tabReselectProvider` + `TabRoot`). The iOS status-bar tap also scrolls to the top |
| Badges are real | `memberNavBadgesProvider` / `professionalNavBadgesProvider` count new likes, new matches, chats with unread messages, and paid desk requests. 0 shows no badge; the number is capped at 99+ |
| No overlap | The bar hides while the keyboard is open. Pages leave space with `OlfaSize.navBarClearance`, which comes from `NavChrome`: the bar's height inside the shell, only the safe area on pages pushed above it or when the rail is used |

## Moving between pages

- On Android, pages fade in with a 4 % slide in the reading direction (220 ms, `OlfaPageTransitionsBuilder`). iOS keeps its native transition and swipe-back gesture. With "reduce motion" on, pages switch instantly.
- `context.pushOnce(...)` ignores a second tap on the same link within 0.7 s, and ignores a push of the page already on screen. It is used for profiles, counselors, chats, booking and tickets.
- Opening a profile from Discover, Likes, Matches or a chat shows the card's data and cached photo at once. The full profile replaces it in place, with no spinner. The full-size photo loads over the cached card-size photo.
- Discover downloads the next 3 cards' photos in advance.

## Loading

- `AsyncView` keeps the current data on screen while new data loads (refresh, or a filter changed), with a thin progress line. The skeleton appears only on first load.
- `ref.cacheFor(...)` keeps lists for 3 minutes and details for 5 minutes after leaving a page, so going back is instant. Pull-to-refresh still fetches fresh data. The counselor directory caches one result per filter combination.

## Consistency

- Colours, fonts and radii come only from the theme. A test checks that the palette is exactly the 4 identity colours.
- There is one count badge (`CountBadge`) for the tabs, unread chats, compliments left and voice notes left.
- Numbers always use `context.type.number(...)` (Montserrat).
- Counselor labels (type, services, languages) and money formatting ("AED 300.00") are the same in the app, the admin dashboard and the preview.

## Wide screens

- `AdaptivePage` keeps every page at most 720 px wide, centred, on tablets and in landscape. Phones are unchanged.

## Round 2 (sign-up, profiles, search, likes and matches, messages, my profile, professionals)

- **Sign-up never loses answers:**
  - Answers are kept encrypted on the device (same storage as the login tokens) until the profile is submitted, then deleted. Signing out also deletes them.
  - When the app restores answers, the "About you" form shows them with a short notice.
  - "About you" is split into three labelled groups. "Continue" with missing fields scrolls to the first one and says so.
  - Every step uses `pushOnce`, so a double tap opens a step only once.
- **Partner preferences have their own page** (My profile → Partner preferences):
  - It loads the saved preferences (`GET /v1/me/preferences`), saves on its own (no new review) and asks before discarding unsaved changes.
  - Fields the page doesn't edit are sent back unchanged.
  - Before this, the tile opened the sign-up step with default values and "Continue" led into the sign-up flow.
- **Profile page:**
  - It opens instantly from the tapped card. The sections not loaded yet show placeholders, not half-filled data.
  - The bottom actions depend on where you came from:
    - Discover: pass / like.
    - Likes: pass / like back.
    - Matches: open or start the chat (one shared function, `openMatchChat`).
    - Your own profile ("see it as others do"): no actions, no report.
- **Discover:**
  - The next page of profiles loads when 4 cards are left, one request at a time.
  - An empty queue while more profiles are loading shows a loading card, not "no more profiles".
  - The filter button shows how many filters are active.
- **Search & filters:**
  - Height and weight (free on every plan) moved to the basic filters.
  - "Show results" shows the number of active filters.
- **Likes:**
  - The badge and count refresh after liking back or passing.
  - A filter with no results says so and offers "All".
- **Matches:**
  - Each row shows its state: New, Chatting or Taking a break.
  - Tapping a row opens the chat, or the profile when there's no chat yet.
  - The start-chat button now has a 44 px touch area.
- **Messages:**
  - The inbox, archive and unmatched lists build only the visible rows.
  - Consultation and member chats are labelled when both exist.
  - Archive and unmatched support pull-to-refresh.
  - A chat's header shows at once from the inbox row.
- **My profile:**
  - Sections: My profile, Subscription, Consultations, Account.
  - "See your profile as others do".
  - Tapping the completeness card opens the editor.
- **Professionals:**
  - The Profile tab (`ProfessionalProfileScreen`) was imported by the router but the file didn't exist, so the app couldn't build. It now exists. It shows:
    - the public counselor card and review status;
    - prices, hours and reviews;
    - wallet, payout methods and withdrawals;
    - the professional policy and account settings.
  - The desk and wallet lists now leave room for the floating bar.
  - In My consultations, the actions wrap instead of overflowing, and the held / disputed / refunded fee state is shown.

## Round 3 — one verification mark, public preview
- **Verification mark:** one check next to a member's name, never two.
  - Burgundy: the live selfie **and** the ID document are both verified.
  - Grey: only one of them is verified. Long-press says which one.
  - Nothing: neither is verified. The routine photo review every live profile passes does not count.
  - Code: `VerificationLevel` (`shared/models/models.dart`), `UserProfile.verificationLevel`, `VerificationMark` (`shared/components/verification_ticks.dart`), `OlfaColors.markGray`. The two-tick widget and its `tickPhoto` / `tickIdentity` strings were removed because the mark replaces them.
  - The Likes "Verified" filter now means "has a mark" (selfie or ID).
  - Counselors keep their burgundy licence mark.
- **Bidi:** phone numbers inside Arabic chat messages keep their digit order (`isolateNumbers`, display only). Names read "سارة، 27" with the Arabic comma (`nameAge`).
- **Chat composer (preview):** the voice button was clipped at the screen edge and the input sat on the home indicator; both fixed.
- **Public preview:** nothing addressed to the team shows on the screens. State switches and simulators (verification states, OTP hint, failed selfie, closed-account type, offline / incoming-message simulators, store state, "Approve (demo)", admin "try it" notes, "demo" labels) only appear with `#team` in the preview URL (for example `#lang=ar&s=verify&team`). The ad card shows a realistic native ad instead of a layout note.

## Round 4 — chats, counselor inbox, public profile, payment sheet, managed accounts, compatibility
- **Chat composer:** send / mic sit on the right of the text field in every language (Arabic included), attachments on the left; the field keeps its reading direction; the send arrow points up so it reads the same both ways. Opening a chat from the list reuses the list just loaded (no second download).
- **Counselor messages** (`CounselorInboxScreen`): search by name or message (Arabic spelling folded), Active · Ended · Archive tabs with counts, a session-status filter, lazy rows, and on ended/archived chats a "Deleted in N days" tag. Members see the same countdown on their ended consultation chats; archived ones move to Archive.
- **Consultation chat retention:** 30 days after the session ends or the last message, then deleted for both (server). The chat shows the date and the days left; a new message restarts the count on screen at once.
- **Compatibility questions in the chat:** an icon in the chat header and a one-line strip (start / my progress / the other person's progress) open a sheet over the conversation. Questions are grouped by area; each answer is saved as it is chosen. The result appears only when both finish, as its own card in the middle of the thread (score, five areas, agreed answers, topics to talk about) — the conversation is never reloaded and messages continue before and after it. Managed from the dashboard (questions, audience, weights, scoring, on/off, totals).
- **Public profile:** tap the left/right of the photo (or swipe) to move between photos, a photo counter, the next photos fetched ahead; header with the single mark, place, online, compatibility and plans; a pinned jump bar (Photos · About · Basics · Background · Marriage · Interests · Trust); details in labelled cards; "Managed by: Father" where it applies.
- **Payment:** one bottom sheet over the booking page (what, when, price, method, total, pay). Processing can't be dismissed; success, declined and cancelled each have their own state. A failed or cancelled payment keeps the booking and its time; "Try again" pays the same booking. Bookings waiting for payment have "Complete payment" in My consultations.
- **Managed accounts:** at sign-up a member chooses "For me" or "For a family member"; the manager gives their name, relation, whose phone signs in, and confirms the owner's agreement. Settings → Account management to change or end it. Profiles show the relation only.

## Bottom bar: frosted glass
- The floating bar is frosted glass: the page shows through, blurred (σ 22), under a 72 % white pane with a light rim and a soft shadow (`FloatingNavBar`). No gradients; the four brand colours only.
- The active tab sits on a brighter glass pill with a thin burgundy edge that **slides** from tab to tab (420 ms, slight overshoot), following the reading direction; the icon lifts slightly as it arrives.
- High contrast / "reduce transparency" → an opaque white bar; reduce motion → the pill moves without animation. Tablets keep the side rail.

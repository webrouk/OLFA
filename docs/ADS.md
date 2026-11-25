# Native ads in Discovery (Google AdMob)

## Rules

| Rule | Where it is enforced |
| --- | --- |
| Discovery only, as a card between member cards. No ads in chats, profiles or anywhere else | The app has a single ad slot (`features/ads`, used only by `DiscoverScreen`) |
| Free plan only, never on Plus or Premium | Server: `adsForMember()` returns `paid_plan`, and the DB trigger `feature_entitlements_paid_no_ads` refuses `show_ads=true` on paid plans (P0060). App: `discoveryAdsConfigProvider` and `ApiMappers.discoveryAds` ignore ads unless the plan is Free |
| Upgrading removes ads at once | `entitlements` is re-read after a purchase; the ads controller rebuilds and disposes any loaded or loading ad |
| Same frame as a profile card | `DiscoveryAdCard`: same size, 26 px radius, border, shadow and white surface. The AdMob native template is styled in OLFA's colours. A black **Sponsored** chip sits above the ad, outside the ad view |
| Touches never reach like/pass/profile | The ad card has no swipe gesture. While it is shown, the like/pass/undo/compliment buttons are replaced by one **Continue** button. The profile behind it is wrapped in `IgnorePointer`. "Remove ads" (to Plans) sits outside the ad view |
| Lazy loading, no reloads | The SDK starts only for a Free member with ads on (after UMP consent). One ad is loaded `preloadAhead` profiles before its slot and kept in a controller (not a widget), so rebuilds and tab switches never reload it. It is shown only at a card boundary and disposed after "Continue". A no-fill slot is skipped, never retried in a loop. Ads older than 55 minutes are dropped |
| Privacy | Nothing about the member (age, gender, religion, location, interests) is passed to the ad request. Non-personalized (npa) by default. Content rating PG by default. Not child-directed (the app is 18+) |

## Admin dashboard → Ads (`/v1/admin/ads`, permission `settings.manage`)

- **Settings**:
  - kill switch
  - Free-plan switch (`show_ads` entitlement)
  - first ad after N profiles
  - then every N profiles
  - maximum ads per session
  - preload distance
  - personalized ads
  - maximum content rating
  - native ad unit ids for Android and iOS
- **Status**: the page shows the effective state a Free member gets: on, or off with the reason (`switched_off`, `plan_off`, `not_configured`).
- **Defaults**: ads are off and no unit ids are stored. An enabled config with no unit id is refused.
- **Audit**: every change is recorded (`settings.ads`).
- **When changes reach the app**: on the next `GET /me/entitlements`, within about 30 seconds of server cache.

## Before turning ads on

1. Create the AdMob app (Android and iOS) and one **Native advanced** ad unit for each.
2. Put the AdMob **app ids** in the native build config (`mobile/platform_assets/README.md`).
3. In AdMob, under Blocking controls, block the categories that don't fit a marriage platform (dating, gambling, alcohol and similar). Set up the GDPR/US-state consent messages under **Privacy & messaging**. The app shows them through UMP.
4. Update the store listings: "Contains ads", Google Play Data safety (advertising ID), and the App Store privacy label.
5. Update the Privacy Policy so that it mentions ads for Free members.
6. In the dashboard: enter the unit ids, then switch ads on.

Demo builds use Google's public **test** native units, labelled "Test Ad".

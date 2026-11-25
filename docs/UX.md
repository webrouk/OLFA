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

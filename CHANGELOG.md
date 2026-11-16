# Changelog

## Pass 11: About and Search render coverage

- Render coverage for Search no-matches and error, the story viewer (layout only; the fixture image cannot load so the viewer shows its broken-image fallback), and a reel item (layout only; the video does not load in a widget test so it shows "Video could not load"). Playback is not tested.
- Room with an empty chat uses the shared empty state (icon, title, hint) instead of one plain line. Render added for a quiet room (one speaker, no messages).
- Render coverage also for New chat and the stories row (real HomeShell, fixture stories).
- Render tests added for About (normal and 1.8x text), Search (empty and results) and Blocked people. Widget renders only, fixture data.
- About text: the two top up statements now say adding coins is not switched on yet (the wallet screen says the same). The speculative future eSewa payment sentence was removed. The deletion-by-email sentence is kept unchanged. Review item still open: the wording is interim, and the privacy claims below are ungrounded. Privacy claims (no ads, no sale, no tracking, what is stored) need grounded review against real behaviour before publication. Deletion behaviour is still an open design decision.

## Pass 10: large-text fixes and test finder fix

- Emulator flows test imported flutter/material, whose TextField type does not match the app's material_ui widgets, so the finders found nothing (cause of s1 and s2 failing). The test now imports material_ui. Not yet run on an emulator or CI.
- Room: hand-raise rows stack name and buttons, the on-stage list scrolls and tiles grow with text size. Settings theme labels stay on one line. Checked at 1.8x text scale in widget renders (layout only).
- Feed render test uses real CC0 Wikimedia Commons photographs from /tmp when present (not committed); otherwise the invented ridge art.

## Redesign pass 9: product fixes found while reviewing renders

- Posts no longer show a hashtag twice (chips only for tags not already in the text).
- Photos size to their own shape (capped height) instead of one fixed crop.
- Chats top bar: New chat plus a More menu (Live rooms, Call history, Archived chats), not four icons. The emulator flows test opens Live rooms through the menu.
- Settings: Push status no longer prints an exception type. Segmented controls use the app tint, not Material blue.
- buildTheme accepts a font fallback list so non-Latin scripts render in tests.
- Onboarding: drawn ridge and sun art (code, no images) per slide. Last slide no longer says you can top up with eSewa (top up is not switched on).
- Compose: borderless writing area, Photos and Reel actions in a bottom bar, counter only near the limit.
- Render tests: real HomeShell (5-tab nav), compose, photo posts in portrait and wide shapes (invented art), demo-data strip. Checked with flutter analyze and widget renders; not on a device.

## Redesign pass 8: chats list and render coverage

- Chats list rows: ink-tone initial avatars, bold unread preview, crimson time and badge for unread, muted chats grey. Render tests now cover chats (English and Nepali), notifications, settings, sign in and onboarding, show a visible demo-data strip, use the five-tab nav, and render the wallet with top up switched off. Checked with flutter analyze and widget renders; not on a device.

## Redesign pass 7: media-led feed rows and calmer dark primary

- Feed rows: author header on top (avatar, name, handle and time), body at full width, photos and video edge to edge, actions below. Dark theme primary changes from a bright pink to a deeper rose with checked contrast. Render test now includes an invented photo post (original art in test/fixtures, test only) served through a test-only HTTP override. Checked with flutter analyze and widget renders; not on a device.

## Redesign pass 6: chat bubbles

- Received bubbles are white with a hairline border, sent bubbles keep the warm tint, corners are asymmetric toward the sender. Better contrast in light and dark. Checked with flutter analyze and widget renders; not on a device.

## Redesign pass 5: room screen

- Room: LIVE tag and listener count on one line (no more wrapped status), stage as large avatar tiles with a speaking ring and mic state, gift in the top bar, mute button beside the message field, Raise hand kept as a labelled button. Same controls and callbacks as before. Checked with flutter analyze and widget renders; not on a device.

## Redesign pass 4: chats and rooms actions

- Chats: New chat moves from a floating button to a top bar action. Live rooms: Go live moves from a floating pill to a top bar button. Flows test taps New chat by tooltip. Fixes a compile error in the dark capture test (ThemeMode import). Checked locally with flutter analyze (no errors) and the render and unit tests (all pass); not run on a device.

## Redesign pass 3: onboarding

- Onboarding drops the gradient circle for a left-aligned editorial layout: large light numeral, short crimson rule, small icon, headline and body. Slide text now goes through the translation helper. Not yet compiled or captured; CI will be the first check.

## Emulator fixture and dark capture

- CI fixture (test-only, local database) gets four more invented posts from fake members, one in Nepali, one long. Signed-in emulator test also captures dark theme feed, profile and wallet.

## CI honesty

- Emulator job no longer hides a failing flows test (continue-on-error removed). New docs/VERIFICATION_STATUS.md lists which flows pass, fail or are unverified.

## Redesign pass 2

- Compose moved from a floating button (it covered post actions) to the Home app bar. Profile Edit button uses the primary crimson. Notification icon colours use the ink palette.

## Feed row author line

- Author name no longer truncates early; menu button no longer adds height.

## Avatar cleanup

- Removed an unused variable after the redesign.

## CI analyze output

- Analyze step reports error and warning lines in any format.

## Visual redesign, first pass

- New palette (warm paper, ink text, crimson only for actions and the active tab), flat navigation bar, underline tabs, 10 px corners. Feed posts are flat rows with hairline dividers, inline author line, plain hashtag links and inset media instead of tinted cards. Wallet balance is a ledger header. Avatars use ink tones. Layout and styling only, no behaviour change. Not yet inspected on a device.

## Push hardening

- Pushes carry no message text (title is the sender or group, body is "New message", "Voice message" or "Photo"). Muted members and anyone blocked either way get none. Failed or slow provider calls never fail a send, and only an explicit UNREGISTERED answer removes a device token.

## Push sender (server)

- API can send chat message pushes through FCM HTTP v1 with a service account (FCM_CREDENTIALS). Off until set. CI tests use a faked provider and a generated key. Not verified against Firebase, no device receipt, iOS not covered.

## Voice bubble contrast

- Progress track in voice bubbles uses a visible track colour (was faint in light mode).

## Emulator text entry finder

- Flow test targets the single visible text field without a first-element finder, which failed inside the Flutter finder.

## Emulator typing helper

- Flow test types through the text input channel and prints a short stack for failed steps.

## Emulator flow test robustness

- Waits for the compose page, and returns to the tabs after a failed step so later steps still run.

## Emulator CI timeouts

- Emulator drive runs are capped at 10 minutes each and the job at 40.

## Emulator interaction run

- New emulator test: like, compose post, start chat and send, rooms list, wallet, with screenshots and screen recordings (local fixture API, synthetic member, not live services).

## Voice message render

- Render test for a chat with two voice message bubbles (mock data, layout only; playback not exercised).

## v30 deployed

- v30 is live: route and event cache at start, plus the repo API code (including the inert media:move-to-b2 command, never run). config/cache.php was left as in v29 to avoid a second change. Rollback target: v29.

## Route and event cache at start

- The image start script now also caches routes and events (config was already cached). CI runs the whole API test suite a second time with both caches on. The 68 routes list identically with and without the cache (method, uri, action, middleware). Not deployed. Effect on speed is not measured yet.

## Feed latency notes updated

- Added the earlier select-1 probe result (about 230 ms per trivial query) and a live check showing a zero-query route still takes 0.7 to 0.9 s. Doc only.

## Android adaptive icon

- Adaptive launcher icon (red background colour plus mark layer kept in the safe zone) for Android 8 and up. Older devices keep the existing icons. iOS icon sizes were already complete. Checked as a flat preview with a circle mask; not yet seen on a launcher.

## Feed latency notes

- docs/FEED_LATENCY.md records the 7 queries per feed page, measured timings and the untested causes. No code change.

## Nepali coverage

- 21 more UI strings (rooms, gifts, calls, wallet, about) go through the Nepali map. Translations were written by the build agent and need review by a native Nepali speaker before release. Many screens, errors and server messages are still English only.

## Short follower counts

- Profile counts show 1.2K and 2.5M style from 1000 up. Unit tested.

## Populated profile render

- Render test for a member profile with counts and two posts (mock data, layout only).

## Gift sheet test

- Widget test: tapping a gift the balance cannot cover sends no request and shows the shortfall.

## Room host label from stable identity

- The host label on the stage list uses the host identity the API returns at join, not the display name. Unit tests cover two members with the same name and a missing host identity. The server already restricts the speaker action to the room host by account id.

## Gift sheet edges

- Gift sheet scrolls on short screens and dims gifts the balance cannot cover, with a clear message on tap. Rendered in CI (mock data).

## Room stage list

- The room now shows who is on stage with host and you labels and speaking or muted state; the host can move a speaker back to listeners (the same take-mic-back action as before). Dismissing a raised hand now only clears it locally and no longer sends a take-back notice to a member who never had the mic. Layout rendered in CI; real room, audio and token flow still unverified.

## RoomView split

- The room screen is now a RoomView widget that takes plain data and callbacks; RoomPage feeds it from LiveKit. CI renders host, listener and failed states. Layout only, no audio.

## Account deletion design

- Added docs/ACCOUNT_DELETION_DESIGN.md: store requirements from official sources, proposed flow, and open decisions. Nothing implemented, nothing promised to users.

## Release builds refuse E2E_TOKEN_BASE

- Runtime guard: a release or profile build with the setting refuses to sign in. The first compile-time attempt did not compile and was removed.

## Test-only token base

- The app accepts an E2E_TOKEN_BASE build setting (empty in all normal and release builds) so the emulator test can get its token from a local fixture. The API still verifies every token.

## Signed-in emulator test against a local API

- Emulator job also boots this API locally (sqlite, throwaway key, synthetic member, tests/E2E, not in the image) and drives the app signed in: feed and profile screenshots. Isolated app-to-local-API evidence only, not Auth0 or live. Debug builds allow cleartext for it; release builds do not.

## Emulator screenshots

- Emulator job now runs through flutter drive and publishes its screenshot to the emulator-shots branch. Public repo, standard runners, no cost.

## Emulator smoke test in CI

- New CI job starts the app on an Android emulator and checks the first screen draws (no sign in, no API calls). Allowed to fail while it is proven. Does not cover audio, calls, push or playback.

## Rooms list render

- CI also renders the live rooms list (mock-backed layout only). The room screen itself needs the LiveKit native library and is not covered by widget tests.

## Render tests for wallet, gift sheet, chat

- CI now renders the real wallet, gift sheet and chat widgets with canned API replies (light and dark). Layout check only, not device behaviour.

## media:move-to-b2

- New artisan command moves database-stored media to B2 per row, verifies recorded size first, reads the file back from B2 and compares size and SHA1 before emptying the database copy, keeps the row on any failure. Tested with a faked B2 in CI. Not yet run against live data.

## Calendar excluded from builds

- Nepali calendar screen and its month table removed from the source tree until provenance is settled; replacement tracked as open.

## Nov 16 capacity doc correction

- CAPACITY_MODEL.md now uses measured Server-Timing figures and labels the knee numbers illustrative.

## 0.1.1 - 2026-11-15

- API: feed, chat, media stored in Postgres, Auth0 token verification. Hosted at https://sanjaal-api.onrender.com.
- Repository restored from the published image after the build box was reset. API test suite rewritten (18 tests, 66 assertions): token checks with a local RSA key, posts, likes, comments, media in the database with Range, chat.

## Unreleased

- API: persistent database connections per server worker (database now in another region). Free Postgres moved from Neon to Aiven; see docs/SCALING.md.

- API: media now goes to a private Backblaze B2 bucket (free 10 GB, no card) when B2 settings are present. The database keeps only a metadata row, reads redirect to B2 with a cached week long download token so video seeking and caching are served by B2, not by the API. Falls back to database storage when B2 is not configured (tests). New column media_blobs.storage.

- CI: a render test draws real screens (feed with post cards, profile header, nav bar) in light and dark with real fonts and icons and publishes the PNGs to a renders branch, so design can be checked without a device. Network images are not fetched there.

- Brand: original Sanjaal mark (Himal peaks over a network line) as launcher icons for Android and the iOS 1024 icon. Generator in docs/brand.

- API: database connections are now really reused inside each server worker (the earlier setting never reached the running image; checked live). A warm request skips the roughly 0.5 second connect cost. Responses carry a Server-Timing header with app time, database time and query count.

- API: the feed makes two fewer database round trips (blocks in one query, reactions and your own reaction in one query).

- API: a token that already passed RS256 verification is remembered for up to five minutes (never past its expiry), cutting per-request CPU.

- Design pass, step 1: one theme for light and dark with pill buttons, filled inputs, rounded cards, sheets and dialogs, floating snack bars. Not yet checked on a device.

- Gifts with coins. A Gift button on posts and reels opens a sheet with six gifts (Rose 5, Heart 10, Momo 20, Crown 50, Himal 100, Rocket 500 coins). Coins move from sender to creator in one locked transaction, both ledger sides are written, and gifts show in the wallet history. No cash out.

- App: voice messages in chat. Tap the mic, record up to 2 minutes with a timer, discard or send. Voice bubbles play and pause with a progress bar. Uses AAC at low bitrate (about 360 KB per minute). Reply previews say Voice message.

- App: smaller uploads (photos 1280 px at quality 78, avatars 640 px, stories up to 20 s, reels up to 60 s) to stay inside free storage and delivery limits.

- API: cache moved from the database to local files (each request was paying a cross-region query for the Auth0 key cache). Requests without a token now return 401 instead of 500.

- API: feed reaction counts and the viewer's reaction load in two queries per page instead of three per post (feed went from 13 to 9 queries for two posts, flat after that).

- API: media route reads only the requested byte range from the database, answers 304 from the ETag without reading the file, and caps one range response at 2 MB. docs/SCALING.md added with the scaling path and cost estimates. Tests: 36 passing.

- 0.4.0: six reactions, 24 hour stories, chat photos, replies, typing, pin, mute, archive, incoming call alert and call history. API: POST/DELETE /posts/{id}/reaction, /stories routes, PATCH /conversations/{id}/settings, POST /conversations/{id}/typing, /calls routes, message kind, media and reply fields. Tests: 34 passing.

- 0.3.0 rebuild of the Flutter app: five tab shell, onboarding, brand theme with dark mode, English and Nepali labels, reels pager, profiles with avatars and follow, search, hashtag pages, notifications screen, settings, comment replies, multi photo posts, report and block, member picker for new chats.
- API: GET /users/{username}, /users/search, POST /auth/me/avatar, bio on PATCH /auth/me, GET /notifications, block and report routes, comment replies and delete. Feeds hide blocked members. API tests: 30 passing.

- Merged video reels (streaming playback) back into main.
- Added GitHub Actions CI: API tests, Flutter analyze and test, release APK artifact, unsigned iOS IPA artifact on a macOS runner.
- Added the iOS platform (bundle id au.fintex.sanjaal) with photo, camera and microphone permission strings.
- Chat: realtime by long poll. The server holds a request open for up to 20 seconds until a new message arrives, so messages show up almost instantly with no extra socket server. The app loops on this call. API server workers raised from 4 to 12 to carry open requests. Added a long poll test (19 API tests, 72 assertions).
- API download route for the Android build at /sanjaal-arm64.apk (image v2).
- Wallet: internal coin ledger (1 coin = NPR 1 of verified top up), member to member transfers, history, and eSewa ePay v2 top up against the eSewa test environment. Coins are credited only after the signed return payload and the eSewa status API both confirm the payment, and only once per payment. No cash out. Khalti is not built (needs Khalti merchant test keys). Flutter wallet screen under Me. API tests: 26 passing (109 assertions).
- Social sign in: Continue with Google through Auth0 (authorization code with PKCE, redirect au.fintex.sanjaal://login-callback). Uses Auth0 development keys, so Auth0 shows a dev-keys notice on the consent screen. Facebook and Apple are not built: Facebook needs a Meta developer app (Auth0 has no dev keys for it), and Apple it needs an Apple Services ID and key from the Apple Developer account.
- iOS: ITSAppUsesNonExemptEncryption set to false and a privacy manifest added (no tracking, no collected data types, UserDefaults reason CA92.1). Not yet built on macOS CI.
- About, privacy and terms screen naming Fintex Australia Pty Ltd. App version set to 0.2.0+2.
- Notifications v1 uses polling, not push. The app asks GET /notifications/summary every 30 seconds while open and shows an unread badge on the Chats tab. Push (FCM and APNs) is planned for launch, once an account strategy exists.
- Calls backend: POST /conversations/{id}/call-token returns a LiveKit room join token for members only (503 until LiveKit is configured). LiveKit Cloud Build plan: no card, 5,000 WebRTC minutes a month, 100 concurrent connections. Config via LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET. API tests: 27 passing.
- Calls in the app: voice and video call buttons in every chat, over LiveKit (livekit_client). Camera, microphone and Bluetooth permissions added on Android. The release build runs in CI, so the call screen is analyzed but not yet run on a device.
- CI: API job uses PHP 8.4, matching the container image and the locked Symfony 8 packages.
- CI: the APK step now reports build errors as annotations.
- Android build: Gradle memory raised for CI runners (the first CI build ran out of Metaspace compiling plugins). Local builds on small machines will need less.
- CI: pushing a v* tag builds everything and publishes a GitHub release with the APKs, the unsigned IPA and SHA256SUMS.txt.
- The API host download links (/download and /sanjaal-arm64.apk) redirect to the latest release APK. Set APK_URL to change the target.

## Unreleased (batch)
- Render preview fix: buildTheme takes an optional fontFamily.
- Push: device token registration (app and API). Sending is pending a server credential.
- Settings shows push status (registered, or why it is off).
- Button, app bar and text button styles carry the theme font family.
- Push status wording: registered device is not working delivery.
- Live audio rooms: host speaks, listeners join subscribe-only, gifts to the host with an in-room notice. API: rooms table, /rooms endpoints.
- Live rooms: chat, raise hand, host lets a listener speak (server permission change). Member display names never fall back to an email address (API presenters, rooms, chat titles, sign-up, and a one-time scrub of stored names).
- Reels: follow button on each reel, progress bar with scrubbing, next and previous reels preload. API: feed authors carry a following flag (one extra query per page).
- Nepali calendar (Settings): Bikram Sambat today, month grid, and named public days for 2083 BS from Nepal embassy lists. Converter tested against 30 published date pairs (CI).
- Calendar shows today in Nepal time (UTC+5:45), says embassy lists are not a Nepal-wide notice, and docs/THIRD_PARTY.md records the data source and its open licence question.
- Recorded the provenance review of the calendar table as an open release blocker.
- API: removed the X-Powered-By version header (expose_php off), added nosniff, no-referrer, HSTS and frame-deny headers, closed the CORS wildcard (native app needs no browser origin).
- Security: API image v28 runs PHP 8.4.27 on Alpine 3.24 with Caddy and php-fpm (PHP2Shell CVE-2026-109618/109619 fixed). See docs/SECURITY.md.
- API start script logs the running PHP, php-fpm, Caddy and Alpine versions at boot so the deployed runtime can be read from the service logs.
- Docs: synthetic capacity sketch using the Breakscale engine locally (docs/CAPACITY_MODEL.md). Not measured production capacity.

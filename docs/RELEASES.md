# Releases

Publisher: Fintex Australia Pty Ltd, ABN 60 688 406 108, contact@fintex.au.

## Unreleased (API image v9)

Visual redesign first pass (theme, feed rows, wallet header); styling only.

Room host label uses stable identity (tests for same-name members). Gift sheet scrolls on short screens and dims unaffordable gifts. Room shows an on-stage list with speaker identity and state, and clearer host action copy. Room screen split into RoomView with host, listener and failed renders (layout only). Account deletion design note added (not implemented). Release and profile builds refuse to sign in if the test-only E2E_TOKEN_BASE setting is present (runtime guard, not yet exercised in a release build). Signed-in emulator test against a local isolated API added to CI. Emulator smoke job with screenshot added to CI (start and first screen only). Render tests added for wallet, gift sheet, chat and rooms list. Command media:move-to-b2 added (not yet run live). Nepali calendar and its month table removed until provenance is settled. Capacity doc now uses measured Server-Timing and labels knee figures illustrative. Media route fix after the free database hit its transfer cap: byte-range reads, ETag 304 without reading the file, 2 MB cap per range response. See docs/SCALING.md. Database moved to Aiven free Postgres, persistent connections (API image v10). Feed queries batched (API image v12: file cache, clean 401). Media to Backblaze B2 (API image v13). Voice messages and gifts with coins (not released). No app release.

Emulator CI now also runs an interaction test (like, post, chat, rooms list, wallet) and records the screen. Local fixture only.

Push sender for chat messages added server side (off until a Firebase service account is configured; fake-provider tests only).

## 0.4.0 reactions, stories, chat depth, calls, 2026-11-15

Six reactions on posts and reels (tap for a heart, long press for like, love, laugh, wow, sad, angry) with counts. Stories that last 24 hours: photo or video, a ring row above the feed, full screen viewer with tap to move, viewer list and delete for your own. Chat: photo messages, reply to a message, typing indicator, pin, mute and archive from a long press, archived list. Calls: full screen incoming call alert with accept and decline (checked every 5 seconds while the app is open, no push yet) and a call history screen with missed calls and call back. API image v8 adds these routes (34 tests passing).

Release assets are built by CI from tag v0.4.0, debug-signed like earlier builds.

Not in 0.4.0: voice messages, push notifications, Khalti, Facebook and Apple sign in, cash out. Not tested on a physical device.

## 0.3.0 full app rebuild, 2026-11-15

New app shell and the missing v1 screens. Home (For you and Following, search, notifications), full screen Reels pager, Chats (with a member picker and groups), Wallet and Me as five tabs; onboarding; Sanjaal brand, light and dark theme, English and Nepali for the main labels; profiles with avatar upload, bio, follow counts, follow and message buttons; search for people and hashtags; hashtag pages; notifications for likes, comments and follows; comment replies and delete; up to four photos per post with full screen viewing; report and block; settings with blocked list, contact and account deletion request. API image v7 adds the matching routes.

Release assets are built by CI from tag v0.3.0 (debug-signed, same caveat as 0.2.0, with SHA256SUMS.txt). Download link: https://sanjaal-api.onrender.com/download follows the APK_URL setting on the API.

Not in 0.3.0: Khalti, Facebook and Apple sign in, push, cash out, and voice or image messages in chat. Not tested on a physical device.

## 0.2.0 Android and iOS, 2026-11-15

Built by CI from tag v0.2.0 and published at https://github.com/MaisySen/sanjaal/releases/tag/v0.2.0 with SHA256SUMS.txt. Most phones need app-arm64-v8a-release.apk. The IPA is unsigned and cannot be installed on a phone until it is signed with an Apple account.

Signing caveat: these Android builds are signed with the Flutter debug key. When we switch to our own upload key, Android will refuse to update over a build signed with a different key, so everyone must uninstall the app first and sign in again. An upload keystore exists and is kept in the vault, not in the repo. Switching CI to it needs repository secrets that the repo owner adds.

Contents: video reels, long poll chat, coin wallet with eSewa test mode, Google sign in (Auth0 development keys), voice and video calls over LiveKit, about and privacy screen, unread badge by polling. Not tested on a physical device yet.

## 0.1.1 hosted API, 2026-11-15

Live at https://sanjaal-api.onrender.com (Render free web service, Docker Hub image sanjaalapp/sanjaal-api, Neon free Postgres). Free instances sleep after 15 minutes idle.

Verified against the hosted API: Auth0 sign-up and sign-in, authenticated post with image upload, media fetch with Range, direct chat send and read.

Limits: chat polls every 4 seconds (no websocket host). Calls, coin wallet and social login are not built.

## 0.1.1 Android APK, 2026-11-15

Built with Flutter release mode, arm64, signed with the Flutter debug key (sideload only, not store-ready). API base is https://sanjaal-api.onrender.com/api/v1.

Verified: `flutter analyze` clean; the app's own Session client passed a live run against the hosted API (sign-up, sign-in, post, invalid image refused, like, comment, direct chat send and read, delete, sign-out). The APK has not been run on a device (none available in the build environment).

Not built yet: Khalti, Facebook and Apple sign in, push notifications. Calls (voice and video) are in the code and need a device test from the CI build. Notifications v1 poll every 30 seconds with a Chats badge. Chat uses long poll.

## Video reels status

Video reels are merged into main (f963bad restored). The 2 GB build host cannot compile the video_player plugin, so release APKs with video are built by CI (see .github/workflows).

- Render previews: component text styles now resolve the test font, so button and app bar labels show in CI renders.

- Push (client half): firebase_core and firebase_messaging, device token registered after sign in and removed on sign out. API: device_tokens table, POST /devices, POST /devices/remove. The sender is not built yet: it needs a Firebase service account key stored in the vault.

- Live rooms (API plus app). CI and API tests only. Needs a two-device check: host audio reaching a listener, gift notice, end room.
- Rooms chat and hand raise run over the LiveKit data channel. API lifecycle and privacy tested in PHPUnit. Not verified: audio, multi-device gifts and chat, the live speaker grant against LiveKit, app compile.
- Reels depth in app: CI compile only, not run on a device. Feed following flag tested in PHPUnit.
- Nepali calendar: BS month table from an open source project (2000 to 2099), checked against embassy holiday pairs. Canberra list has one internal conflict (29 Asoj), left out. Lunar festival dates beyond 2083 not provided. Device check pending.
- Licence of the BS month table is unconfirmed (docs/THIRD_PARTY.md). Do not ship to a public store until settled.
- BLOCKER: Nepali calendar table has an unresolved provenance gap (docs/THIRD_PARTY.md). Remove or replace before any APK.
- Security review (Nov 2026): runtime PHP 8.4.23 is behind, Alpine 3.20 base is EOL, built-in server in production. Fixes tracked in docs/SECURITY.md.
- SECURITY: v26 and v27 ran PHP 8.4.23 (PHP2Shell affected). v28 fixes the runtime. Exposure window on the affected build was about 21 hours on 15 Nov 2026. Credentials rotated, see docs/SECURITY.md.
- v29 adds a boot-time runtime version log line.
- 2026-11-15 security: credentials rotated (APP_KEY, database, LiveKit, B2), eSewa confirmed as test values, Neon recovery and its old credential still open. Details in docs/SECURITY.md.
- 2026-11-16 docs: docs/CAPACITY_MODEL.md, synthetic model only, no code change in the API or app.

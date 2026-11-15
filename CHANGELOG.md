# Changelog

## 0.1.1 - 2026-11-15

- API: feed, chat, media stored in Postgres, Auth0 token verification. Hosted at https://sanjaal-api.onrender.com.
- Repository restored from the published image after the build box was reset. API test suite rewritten (18 tests, 66 assertions): token checks with a local RSA key, posts, likes, comments, media in the database with Range, chat.

## Unreleased

- API: persistent database connections per server worker (database now in another region). Free Postgres moved from Neon to Aiven; see docs/SCALING.md.

- API: media now goes to a private Backblaze B2 bucket (free 10 GB, no card) when B2 settings are present. The database keeps only a metadata row, reads redirect to B2 with a cached week long download token so video seeking and caching are served by B2, not by the API. Falls back to database storage when B2 is not configured (tests). New column media_blobs.storage.

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

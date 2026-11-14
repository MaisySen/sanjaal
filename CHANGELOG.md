# Changelog

## 0.1.1 - 2026-11-15

- API: feed, chat, media stored in Postgres, Auth0 token verification. Hosted at https://sanjaal-api.onrender.com.
- Repository restored from the published image after the build box was reset. API test suite rewritten (18 tests, 66 assertions): token checks with a local RSA key, posts, likes, comments, media in the database with Range, chat.

## Unreleased

- Merged video reels (streaming playback) back into main.
- Added GitHub Actions CI: API tests, Flutter analyze and test, release APK artifact, unsigned iOS IPA artifact on a macOS runner.
- Added the iOS platform (bundle id au.fintex.sanjaal) with photo, camera and microphone permission strings.
- Chat: realtime by long poll. The server holds a request open for up to 20 seconds until a new message arrives, so messages show up almost instantly with no extra socket server. The app loops on this call. API server workers raised from 4 to 12 to carry open requests. Added a long poll test (19 API tests, 72 assertions).
- API download route for the Android build at /sanjaal-arm64.apk (image v2).
- Wallet: internal coin ledger (1 coin = NPR 1 of verified top up), member to member transfers, history, and eSewa ePay v2 top up against the eSewa test environment. Coins are credited only after the signed return payload and the eSewa status API both confirm the payment, and only once per payment. No cash out. Khalti is not built (needs Khalti merchant test keys). Flutter wallet screen under Me. API tests: 26 passing (109 assertions).
- Social sign in: Continue with Google through Auth0 (authorization code with PKCE, redirect au.fintex.sanjaal://login-callback). Uses Auth0 development keys, so Auth0 shows a dev-keys notice on the consent screen. Facebook and Apple are not built: Facebook needs a Meta developer app (Auth0 has no dev keys for it), and Apple it needs an Apple Services ID and key from the Apple Developer account.
- iOS: ITSAppUsesNonExemptEncryption set to false and a privacy manifest added (no tracking, no collected data types, UserDefaults reason CA92.1). Not yet built on macOS CI.

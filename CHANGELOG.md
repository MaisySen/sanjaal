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

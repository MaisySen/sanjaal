# Releases

Publisher: Fintex Australia Pty Ltd, ABN 60 688 406 108, contact@fintex.au.

## 0.1.1 hosted API, 2026-11-15

Live at https://sanjaal-api.onrender.com (Render free web service, Docker Hub image sanjaalapp/sanjaal-api, Neon free Postgres). Free instances sleep after 15 minutes idle.

Verified against the hosted API: Auth0 sign-up and sign-in, authenticated post with image upload, media fetch with Range, direct chat send and read.

Limits: chat polls every 4 seconds (no websocket host). Calls, coin wallet and social login are not built.

## 0.1.1 Android APK, 2026-11-15

Built with Flutter release mode, arm64, signed with the Flutter debug key (sideload only, not store-ready). API base is https://sanjaal-api.onrender.com/api/v1.

Verified: `flutter analyze` clean; the app's own Session client passed a live run against the hosted API (sign-up, sign-in, post, invalid image refused, like, comment, direct chat send and read, delete, sign-out). The APK has not been run on a device (none available in the build environment).

Not built: calls, coin wallet, social login, video playback, push notifications. Chat polls every 4 seconds.

## Video reels status

Video posting with streaming playback is on branch `video-reels` (commit f963bad). The release APK is built from main without it, because the video_player plugin build exceeds the memory of the small build host (three attempts killed by the OOM killer). Build it on a larger machine to ship video. The API already supports video upload and Range streaming.

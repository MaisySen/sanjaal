# Releases

Publisher: Fintex Australia Pty Ltd, ABN 60 688 406 108, contact@fintex.au.

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

# Integrated app preparation, November 19, 2026

This branch is preparation, not a release or product-completion record. The actual client artifact must be traced to its own CI run and digest before any later finalization. Compilation does not prove installation, native behavior or speed.

## Source boundaries

- Historical last-observed Samsung client: source `68aec83024c80f8d0951a03b79cd6112c4f40074`, version 0.5.5 (2010), private update on November 17. This is not a new device read.
- Loading/session lane: exact isolated app tree from source `599da314c34bf0f6961ff4ca00d82c3ddd8c4003`, including the new Home handover request-identity fix. Its engineering APK is debug-key-signed and reuses 2010. It is not a legitimate upgrade artifact.
- This branch adds the existing bounded local video-poster extraction/fallback and prepared English/Nepali label/template coverage to that lane. The native extractor may fail without blocking video publication. The current server source already supports the poster field; no new runtime backend feature is proposed here.
- Backend runtime files remain those of `7bb60561c6e9efde2c99bcade0f77053fd1c7680`, the source of last-verified live image `29858723492076017fac63d273423243eb48f53cc3410dbe03a927b38c78eb66`. Added compatibility fixtures and local-only fault injection are test code, not deployed routes.
- New group member-removal, ownership-transfer and invitation-policy controls are excluded. The broader recovered branch and its schema changes are not substituted for the deployed API.
- Keyed B2 staging, budget/admission tables and sweep work are excluded. No real B2 verification, protected-media conversion, migration, remote cleanup or media-cache change is part of this branch.

## Full-app acceptance reconciliation

| Required journey | What this preparation retains or adds | Proof still needed |
| --- | --- | --- |
| Start and return | Secure refresh storage, retryable startup failure, shared refresh, account/request boundaries, keep-alive API client, one-use fresh Home bundle | Exact integrated native startup/restore, then physical process-death/background/network recovery. Synthetic delay tests are not device latency. |
| Home and Reels | Retained five-tab state and feed/reel position; poster/fallback for videos; current access checks rather than persistent feed caching | Exact integrated visual review, genuine Samsung scroll/back/playback/audio and loading feel. |
| Post, Only me story and reel | Existing non-blocking upload strip, progress/error/retry, immediate local confirmed result, draft guards and explicit Share | Local native create/retry tests, then complete physical-device journey and recording from the final candidate. Local response-loss testing does not enable production replay/B2. |
| Five tabs and Settings | Home, Reels, Chats, Wallet, Me; floating glass bar; top-left Settings and grouped searchable options retained | Final integrated screen-by-screen review against available references and physical five-tab recording. Missing reference bytes remain an explicit limit. |
| Chat and group | Distributed chat/history/private-media protections retained; language coverage improved. Unready group administration additions excluded | Native network/retry/history and two-device delivery checks. No claim of new live group controls. |
| Wallet | Required destination retained with deposits, transfers and cash-out unavailable | Providers, legal/operational readiness and verified money paths are separate. No money activation for appearance. |
| Calls, rooms and push | Existing status/consent/lifecycle code retained, not presented as new verified capabilities | Real two-device calls, route/interruption/audio/reconnect, room mic consent/revoke and foreground/background push/logout-switch checks. |
| English/Nepali and readable states | Prepared fixed-label and whole-template translations; existing successful/empty/error/loading screens retained | Actual final-tree renders, large-text review and native Nepali wording review. Coverage is not translation quality. |
| Product depth | Real current journeys only, no invented community activity or decorative roadmap promises | Original full-product acceptance remains open. Nepal/health expansion is not inferred from old notes. |

## Validation and distribution policy

The local emulator API uses throwaway SQLite data and a throwaway signing key. The second fixture server alone enables upload receipts and loses one response after saving, to exercise retry without duplicates. No production identity, media, B2 or account is involved. Fixture endpoints and token defines must not appear in a production-endpoint artifact.

CI keeps API/parity/concurrency, whole Flutter tests, actual widget renders, Android compilation, unsigned iOS compilation and emulator integration separate. Every result belongs to its exact head; a skip is not a pass. Production-endpoint APK/AAB outputs are engineering artifacts until stable-key verification and an unused version code have been checked through their owning sources. No new version code is selected here. The current 2010 artifacts must not be sent as upgrades.

No tag, release, Play upload, download-link change, email delivery or phone installation is part of preparation. Preserve the installed app and data. Never uninstall or wipe to bypass update identity. Final stable-key candidate Samsung acceptance is a required shipment gate, not replaced by unit tests, screenshots, an emulator or unsigned iOS compilation. Main coordinates a phone request at an appropriate user moment; this lane does not poll the phone.

The last-verified live API and immediate rollback remain `298587...eb66` and `b384617...4f19`. This document does not establish their present state after its write time and does not authorize any deployment. No further boot/provider/FPM/persistence tuning is supported by the local profiling evidence.

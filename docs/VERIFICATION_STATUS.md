# Verification status

Updated November 17, 2026. This is a test record, not a claim that the full app is finished.

## Published preview

Android 0.5.1+6 was built from `51c1c73`, signed with the stable upload key, and published as a test prerelease:
https://github.com/MaisySen/sanjaal/releases/tag/v0.5.1

CI run: https://github.com/MaisySen/sanjaal/actions/runs/43887613498
All four jobs passed: API, app, unsigned iOS build, emulator. The emulator uses a local fixture API and synthetic member, not the production API or a Samsung phone. Its actual flows test passed composing a post and sending a chat message. Earlier finder failures were fixed; they are not still outstanding.

| Flow | Current evidence | Still unverified |
| --- | --- | --- |
| Launch, signed-in feed, profile, like, rooms list, wallet | Fixture emulator checks pass in the CI run above | Physical phone behavior |
| Compose and publish post, start chat and send | Fixture emulator interaction checks pass, screenshots inspected | Production writes and physical phone behavior |
| Small-phone Create sheet | 320x640 widget regression opens sheet, selects Reel and reaches Continue without overflow | Physical phone behavior |
| Real Auth0 email/password sign-in | Real Auth0 password grant returned 200 for the existing synthetic QA identity; the app's actual Session.login client also passed a read-only live test | On-phone entry and native social-login callback |
| Live signed-in reads | Actual Session client passed profile, posts, saved, conversations, withdrawals, rooms, and wallet checks against the deployed API; cashout remains unavailable | Production posting, chat, media, audio, push and multi-device behavior |
| Persistent login / refresh | Root cause confirmed: API Allow Offline Access is off in Auth0; no refresh token issued | End-to-end refresh issuance, device secure storage and restore |
| Secure refresh persistence | Candidate source migrates preferences to Keystore-backed storage / Keychain, clears old copies, excludes Android backup, and prevents a new login inheriting another account's refresh token; targeted tests pass | Candidate build/device verification; not in published 0.5.1 |
| Calls and live rooms | Client and server code exists; prior synthetic transport checks are not app/device evidence | App audio/video, permissions, backgrounding and two-device calls |
| Push delivery | Client registration and server sender code exists | Real delivery and production credential/configuration readiness |
| Wallet / cash-out | Signed-in balance/history/withdrawal reads return 200; cash-out unavailable; deployed payout provider remains DisabledPayout | Top-up and payout provider integration, approval and payment testing |
| iOS | CI unsigned build passes | Signed install, real-device behavior and distribution |
| TeamViewer / Samsung | Separate physical-device verification work | No genuine Samsung test claimed here |

## Safe live verification

`app/test/live_api_test.dart` is explicitly opt-in via `SANJAAL_QA_LOGIN_FILE`, a private existing-QA credential file. Its HTTP client permits only the Auth0 token POST and API GETs. It does not create identities, publish posts, send messages or move money. Never commit the private credential file or token responses. A skipped live test in normal CI is not live evidence.

Auth0 settings were read at the API's settings page. Offline access was not enabled during these checks. In particular, published 0.5.1 still stores any refresh token it receives in ordinary preferences, so the hardened replacement needs verification before enabling persistent sessions.

## API deployment

The live image remains `sanjaalapp/sanjaal-api:v31-7e2e68c`, not the latest branch head. Source changes after that commit are not deployed merely because repository CI passes. The newer payout retry hardening is locally tested, including PostgreSQL 18 concurrency checks, but is not live. Payouts remain disabled.

## Secure-storage candidate checks

Local split suite: 167 passed, 1 live test skipped without credentials (51 non-render tests, 56 light renders, 56 dark renders, 4 other renders). The opt-in actual-Session live test passed separately. Analyzer reports no errors or warnings; remaining diagnostics are informational. Candidate is 0.5.2+7, not yet published or device-tested. Plugin source: https://pub.dev/packages/flutter_secure_storage (11.2.0); uses default platform secure storage without requiring biometric enrollment.

## Connected first-use source batch

The next working source batch changes first-run/account routing, direct empty-state actions, profile hierarchy and post-publish return behavior. It preserves the requested floating glass navigation and reduces independent photo-action capsules. This is not a new released APK or a claim that the full product-quality correction is complete.

- Prior secure-storage/font source `562ac4a` passed all four CI jobs, including actual Android emulator signed-in checks with the secure-store migration, new-session restore and logout assertions. The emulator still uses a local fixture API, not Auth0 or a Samsung phone.
- Local current source passed all 116 light/dark render tests, 57 other tests before two additional regressions, and the final 8-test first-use regression set. The full current suite is run again in CI; do not add overlapping test counts together.
- The new first-use test initially found English 1.8x overflow at 320x640; the wordmark constraint was fixed and the test rerun successfully. Actual pixels were inspected after loading real test fonts, not inferred from test success.
- First-use tests cover English/Nepali at 320x640, normal/1.8x text with a reachable account action; actual app welcome-to-registration-to-sign-in routing; empty-state vs load-error actions; refresh queuing during an in-flight fetch; and profile list/count reload after a publish revision.
- The emulator publish flow now requires the post to appear after returning from Compose without a manual pull-to-refresh. Its next CI result is pending, not inherited from the previous source.

## Connected communication source batch

The next batch makes Calls and Live rooms visible in Chats, adds an actionable empty inbox and proper load-error retries, preserves list space above the floating navigation, and ignores stale inbox responses when switching to Archived. A room needs a valid title before Start; duplicate start requests are blocked. Call history refreshes after returning from a call.

The audit found a real call-state bug: incoming Accept/Decline previously swallowed server failure and still entered the call or dismissed its ring. The candidate now stays on the ring screen with a retryable error, disables both actions during a request, and only changes screens after the server accepts the action. Caller/error content scrolls separately from fixed accept/decline controls on small screens.

Current local source: 204 tests passed, 1 opt-in live test skipped (70 non-render, 67 light, 67 dark). The 11 new communication tests use a mock API, not real media: direct chat creation and Calls/Rooms navigation, three load-error retries, archive-response ordering, room-title validation/cancel with no POST, outgoing call avatar identity, and failed incoming accept/decline with duplicate suppression and retry. Small 320x640/1.8x incoming-error and empty-inbox pixels, normal Chats, and rooms error pixels were inspected. New emulator/CI evidence remains pending. No actual calls, room creation, message sends, provider changes, or new APK release happened in this batch. Native Nepali copy still needs review.


## Call lifecycle source follow-up

A source audit found that a delayed token/connect response could continue opening microphone/camera after the call screen had been left. The setup runner now rechecks ownership after each asynchronous step, ends the server call when a late token arrives after leaving, and stops capture before disposing the room. Native disposal waits for outstanding setup/media work and disconnects again before final release. A setup or permission failure also disconnects and attempts to end the call instead of leaving an unseen ringing session. Server end is best effort, not a network-guaranteed delivery claim.

Media buttons remain disabled while connecting or applying a change; state changes only after native success, with errors shown instead of optimistic state. Incoming-call polling now reserves its in-flight guard before the network await, preventing overlapping slow polls and competing rings.

The current split suite passed 219 tests, with one opt-in live test skipped (85 non-render, 67 light, 67 dark). This includes 13 setup-ordering tests with fake native callbacks, an actual HomeShell slow-poll regression, and media-control disabled-state behavior. These tests do not invoke real microphones/cameras or establish native teardown behavior on a device. The communication batch still needs new CI and physical audio/background/reconnect verification.

First-use commit `1d87c01` passed all four CI jobs: https://github.com/MaisySen/sanjaal/actions/runs/43899037326 . Actual emulator job 133410327171 logs show the three test groups passing in 13, 33 and 49 seconds. Its flows source requires post visibility after publish without manual pull-to-refresh. The API remains a local fixture, not production or Samsung evidence. Communication commit `adaa02b` has its own run: https://github.com/MaisySen/sanjaal/actions/runs/43901274977 .

Final visual follow-up: a new pixel check of the light-theme video call caught black header text/back navigation against the call's black surface. Explicit white text and a white BackButton style fix it. Rerendered the call fixtures, checked the updated light video pixels, and reran the 13 communication tests plus four call layout tests; title-color regression added. The 219-test split above predates only this contrast follow-up; latest full CI remains the integrated check.

## Startup, active tabs and creator return

An actual HomeShell widget request trace with a mock API originally made nine GETs at startup, including unvisited Reels, Chats, Wallet, withdrawals and own profile/posts. Lazy mounting now requests only Home posts, stories and unread summary (three GETs), preserving each destination after its first visit. This is a measured reduction in fixture request count, not a claim of faster physical startup or free-tier capacity. Unvisited and hidden tab tickers are disabled. A visited Chats tab stops its periodic reads while hidden and refreshes when revisited. Shell notification/call polls stop while backgrounded; Reels receives active=false to pause its existing player on background. Native media behavior is still unverified.

The creator journey now refreshes Reels after publishing, queues a refresh that arrives during an existing request, resets its page index on refresh, and refreshes story rings after a story is posted through Create. Stale story reads cannot replace a newer revision. Empty Reels offers Create a reel directly, while a failed load offers retry. Its empty/error surface follows the app theme instead of using dark text on black in the light theme.

The new actual-shell Reels fixture render caught captions and the sound control hidden under the floating glass navigation. The content/action/progress inset now leaves those above the bar without removing or replacing it. The 320x640, 1.8x text render asserts caption and Sound bounds above the bar, and actual pixels were inspected. Reel Follow controls have 48px minimum height. These are failed-video fixture frames, not successful video playback evidence.

Current local split: 238 tests passed, 1 opt-in live skip (94 non-render, 72 light, 72 dark); analyzer no errors or warnings, 20 informational diagnostics. Nine new tab/creator tests cover the exact startup read budget, first-visit loading/state retention, hidden/background polling, in-flight Reel refresh, stale story ordering, empty/error Reels, and actual HomeShell post-Reel/story return with fake picks and mock uploads. No production write or native picker/media proof. Direct dependency declaration now includes the picker interface already used by fixture tests, with no resolved version change.

## Covered-route and background media ownership

Reels and feed videos now observe tab visibility, app lifecycle and the shared navigator. A pushed profile/call page or modal sheet pauses the covered video; reels may resume when visible again, while a manually started feed video stays paused until tapped. Story video and its timer pause together under another route/background and during long press. A story initialization finishing after exit cannot start playback or install a new timer. Story action dialogs now use the same pause path.

Ten new tests drive the real video widgets/controllers against a fake video platform: route cover/return for Reel and Feed, hidden-tab pause for both, delayed Reel initialization under a cover, background/resume, story cover/background timer behavior, story hold/release, modal sheet pause/resume, and delayed story initialization after exit. These verify app-to-plugin calls and timer ownership, not native codec/audio, real speakers, OS interruption policy or physical teardown. They do not prove production media loads.

Current local split: 248 passed, 1 opt-in live skip (104 non-render, 72 light, 72 dark). Analyzer still has no errors or warnings. The full light/dark fixtures were rerun and the change introduces no new visual design. Prior contrast commit `f3cfb24` is all-four-jobs green: https://github.com/MaisySen/sanjaal/actions/runs/43902962790 . Startup/creator commit `0899321` has a separate run: https://github.com/MaisySen/sanjaal/actions/runs/43906142437 and was still in progress at this record.

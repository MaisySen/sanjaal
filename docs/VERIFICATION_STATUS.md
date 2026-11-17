# Verification status

Updated November 17, 2026. This is a test record, not a claim that the full app is finished.

## Current checkpoint: November 17, 20:42 AEDT

This section supersedes conflicting status statements in the historical checkpoints below. A successful source check is not a deployment, an installed build or device acceptance.

- Exact source `68aec83024c80f8d0951a03b79cd6112c4f40074`, Android **0.5.5 (2010)**, was privately installed over the previous app on the Samsung without uninstalling or wiping. About was visually checked. This was not a Play Store update.
- Actual Samsung recordings cover the five tabs and searchable top-left Settings; successful synthetic photo, Only me story and reel uploads; a small persistent upload bar; Wallet usable during upload; new profile counts without manual refresh; and Home position retained through tab navigation. Story upload/viewing are separate clips. The new reel later appeared in the main Reels list after deliberate refresh.
- Open findings: sign-in was required after the update, cause unknown; slow story/original loading; captionless reel profile tile lacks a poster. The static five-second QA reel does not establish motion/audio playback. Failure/retry, background/process death, room/call audio, push delivery and Play flexible-update proof remain open.
- The Samsung remote connection stopped updating and then explicitly reported unavailable. Device work is paused. A stale remote frame is not an app failure and must not be used to prove current state.
- Startup source `bb88ff5ddfe6757a305d08d8094815abaff3c601` separates a retryable restore error from sign-out. Storage, transport, service or account-read failures preserve the saved grant; only an explicit refresh `invalid_grant` rejection removes it. A complete local 51-file Flutter sweep passed 843 tests with one opt-in live skip. This fixes a proven error-handling flaw, not the confirmed cause of the Samsung sign-in observation.
- Poster source `e70b84c1d8a4a42faf6f3ca4b24a6cbb27c8ab78` adds bounded local native first-frame extraction, a capability-gated immutable upload poster, validation/metadata removal, transaction/replay binding and lifecycle/access checks. Legacy videos have a visible play fallback, not a fabricated thumbnail. Local API: 154 passed, one PostgreSQL-only skip; focused Flutter regression groups: 106 and 181 passed. These groups overlap earlier suites and must not be added to their totals. Native emulator assertions were added, not yet accepted.
- Current CI for that exact poster/startup source: https://github.com/MaisySen/sanjaal/actions/runs/44055078702 . At 20:42 all five jobs passed: API, app, unsigned Android bundle, unsigned iOS and actual emulator. Release was skipped. Downloaded emulator logs show all four groups passing; the native-media test requires actual camera first-frame extraction, byte decoding, poster upload/read/delete against its throwaway local API. These are emulator results, not Samsung acceptance. Actual artifact inspection found that the OS notification permission dialog covers later frames in the recording and the Flutter-only story screenshot is black at capture. The decoder/HTTP assertions passed, but visual acceptance of that journey is withheld. A follow-up grants notification permission only in the throwaway emulator setup and adds full-Android-screen poster/story captures after decoded image presentation; its new CI is pending.
- New startup and poster source is not installed on the Samsung. No new stable-key candidate finalization, API deployment, Play upload or release was performed for these changes. Wallet remains unavailable until live money paths are independently verified.

Source: https://github.com/MaisySen/sanjaal/commit/e70b84c1d8a4a42faf6f3ca4b24a6cbb27c8ab78

## Historical checkpoints

The sections below preserve what was checked at the time. Their older versions, counts, deployment labels and open gaps are not a current-state inventory.

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

The last verified deployment is the isolated media-security image `sanjaalapp/sanjaal-api:v35-media-0f805e8`, not the recovered product branch head. Earlier v31 references below are historical checkpoints. The isolation patch preserves authenticated chat/range reads and requires a current positive public reference for anonymous media. It is not a broad product deployment. The health endpoint returned 200 on November 17 at 08:24 AEDT; that alone does not identify the image or prove feature readiness. Candidate chat replay, upload receipts, polls and subsequent client work must not be described as deployed. Payouts remain disabled.

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

## Poll source checkpoint

Single-choice polls now have composition, aggregate result display, idempotent choice replacement/removal, authenticated/blocked/deleted-post checks, and one aggregate query per feed page. The client exposes creation only when `/auth/me` explicitly advertises `features.polls`, so the older deployed API does not show an unusable composer. No migration or new API was deployed. No APK was released for this checkpoint.

Local evidence: API suite 89 tests / 686 assertions, repeated with cached routes; PostgreSQL 18.7 throwaway database parallel same-member voting and voting/deletion tests 2 tests / 5 assertions. Flutter split suite: 90 non-render tests, 23 render-file behavior tests, 73 light and 73 dark renders = 259 passed, one opt-in live test skipped. Analyzer has no errors or warnings, 22 info notices. Actual light/dark 320x640, 1.8x poll and composer pixels inspected. Composer scrolls when content exceeds the viewport; keyboard/physical-phone interaction remains unverified. Counts are confirmed responses, not optimistic guesses. No voter names are exposed by the API; backend administrators still have database access, so this is not cryptographic anonymity.

The initial local API failure was an incorrectly selected PHP binary without GD plus missing CI test key, not a passing regression waiver. Re-running with the GD-enabled test binary and the existing non-production CI test key passed the entire suite.

### Poll composer reachability follow-up

At 1.8x text on a 320x640 viewport the original Remove poll action was partly offscreen above an irrelevant disabled media toolbar. Poll mode now replaces that toolbar with one pinned Remove poll action. A new widget regression applies a simulated 240px keyboard inset, scrolls to and edits Option 2, verifies Remove poll is fully above the keyboard boundary and hit-testable, and removes it while focused without controller errors. All six poll widget tests pass. Updated light/dark pixels were inspected. A new actual-emulator flow asserts a nonzero native IME inset, captures the state, then publishes/votes/removes a vote against the fixture API. That new native flow is pending CI execution, not yet proof.

## Private-media isolation containment

An isolated security branch based on the prior production source scopes B2 public download tokens to the exact generated object UUID, limits new tokens to one hour, and keeps new chat attachments on the existing authenticated database-media path. This is intentional containment for previously issued broad download tokens, not a claim that those tokens were revoked. The isolated production-runtime suite passed 86 tests / 625 assertions with cached routes. A follow-up maintenance-command safeguard permits only positively identified public media to move to B2 and excludes private or unclassified uploads; its isolated suite passes 87 / 632. No schema migration is involved. Do not restore the previous private-upload-to-shared-bucket behavior in a rollback. Moving private files to separate storage and free-tier quota controls remains a product-readiness item.

## Blocking boundary audit

Source fixes now apply the same block policy to remembered direct post/comment/reaction/gift URLs, new follows, direct messages/call-token requests and new groups. Hidden comments/replies and notification actors are filtered; comments on deleted posts no longer create notification entries. Historical direct-chat access is not destroyed by a block. Existing shared-group interaction policy is not claimed fully audited. Local source API suite passes 93 tests / 749 assertions, including the new boundary regressions, repeated with cached routes on the exact production PHP runtime. These broader source changes are not part of the isolated live media image.

### Deployed isolated media safeguard

The live API now runs `sanjaalapp/sanjaal-api:v34-media-f47350b`, manifest `sha256:ffd7f4af418133adf447e3a6985579bec5c8691f3037be1476cc098f6d0dbd65`. Deploy succeeded with no migrations; actual dashboard pixels/logs were inspected and health/ping returned 200.

https://dashboard.render.com/web/srv-dbs73e67bikc73epiodg/deploys/dep-dbtjbiu1egvs73b47as0?r=live

This image is the old production source plus only the three media-safety files, not the whole recovered branch or polls. On the preceding containment image, live public-object HEAD checks showed a new token worked for its own object (200), failed for another public object (401), and carried a one-hour timestamp interval. An old token still worked on its original public object, so revocation was not claimed. No private file bytes were queried. Keep the database-only private path in any rollback. The immediately previous v33 containment image is a safer rollback than the older v31 image.

### Native poll IME gate result

`fe6111a` API, app and unsigned iOS jobs passed, but the new emulator poll gate failed because the actual platform inset stayed zero. Its failure screenshot was inspected and contains no native keyboard. This is not native-keyboard proof. Smoke and signed-in groups passed. The nonzero-inset assertion remains; source `66129e7` explicitly requests the IME and waits on platform geometry rather than assuming synthetic text entry opened it. That revised gate is pending: https://github.com/MaisySen/sanjaal/actions/runs/43913465904 . No new APK is released.

Earlier `8f8c6dd` API/app/emulator passed but iOS was cancelled, not a code-test failure and not an all-green run. Its URL remains https://github.com/MaisySen/sanjaal/actions/runs/43907420534 .


## November 17, discovery and room-boundary candidate (not deployed)

- Room discovery, direct room join and room gifts now respect host/member blocking in either direction. This does not revoke already issued room tokens or prove shared-room participant isolation.
- Search invalidates pending responses as soon as its query changes or clears; failed searches retry without retyping. Notification post events and shared-post cards now resolve the current post instead of opening the actor/author profile. Deleted/hidden posts show an unavailable state; network failures offer retry.
- Local PostgreSQL 18 suite: 95 tests/764 assertions, both normal and route/event-cached. Eight local concurrent invariant checks pass with 49 assertions, including explicit local throwaway database guards. Test-only PDO persistence is disabled because independent test app instances otherwise share a connection and can collide at migration setup. Runtime persistence is unchanged. The CI candidate now pins a PostgreSQL 18 throwaway service and runs these checks.
- Local non-render Flutter checks: 94 passed, 1 deliberately skipped live test. Discovery checks: 7 of those tests. Eight focused light/dark fixture renders cover post detail/unavailable and search retry, including 320x640 at 1.8x text. Actual pixels were reviewed; these are fixture layout evidence, not a native keyboard or physical-device result.
- CI 43913465904 (66129e7): API/app/unsigned iOS passed; emulator failed with platform inset 0.0 at the preserved native keyboard assertion. Gboard was the enabled default and hardware-keyboard IME display was enabled. Explicit TextInput.show did not settle the gate. No APK release follows from that run.
- Next emulator candidate uses a native Android pointer at the actual Option 2 coordinates through a token-checked, opt-in, CI-only fixture router. It preserves the nonzero inset, focused Option 2 and fully visible/hit-testable Remove poll checks, rejects registered mock text input, and captures full native display/input-method diagnostics. It has not passed until the actual run says so. No production route or native app backdoor is added.


## November 17, 04:26 AEDT isolated media lifecycle deployment

An additional synthetic regression reproduced anonymous access to an orphaned private attachment after the final group member left and message references were deleted. Isolated commit 0f805e8 now requires positive current public-post/avatar/active-story ownership before anonymous media requests, including conditional requests. Authenticated chat serving, private DB-only uploads, object-scoped B2 tokens and migration safeguards remain intact. No blob deletion or schema change. Production-runtime tests pass 90/648 both normal and cached. Recovered cherry-pick bdba15b passes 98/780 locally.

Image sanjaalapp/sanjaal-api:v35-media-0f805e8, manifest sha256:42304754663e3af8ea2c4193495beed58bcc6f7f26ae96f3cfa0805f4876ddfd. Render deployment succeeded20.7s, nothing to migrate: https://dashboard.render.com/web/srv-dbs73e67bikc73epiodg/deploys/dep-dbtjp66i0phs73dil13g?r=live . Dashboard pixels/logs inspected. Current /up and ping200, public DB media HEAD200 and B2 media HEAD302. These are health/public-route checks, not a private live-upload mutation proof. Current read-only metadata at04:24 showed zero attachment messages, nine B2/four DB blobs, zero private-referenced or nonpublic-unreferenced blobs. No private bytes read and no access evidence found. Existing broad B2 tokens are still not claimed revoked. Do not rollback below v35 without restoring this lifecycle safeguard.

Full local Flutter0986e70 candidate regression completed in separate bounded runs:94 non-render,177 render_screens and4 base render checks passed, one intentional live-test skip. Total275 passed/1 skipped. Native-IME CI43916543448 remains separate and pending.

### Connected photo gallery candidate

One swipeable multi-photo treatment replaces the fixed-count immersive cover and disconnected detail tiles. Full-screen starts at the selected image, supports page/zoom and explicit close, and retains per-request authorization for single private-photo callers. Error/retry, position and current-post bindings are covered by 13 new offline tests; Home/detail and viewer fixture pixels were reviewed at 320x640 and 1.8x text, light/dark. Full non-render Flutter suite: 107 passed, one intentional live-test skip. Analyzer: 22 info notices, zero errors/warnings. Device gestures, codec behavior and live downloads remain unverified. No release/deployment claim.

### Recovery continuity and native surface follow-up

Notification refresh errors now retain current items with retry; empty lists can refresh; concurrent refresh reads are guarded. Failed share destinations can reload in place without sending. Four additional offline recovery tests pass, with 320x640/1.8x fixture pixels reviewed. Latest complete local Flutter batches: 111 non-render + 177 screen renders + 4 base renders = 292 passed, one intentional live-test skip. Analyzer: 22 info notices, no errors/warnings.

CI43927332530: API/app/unsigned-iOS jobs passed. Emulator failed the preserved real-IME inset assertion: Option2 was actually focused, but keyboard visibility was false and inset zero. Next diagnostic runs the same native gate before screenshot conversion ever changes the Android surface. This is not keyboard proof or a release approval. Live API remains the isolated v35 security correction; no new APK was published.

### Story review and draft safety candidate

Picking a story opens review rather than uploading. Photo/local-video preview, optional caption and explicit Share story use the existing API. Selection/caption remain after an error. Post/reel/story route-back asks before discarding a draft; active uploads remain on screen; empty post exit stays immediate. Video preview waits for Play and pauses under another route/background. Nine creator tests and two fake-video-platform tests added; camera and shell story journeys now verify the explicit-share step. Actual 320x640/1.8x English/Nepali light/dark fixtures inspected. This is not device/video-codec or live-upload evidence. Draft storage is in-memory only.

Latest full local batches: 122 non-render + 177 screen-render + 4 base-render = 303 passed, one intentional live-test skip. Analyzer has no errors or warnings. Fresh CI10cb345 exposed missing mkdir calls in new screenshot helpers, now fixed and verified after moving all old renders aside. That CI's API and unsigned iOS passed; app failed the helper setup; emulator again failed the unchanged native inset gate. Native logs report FlutterView not served even before screenshot conversion. No keyboard pass, APK publication or live API change.

Upload retries remain incomplete against response-loss-after-commit: story/post endpoints have no per-draft server idempotency key. A retry in that case may duplicate content. Do not treat retained-draft UI as a guarantee of exactly-once publication.

### Replay-safe upload candidate

The gap recorded above is now implemented in source, with rollout OFF by default. `UPLOAD_INTENTS_ENABLED` gates capability and keyed requests. Resource/receipt/DB bytes commit together; unchanged replay returns the current original; changed payload returns conflict; deleted/expired original returns gone. Receipt migration refuses to erase populated tombstones. Client preserves one intent per draft, warns on old-API unknown outcomes and asks before preparing a distinct upload. No automatic resend or duplicate-safety claim for unkeyed legacy uploads. DB staging capacity/retention review is required before activation. See [UPLOAD_RETRY_PROTOCOL.md](UPLOAD_RETRY_PROTOCOL.md).

API local:107/855 SQLite and PostgreSQL normal/cached. Real PostgreSQL races:10/66, including concurrent keyed file replay/conflict. Flutter:138 non-render +177 screen renders +4 base renders =319 passed, one intentional live-test skip. Analyzer20info/noerrorswarnings. Source-only; production upload/physical network loss/native IME/Samsung/performance remain unproven. No broad API deploy or APK release.

## November 17 comments recovery candidate

- API: 109 tests / 880 assertions on normal and route/event-cached SQLite and PostgreSQL 18.
- Real local PostgreSQL concurrency: 12 tests / 81 assertions, including parallel reply/thread deletion and four-way repeat deletion. Throwaway localhost database only.
- Flutter: 164 non-render tests (including 26 comments fixtures), 177 screen-render tests, 4 base-render tests. 345 passed; one intentional live-test skip. The broad suite was run in separate complete batches after a combined process exceeded its command time budget. Analyzer: 19 information notices, no errors or warnings.
- Comments reply and ambiguous-outcome fixtures inspected at 320x640, 1.8x, light/dark, English/Nepali, with simulated keyboard space. Not device or native-IME evidence.
- CI5af6f73 settled at https://github.com/MaisySen/sanjaal/actions/runs/43940599271 : API, Flutter/release-APK build and unsigned iOS passed; emulator failed the preserved poll native-IME assertion; release skipped. Actual native screenshot shows Option 2 focused without a visible keyboard; test/platform insets were both 0 with mocked=false. No full-pass claim, new APK publication or speculative keyboard-harness change.
- Live v35 media isolation unchanged. Upload receipt rollout still defaults OFF. Comments have no exactly-once protocol; ambiguous sends require review rather than blind retry.

## November 17 profile continuity candidate

- 31 focused profile tests: retry/read ordering, follow reconciliation without a repeated mutation, pending and rejected saves, unchanged/changed draft exit, controller/picker disposal, immediate-photo versus unsaved-text state, invalid-form no-send and English/Nepali light/dark/large-text layouts.
- Complete local Flutter: 195 non-render +177 screen-render +4 base-render =376 passed; one intentional live-test skip. Analyzer20info, zero errors/warnings. API unchanged from109/880 and12 real local PostgreSQL concurrency tests/81assertions.
- Actual profile retry/edit/member/own PNGs inspected, including simulated keyboard space. The simulated space is not a native keyboard result.
- CI12cb11d https://github.com/MaisySen/sanjaal/actions/runs/43943507650 : API/app/unsigned iOS pass; emulator fails only native poll inset (test/platform0,mocked=false), release skipped. Native screenshot inspected: Option2 focused, no visible keyboard. Monitor removed after settlement.
- No production changes. Livev35 media isolation, disabled payouts and upload-intent rolloutOFF preserved. No new APK publication or physical Samsung/iPhone claim.

## November 17 chat recovery candidate

- API115tests/919assertions, SQLite and PostgreSQL18 normal/cached. Six focused message tests cover immutable replay/reply, sender+conversation key scope, soft deletion/rejoin history, rollback after bytes insert, no extra replay blob, and final-leave DB cleanup with legacy B2 isolation/no remote calls.
- Real local PostgreSQL races14/97: four-way text/media same-key requests and final-group-leave/send included. Not live service/load evidence.
- Flutter211non-render+177screen-render+4base-render=392passed, one intentional live-test skip;16 focused chat tests. Analyzer21info/noerrorswarnings.
- Actual320x640/1.8x English/Nepali light/dark chat retry pixels inspected; low-contrast status corrected. Simulated keyboard space only.
- Profile CIcb792b6 https://github.com/MaisySen/sanjaal/actions/runs/43947579638 passed API/app/unsigned iOS, failed only unchanged native poll IME0inset/mocked=false; release skipped. Native screenshot inspected and monitor deleted. No APK publication or live API mutation.
- Existing private DB media isolation and positive current public-reference rule preserved. Final-leave cleanup only deletes DB blobs belonging to that conversation; legacy B2 deletion remains separate. Upload receipt rolloutOFF and payouts disabled.
- Remaining chat gaps: durable outbox/drafts, failed media selection retention/retry, before-sequence history paging in the client, foreground/background network recovery and real device delivery.

## November 17 chat history candidate

- Client now requests earlier history explicitly, preserving the cursor/draft on error, deduping IDs, preventing overlapping pages and leaving join-time authorization to the existing API. Stable center slivers preserve reading position across variable-height prepends and concurrent incoming polls. Bottom following and an explicit New messages jump are separate from reading older content.
- Fourteen history fixtures, including two consecutive prepends, initial-send/read race, same-cursor retry, duplicate IDs, disposal and send-completion scroll preservation. API history regression verifies three exclusive sorted pages, no repeated IDs, empty end, join boundary and leave denial.
- Full split local Flutter:30chat/history+80other+115journey+181render=406passed, one intentional live-test skip. A render command exceeded its time budget; complete rerun passed181/181. Analyzer21info/no errors or warnings. API116/940, SQLite and PostgreSQL18 normal/cached;14actual local PostgreSQL races/97assertions.
- Actual English/Nepali light/dark history retry fixtures inspected at320x640/1.8x. Single-line placeholder fixes excessive large-text composer height; editor still grows to four lines for actual input. Synthetic fixture evidence, not native keyboard/device/live-network proof.
- Prior chat40581ce CI https://github.com/MaisySen/sanjaal/actions/runs/43950233474 settled: API/app/unsigned iOS passed, emulator failed only the preserved native poll IME gate, release skipped. Actual native display inspected: Option2 focused without keyboard, test/platform insets0, mocked=false. No harness weakening.
- The earlier before-sequence client gap is addressed in source. Durable outbox/drafts, failed-media retry, background recovery and actual two-device delivery are still incomplete. Live isolatedv35, upload-intent rolloutOFF and disabled payouts remain unchanged. No new APK release.

## November 17 chat media continuity candidate

- Photo/voice uploads retain one private in-memory retry copy with immutable original bytes/clientID/reply and a visible pending/failed bubble. Explicit retry never overwrites a newer text composer/reply. Poll acknowledgement is sender-scoped; late response loss cannot downgrade confirmation. No new endpoint or automatic resend.
- One unconfirmed attachment per screen bounds retention. Explicit removal/leave wording distinguishes losing local retry bytes from deleting a potentially delivered message. Pending uploads guard accidental back. Forced picker/upload disposal is safe. No persistent outbox or across-route/process recovery added.
-18new fixtures. Voice transport uses synthetic bytes injected at the recorder callback; actual microphone permission, capture, codecs and playback are not tested by that fixture. Multipart photo checks compare original/retry payload after removing only the transport boundary. API unchanged, source replay hardening remains undeployed.
- Complete local split Flutter:128non-render+115journey+181render=424passed, one intentional live skip. Analyzer21info/no errors or warnings. API116/940,14localPG races97 remains the latest checked API state.
- Actual EN/NE light/dark320x640/1.8x media-retry and leave-confirmation PNGs inspected. Long leave wording was shortened; shared snackbar text now preserves theme fonts/fallback instead of dropping them. These are fixture checks, not native keyboard or real-device evidence.
- History CI43954312948 was still running at08:03: API/appbuild passed, unsignediOS/emulator still pending. No new APK release or live API change. v35 security isolation, disabled payouts, upload rolloutOFF and physical/native gates remain intact.

## November 17 voice playback candidate

- Actual playback widget guards private download/native preparation completions against disposal, source changes, background and covered routes before resuming. Visibility loss pauses without automatic restart. Loading prevents duplicate taps. Pause/Play reuses the current source/position. Own-bubble controls/progress inherit the correct foreground ink.
-15new synthetic tests with fake decoder/speaker, not physical sound, codec or network evidence. Four own/received EN/NE light/dark320x640/1.8x PNGs inspected. Local full splitFlutter143non-render+115journey+181render=439passed/1intentional live skip;analyzer21info/noerrorswarnings. API unchanged116/940+14localPGraces97.
- History73a69daCI https://github.com/MaisySen/sanjaal/actions/runs/43954312948 settled:API/appAPK-build/unsignediOSpassed;emulatorpollnativeIMEfailed/release skipped. Actual native display inspected with Option2focus/no visible keyboard. No nativepass/APKpublication/deployment. Media c845a94CI43956201092 remained running at08:09 withAPIpassed.
- Recording lifecycle, durable drafts/outbox and actual two-device/audio delivery remain open. Livev35isolation/uploadOFF/disabledpayouts unchanged.

## November 17 voice capture candidate

- Recorder start/finish/shutdown now have one owner across async permission, directory, native start/stop and file reads. Cancellation checks suppress post-exit capture/upload/callbacks. Covered/background/inactive-start cases cancel without auto-start. If permission UI backgrounds the app, recording needs a fresh microphone tap after permission completes.
- Send/discard cannot stack; callbacks notify once. Owned temporary files are deleted on success, error, discard or shutdown. Cleanup waits for in-flight native calls rather than disposing out of order. This cannot guarantee immediate cleanup if a native call itself hangs; actual OS/microphone/codec testing remains open. Existing120second duration-limit behavior preserved.
-21controlled fake-recorder/file fixtures pass. Complete split localFlutter164non-render+115journey+181render=460passed,1intentional live skip;final focused recorder rerun after inactive-start refinement also passed. Analyzer21info/no errors or warnings. Four actual EN/NElightdark320x640/1.8x recording-control PNGs inspected. These are synthetic capture files and fake permission/native callbacks, not device/audio evidence.
- APIunchanged116/940+14localPGraces97. At08:18mediaCI43956201092 API/apppassed,emulatorfailed,iOSpending;playbackCI43957455274 API/iOSpassed,app/emulatorpending. No new APK publication/live deployment. NativeIME remains unresolved, uploadOFF/payoutsdisabled/livev35isolation preserved.


## November 17 whole-product reconciliation, 08:25 AEDT

The user's full-product quality correction is still the acceptance criterion. Bug counts, fixture renders and successful compilation are supporting evidence, not completion. See [PRODUCT_RECONCILIATION.md](PRODUCT_RECONCILIATION.md) for the connected journey review and release path.

- Actual current HomeShell, Chats, Wallet, story review and own-profile fixture pixels were inspected. The requested floating glass bar is present. The generic `me_dark` fixture has an endpoint-fixture error; it is not successful-profile proof. The focused own-profile fixture is valid large-text layout evidence, not live profile data.
- Published release list rechecked: v0.5.1 remains the newest preview. Current recovered source through b9927b7 is not a published app. API ping returned 200/status ok/media b2, not proof of the candidate deployment.
- CI43957455274: API/app/unsigned iOS passed, emulator still running at 08:24. CI43959218322: API passed; other build/native jobs still running. No native pass or new APK claimed.
- Historical tag publication omitted the emulator dependency and would have published ordinary debug-signed APK artifacts. Candidate workflow now depends on all four jobs and is explicitly disabled in source until stable-key signing and final artifact verification are integrated. Do not remove the disabled condition merely because tests pass. No tag or variable was changed by this source correction.
- Durable drafts/outbox, physical input/audio/camera/network/push, two-device calls, iOS signing, remaining Nepal-focused roadmap and cohesive product polish remain open. Upload-intent rollout stays OFF and DisabledPayout stays bound. No broad deployment performed.


## November 17 recorder CI correction

Recorder CI43959218322 failed one widget assertion: delivery was observed before final temporary-file deletion completed. API and unsigned iOS passed; the app test step failed and did not build an APK. Local success had not proved CI success. Playback CI43957455274 settled API/app/unsigned iOS pass, native poll IME failure and release skipped; actual native display again shows Option2 focused with no keyboard.

Candidate correction awaits private-file cleanup before handing bytes to onDone, then rechecks visibility. A new callback-boundary regression requires the directory to be empty inside delivery. The test pumps both fake-zone continuations and actual file I/O until the delivery event, with a bounded timeout, rather than assuming a fixed50ms drain means cleanup completed. Bytes-once, no-cancel and file-deletion assertions remain. This changes no codec/permission/native-IME claim.

Focused40tests passed. Complete local splitFlutter165nonrender+115journey+181render=461passed,1intentional live skip;analyzer21info/noerrorswarnings. A combined command finished all journeys but hit its budget during renders; a complete181render rerun passed. No new APK, production deployment or physical-device result. Whole-product work remains open per PRODUCT_RECONCILIATION.md.


## November 17 new-chat journey candidate

-26focusedfixtures and full local splitFlutter165nonrender+141journey+181render=487passed,1intentional live skip. Analyzer21info/noerrorswarnings. API unchanged116/940+14real localPGraces97.
- Immediate search generations, loading/error/retry separation, immutable pending creation selection, duplicate/back locks, group draft protection and unknown-create-result containment implemented in candidate source. No group replay protocol or durable draft added.
-16small/large-text language/theme/layout cases; actual representative ENlight/NEdark group/error/simulated-keyboard/unknown-result images inspected. Title truncation corrected after the first pixel check. Fixed create action is visible above simulated240dp keyboard space, not native keyboard evidence.
- At08:40 recorder43959218322 settled API/iOSpass, appfailed earlier cleanup fixture and emulatorfailed; corrected-recorder43961436452 APIpassed/otherspending. Reconciliation43960237408 API/apppassed/iOS+emulatorpending. No green corrected CI claim, APK publication or production mutation.
- Livev35mediaisolation,uploadOFF,disabledpayouts and fail-closed tag publication unchanged. Whole-product profile/first-use, nativeinput and genuine device proof remain open.


## November 17 profile hierarchy candidate

Actions now precede real metrics; smaller identity/count headings, responsive metric rows at large text and natural-width member action wrapping avoid fragmented words. Nepali Saved/empty titles added. Four additional normal/large English/Nepali tests check ordering/count retention/metric label space/create-action scroll reachability. Actual pixels inspected, including the corrected large-text case and actual scrolled create-action location. Large-text create is not above-fold. No invented activity or hidden load failure.

Complete local split491passed/1intentional live skip(165nonrender+145journey+181render),analyzer21info/noerrorswarnings;focusedprofile+firstuse43passed. APIunchanged116/940+14localPG97. This is candidate-only, not published APK, physical-device proof or whole-product completion. PRODUCT_RECONCILIATION.md remains the broader acceptance/path record.

## November 17, 09:00 AEDT: first-use form follow-through

Auth form labels, validators, helper text and pending/social notices now follow the selected English/Nepali language. Labels stay visible above fields, helper/errors wrap, and the social label is centered at large text. Explicit show/hide password is disabled while pending and resets hidden on form switch. Inputs use next/done actions and registration advertises new-password autofill. Submission snapshots fields/mode, blocks duplicate callbacks and freezes inputs; unexpected/malformed responses produce a recoverable error while late disposed responses do not mutate UI.

Local result: 165 non-render + 158 journey + 181 render = 504 passed, one intentional live skip. Analyzer: 21 info, no warnings/errors. Thirteen new offline Auth fixtures cover invalid input, pending freeze/double-submit, visibility/autofill, malformed response/disposal, plus English/Nepali light/dark sign-in/register at 320x640, text scale 1.8, simulated 240 inset. Actual `auth_entry_register_ne_dark`, `auth_entry_signin_en_light`, and `auth_top_register_ne_dark` pixels inspected. Scrolled fixture cropping is intentional. These tests do not establish real keyboard behavior, actual credentials, live registration, social callback, secure-store restore, or native Auth0 refresh capability. No provider settings were changed.

New-chat CI https://github.com/MaisySen/sanjaal/actions/runs/43962772907 settled API/app/unsigned iOS pass, emulator fail and release skipped. Actual downloaded `poll_native_display.png` inspected: Option 2 focused/caret visible, no keyboard. The native assertion remains unchanged. Profile run https://github.com/MaisySen/sanjaal/actions/runs/43964527577 remains in progress as of 09:00 (API pass). No APK was published or broad API deployment performed.

## November 17, 09:14 AEDT: Wallet destination follow-through

Wallet balance refresh now commits parsed data atomically with generation ordering. Malformed first loads show retry without inventing a zero. Failed later reads retain the real last balance with a stale notice and disable mutations until refresh succeeds. Secondary cash-out history failure is visible and independently retryable. One operation owns wallet controls across its dialog/network continuation; transfer fields are validated and snapshotted. Ambiguous transfer replies block Send in the current Wallet view and direct the member to Activity, rather than inviting a blind repeat. An explicit 4xx refusal (except 408) permits correction. Dialog controllers live with their route until disposal, forms scroll above the keyboard, and late disposed completions do not update UI.

This is not durable transfer replay: leaving/reopening the view or restarting loses the local uncertain-result lock. The transfer endpoint still has no client replay key. Funding/payout availability remains server-controlled and unchanged; this work executes no real transfer, payment, top-up or withdrawal, and changes no provider binding. Do not claim money readiness. Cash-out's existing retry key remains scoped to the same amount/current view; 408 now keeps it as an uncertain outcome.

English/Nepali wallet labels, availability, history states and helper/error text now match the chosen language. Action layout measures actual translated labels before choosing columns. Large-text history puts the amount below the sender; long numeric balance scales down within its card. Actual normal Nepali light, large Nepali dark overview/history and English/Nepali transfer-dialog pixels were inspected. The first review found untranslated Cash out and clipping of the first floating form label; both were corrected and re-rendered. Scrolled history and dialog crops are not missing-content claims. Simulated 240 inset is not native-keyboard evidence.

Local result: 165 non-render + 184 journey + 181 render = 530 passed, one intentional live skip. Twenty-six new offline Wallet journey checks include malformed/stale/ordered reads, visible history recovery, invalid amounts/no writes, frozen single submission, explicit-vs-unknown transfer outcomes, late disposal, normal/large English/Nepali light/dark, long balances/history, and scroll-reachable dialog fields/actions. Eight existing Wallet render/cash-out checks also pass within those suites. Analyzer: 21 info, no warnings/errors. One combined test command hit its execution limit after the non-render suite; the interrupted journey suite was rerun in isolation and passed fully. Final journeys and render suites were rerun after the last dialog padding correction.

Profile CI https://github.com/MaisySen/sanjaal/actions/runs/43964527577 and Auth CI https://github.com/MaisySen/sanjaal/actions/runs/43965648864 now settled API/app/unsigned iOS pass, emulator fail, release skipped. Both actual downloaded native poll screenshots were inspected: Option 2 focus/caret, no keyboard. Profile job log confirms native inset 0. The actual gate remains unchanged. No new APK, deployment, Auth0 toggle or provider activation.

## November 17, 09:17 AEDT: native input focus investigation

A new lead from Auth run 43965648864's actual Android input dump: `com.google.android.permissioncontroller` kept native focus until 22:10:00.204 UTC, while every app SHOW_SOFT_INPUT attempt failed before focus returned (last at 22:10:00.015). Flutter's synthetic steps had progressed behind the native window. The captured client had an input connection but `mCurPerceptible=false`/`mInputShown=false`. This suggests expected notification permission setup interferes with the gate, not proof of a solved keyboard.

The CI-only, token-guarded native fixture bridge now has an explicit bootstrap operation: capture UI XML/window evidence, grant only POST_NOTIFICATIONS to the fixed throwaway `au.fintex.sanjaal` package, and require actual Android current-window focus on that package before continuing. No generic native dialog is clicked or dismissed. Before/after native window, permission command exit/result, UI XML and screen capture are retained as artifacts. Failure to grant or regain native focus fails setup rather than silently proceeding. The app's production permission flow is unchanged. This is fixture notification setup, not proof of real push delivery or any user's device permission.

The flow invokes this after startup and before synthetic navigation. Existing real native pointer, unregistered mocked-input, field-focus, nonzero native inset and visible Remove poll assertions remain unchanged. No fabricated inset, screenshot conversion workaround or weakened expectation was added. Local validation: PHP syntax pass; fake-adb HTTP contract verifies ready focus, existing bounded tap, input/auth rejection, grant failure and foreign-focus failure; Flutter analyzer 21 info/no warnings/errors. Contract checks exercise a fake adb and cannot prove Android behavior. The next genuine emulator run must decide this hypothesis with the new native evidence.

## November 17, 09:39 AEDT: native gate closed for this fixture; durable member-transfer candidate

Native-focus CI https://github.com/MaisySen/sanjaal/actions/runs/43968600331 settled API/app/unsigned iOS/emulator success, release skipped (still explicitly disabled). Actual pre-setup native XML identifies 'Allow Sanjaal to send you notifications?' in permissioncontroller, with GrantPermissionsActivity holding focus. Expected notification grant exited 0; after-window focus is Sanjaal MainActivity. The genuine adb `poll_native_display.png` visibly contains Gboard, Option 2 focus/caret and Remove poll above the keyboard. Logs report test inset235.0/platform235.0/mocked=false and Flow passed poll. Poll creation/vote continuation also passed and its actual image was inspected. Flutter's converted `flow_poll_native_keyboard.png` omits the OS layer, so it is not the keyboard-pixel evidence. The real native assertions were unchanged. This closes this local-API/synthetic-member emulator input gate, not Samsung, real credentials/Auth0, live API, media/calls/push or signed-release proof. Older Wallet run https://github.com/MaisySen/sanjaal/actions/runs/43968125720 settled API/app/iOS pass, native fail, release skipped with its old unfocused-permission setup.

### Member transfer replay and reconciliation, source only

New permanent `wallet_transfers` receipts are sender/key scoped, fingerprint normalized username/amount/note, and return the original completed receipt on identical retry, even after recipient rename or later balance changes. A changed body with the same key returns409. Ordered participant locks precede receipt creation; the receipt and both ledger sides share a transaction. Missing/invalid keys fail422 rather than use an unsafe legacy transfer fallback. The wallet response advertises transfer replay support for the new client.

The client saves the original account-scoped key/details in secure storage before POST, verifies readback/removal, and restores the original after navigation or a new session. Only immutable-original retry is available until a valid same-key/amount completed receipt arrives. A failed write sends nothing; failed clear retains the pending transfer; corrupt/missing-identity storage fails closed. A competing saved original is not overwritten. Leaving during storage does not send after disposal. Account changes cannot use the previous member's actions. An older API without replay support disables Send with an explicit safety notice, never falls back unkeyed. Review recipient/amount/note and Confirm send precede persistence/network. Explicit rejection can release the key;408/409/malformed/transport/server errors preserve it for original-only reconciliation.

Local verification: SQLite and actual local PostgreSQL full API suites both121pass/973assertions, normal and route/event cached. All16 real local PostgreSQL races pass118assertions, including five-way same-key debit-once, different-key overdraft protection, opposite-direction lock ordering and ledger/balance conservation. Five new API replay tests include rollback on receipt-write failure, payload conflict, sender scoping, new explicit transfer key, renamed recipient and invalid/missing keys. An initial test invocation lacked the fixture app key and another selected a PHP binary without PDO PostgreSQL; these were local harness setup misses, rerun with the established fixture key/PDO binary and throwaway local database. No live database was used.

Flutter final:167non-render +196journey +181render =544passed/one intentional live skip; analyzer21info/no warnings/errors. Wallet has38 offline journey checks; two secure-adapter mock checks. Filled English/Nepali light/dark 320x640/text1.8/simulated240inset journeys enter all fields, review details before any request, confirm, verify the keyed receipt, refresh balance and reach the corresponding -25 activity. Normal UI, reviewed details and final activity pixels were inspected; temporary success snackbar was allowed to leave before final history evidence. Fault fixtures cover persistence failure, failed clear, corrupt pending data, disposal during storage, other-account isolation, reopen/fresh-session original key, unsupported server and canceling review without persistence/request.

### Remaining rollout and product limits

No migration, provider activation, real transfer/payment or broad deployment was performed. Permanent receipts need capacity/retention/backup review; never prune them while delayed retries can arrive. The migration refuses rollback once receipts exist. Old client previews omit the now-required key and would receive422 if this API is deployed; reconcile the API/client rollout and explain this restriction before any release. New clients on old API fail closed for Send. Secure storage tests use fakes: physical-device persistence, restore and interruption behavior remain unverified. Storage loss/wipe or a restored old backup is not proven safe by normal reopen tests. Gifts and cash-out have separate replay/durability requirements and are not covered by member-transfer receipts. DisabledPayout and funding/payout unavailability are unchanged. No new APK was published. Whole-product daily value, native media/two-device proof and legitimate stable-signed production-endpoint distribution remain open.

## November 17, 09:44 AEDT: fail-closed phone preview finalizer, not a published APK

Added `.github/ci/finalize_phone_preview.py` and its11 fake-tool unit contracts. The finalizer requires the selected run and artifact digest/source evidence plus API/app/iOS/emulator completed-success jobs. It checks package/version/ARM64, no debug/backup flag, production API and no fixture/tunnel markers before stable-key signing, then independently checks expected certificate, v2/v3 signature,16KB zip alignment and payload again. It writes a versioned APK, verification JSON and checksum, refuses overwrite, and never publishes or deploys. Decoded key bytes live only in an automatically removed private temporary directory; password arguments use private files. No signing material enters repository code or logs.

Local11unit contracts use fake Android commands and do not establish a real signature. An actual fresh download of old0.5.1 CI artifact was correctly rejected by the new payload check because the old manifest does not explicitly disable backup. Current candidate does disable it. Full successful finalization of the current candidate and its own CI remains pending. The tag publisher remains explicitly disabled; this standalone verified-preview path does not silently reopen it. An old release-note sentence recommending uninstall was removed and replaced with identity/data-preservation guidance, without claiming Android can update incompatible certificates.

Live anonymous ping https://sanjaal-api.onrender.com/api/v1/ping returned200/statusok/mediab2 at09:42. This is health, not signed-in capability or deployment identity proof. CandidateCI https://github.com/MaisySen/sanjaal/actions/runs/43972117639 is still pending; no new APK, live migration or API/provider change.

Finalizer follow-through09:45: sixteen-kilobyte verification now checks every ARM64 native library's actual ELF PT_LOAD alignment/congruence, not only ZIP offsets.13 fake-tool contracts pass, including rejection of4KB-only native segments and non-ELF native payloads. All6 native libraries in the freshly downloaded historical0.5.1 CI APK pass the ELF check; that historical APK still correctly fails the separate backup-disabled condition. This is a real historical library inspection, not verification of the still-pending current APK or a new publication.

## November 17,09:55 AEDT: actual0.5.2 artifact finalized, not yet published

Feature commita9323c7's ownCI https://github.com/MaisySen/sanjaal/actions/runs/43972117639 passed API/app/unsignediOS/emulator, release skipped. Downloaded actual run/jobs/artifact ID14278798643; native pixels show Gboard/Option2/Remove poll and log test/platform235.0/mockedfalse. The exact ARM64 artifact was finalized with the stable existing identity: versionName0.5.2/code2007,41,024,622bytes,SHA2562a510e7015f61a2925a7894ac7e4004d868b8742c2a847e2eb7e9d017fa40a6a. Finalizer verified v2/v3,expectedcertificate,16KBZIP+allnativeELF,package/version/ABI,productionAPI,noQA/tunnelmarkers,backupoff/nondebuggable.

Actual signing found and corrected a password-file consumption issue: apksigner consumes successive lines when store/key point to the same file. A separate0600temporary key-password copy now supplies the existing value, automatically removed with decoded key material. No password or signing identity was changed.13fakeunitcontracts re-pass; the actual APK now passes all final checks. This is not publication or owner-device installation, liveAuth0/storage/calls/push acceptance, or API rollout. Compatibility remains as described above: current live API lacks transfer_replay so the new client disables Send; old previews would receive422 if the new API is later deployed. NoAPI/provider/migration action performed.

Publication09:55AEDT: preview0.5.2 is now available at https://github.com/MaisySen/sanjaal/releases/tag/v0.5.2 with exact sourcea9323c7 and the verified artifact above. Anonymous download of all3publishedassets matched local bytes, including APK41,024,622bytes/SHA2562a510e7015f61a2925a7894ac7e4004d868b8742c2a847e2eb7e9d017fa40a6a. Actual published page read back correctpreview/source/caveats/assets. Direct APK https://github.com/MaisySen/sanjaal/releases/download/v0.5.2/sanjaal-0.5.2-arm64-v8a.apk . Parent has usable links and verificationJSON. No email or owner-device installation was executed by this engineering task. Product/device/live-backend limitations remain, not completion.

### Reference-led integrated candidate, November 17 (not released)

Local verification:169 non-render checks passed with one intentional opt-in live skip;222 journey/upload checks passed. Render verification was split to fit the local runner's time limit:77 light cases passed;95 dark/remaining cases passed and five obsolete Home-pager expectations were explicitly retargeted to the retained optional paging component, then all five passed. Four base rendering cases also passed. The new Home's ordinary scrolling/filter/story retention is checked separately in reference_journey_test, not weakened into a paging test. Analyzer:23 informational diagnostics, no warnings/errors. A timed-out aggregate run is not counted as passed. New candidate-native CI/device evidence remains awaited.

Source tests cover real shell upload handoff before reply, usable tab navigation, streamed multipart completion versus server finishing, direct confirmed-resource insertion despite older GET responses, deduplication, replay-safe immutable retries, fail-closed unknown outcomes, secure-marker restart/storage failures, bounded warm reel-player reuse, top-left Settings/search, and both navigation-state clearances at320x640 including1.8x text. These are synthetic HTTP/platform/layout checks, not production delivery or Samsung proof. Full applicability and remaining work are in REFERENCE_DESIGN_FOLLOWTHROUGH.md. New APK delivery/publication remains held.

## November17,17:32AEDT: upload-strip fit and exact retention regressions

Candidate source requires explicit `transfers_available:true` as well as replay support before enabling Send. False or absent availability fails closed. This is separate from the already deployed API0510d2c hold; client changes are not on the owner's installed Play2008.

A focused320x640/180%text fixture exposed a real upload-strip RenderFlex overflow when Open original, Retry and Dismiss occupied the same row as the status. Recovery actions now wrap below the status, preserving readable status and available app content. English/dark and Nepali/light Wallet unavailable-state pixels and English/Nepali upload-strip pixels were rendered and inspected. At this large text, Wallet availability copy requires scrolling; the complete notice is reachable. No claim of a compact single-line bar at accessibility text sizes. Fixtures use synthetic data, not phone evidence.

New regressions preserve Home's exact420px offset and original Home GET count through allfive tabs and Settings/back; preserve Reels page/current identity through allfive tabs; insert a confirmed reel at index0 without replacing the currently viewed reel or refetching. Image-only reel fixtures isolate navigation/index behavior, not actual decoding/playback. False/missing wallet availability and disabled money controls are covered. FocusedWallet/reference/upload suites65passed; analyzer84info/noerrorswarnings. Full exactcandidateCI and actual Samsung flows remain gates.

Physical-device acceptance is blocked on the remote connection, not lack of owner consent. Owner reported accepting multiple times; no new setup or consent requirement is inferred. Actual five-tab/full post/story/reel recordings, exact on-phone build inspection, visual reference acceptance, native mic/account-switch proof and Play flexible-update proof remain incomplete. No candidate signed, installed or shipped by this batch.

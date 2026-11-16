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

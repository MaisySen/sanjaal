# Whole-product quality plan

Working plan, November 17, 2026. Not a completion report or a newly approved brand direction.

## User outcome

The current app does not meet the user's quality bar. Passing tests and fixing defects are necessary but insufficient. The Nov 15 brief covers UI, UX, colors, branding, logo, buttons, theme, speed and ease, with a complete product rather than piecemeal releases. The Nov 17 feedback explicitly rejects the cheap feeling and asks for proper planning. Continue the full build, without claiming that infrastructure changes finish it.

## Evidence reviewed

Current source and actual rendered pixels for onboarding, sign-in, home shell, chats, profile and wallet, in addition to the small-phone Create regression. These are synthetic fixture layouts, not production content. Actual Samsung first-run/login proof is tracked separately. The font fix makes Nepali text deterministic but is not a redesign.

Observed design problems and product risks:

- First-run onboarding gives most of the screen to repeated decorative mountains, then asks for multiple Next taps. It explains a feature list rather than quickly making the product useful. Sign-in repeats English and Nepali names above a generic form, with little connection to the onboarding visual language.
- Home stacks a header, tabs, stories, a deeply rounded one-post card, large action bubbles, and a floating navigation pill. Each component competes for attention. Photo content has substantially different visual weight from text posts. Content, author identity and actions need a shared hierarchy across post types.
- Chats are functional rows without a clear social identity. Calls/live rooms are buried in a menu. This is an information architecture issue, not something solved by adding decoration to rows.
- Profile gives large amounts of space to avatar, zero counts and full-width buttons, then another large empty state. It does not help a new member become part of the community. Empty states across the product need useful next actions without fake activity or invented people.
- Wallet is a primary destination while two of its three leading actions are disabled. The unavailable state is truthful, but its prominence promises utility that is not there. Keep the feature and its limitations clear; do not silently remove it from scope or make payments appear enabled.
- Screens use similar black buttons but not a complete common system for spacing, density, shapes, emphasis, state, motion and content. A shared button color alone does not create a product.

## Product contract before changing screens

Preserve the agreed feature scope: posts, reels, stories, chat/groups, calls, live rooms, gifts/wallet, Nepali/English and the Nepal-specific features still owed. Maintain a truthful capability map: built source, deployed API, published app, tested live and tested on a physical device are separate columns. Never show synthetic activity as real or make unavailable money actions appear usable.

Primary journeys to design end to end:

1. New member: value -> sign-in/register -> identity -> useful first destination -> discover/follow or start a conversation. Minimize forced setup and avoid repeated introductory screens.
2. Daily member: open -> resume relevant content/conversation -> react/reply/share -> return without losing place. Preserve feed and tab state.
3. Creator: choose post/reel/story -> capture/pick -> edit/preview -> clear audience/action -> visible progress -> published result or recoverable failure. No unexplained blank or modal dead end.
4. Conversation: find person/group -> message/media/voice -> delivery/retry/read state -> call or group controls. Respect membership and join-time history.
5. Live participation: discover room -> understand status -> join/listen -> speak/request -> leave. Audio/background/reconnect must work, not merely look complete.
6. Value: understand coin balance/activity/gifts and honest availability. No activation, purchases or payouts without the existing approval rules.

## Design system batch

Establish one reusable system before broad screen edits:

- Type roles for display, page title, section, body, metadata and controls; Nepali fallback bundled; text scaling checked.
- Spacing/density scale and a small set of surface/radius treatments. Large rounded containers must earn their space rather than surround every object.
- Common top-level header and consistent nested navigation. Preserve the floating iOS-style glass bar explicitly requested November 16. Evaluate it against real content bounds, keyboard and gesture insets; reduce competing chrome rather than remove that requirement. Do not change destination order casually.
- One action hierarchy: primary, secondary, quiet and destructive. Shared loading, pressed, disabled and progress treatment; tap areas and contrast checked.
- Avatar/content identity rules, real-image crop rules, media placeholders, unread/status badges and timestamps.
- Shared empty, error, offline, permission, loading and recovery states. Skeletons only where they explain incoming content. Preserve unsent work.
- Restrained motion that explains navigation and state; no decorative motion masking load time.

Visual direction remains a working design decision, not claimed user approval. Review prior explicit visual instructions before changing palette or brand. Do not import another project's aesthetic as a Sanjaal preference. No generic gradient-and-card replacement.

## Implementation order and acceptance

### A. Reliability gate already in flight

Finish the secure-storage candidate CI, inspect the actual APK build failure, verify Android plugin migration/restore/logout and unsigned iOS build. Do not weaken emulator assertions. Do not enable Auth0 offline access while the public phone build still persists tokens in ordinary preferences. This is infrastructure, not the product-quality deliverable.

### B. Design audit and reference pass

Review real current competitor journeys through reliable public evidence, with source links and a specific lesson for Sanjaal. Distinguish observed behavior from design opinion. Use a screen/journey matrix, not copied UI or a feature checklist. Resolve current approved constraints before choosing a direction.

### C. One coherent vertical slice

Implement first-run/sign-in -> home -> create -> profile as a connected slice using the system. Include no-content and failure states, back behavior, keyboard and tab state. Review the entire slice together before extending it. Candidate source screenshots are private review evidence; do not drip-release APKs as if each slice were the full app.

Acceptance: actual pixels at 320x640 and normal phone dimensions, light/dark, English/Nepali and 1.8x text; no clipping or blocked main action; identity/actions understandable; widget tests for navigation and recovery; genuine emulator flow and separately labeled Samsung test.

### D. Connected communication slice

Apply the same system to chats, group controls, voice messages, calls and rooms. Verify useful discovery and placement rather than hiding completed features in miscellaneous menus. Test real media/audio, permission refusal, reconnect, backgrounding and two-device behavior where access permits. Anything not verified stays clearly recorded.

### E. Remaining feature depth and performance

Work through the full gap register, including Nepal-specific functionality, with safe data provenance and no money-provider shortcut. Measure cold start, warm resume, feed/media loading and conversation latency from actual runs. Do not promise a 2,000-user free-tier capacity result without measured support. Fix the slowest user-visible path first.

### F. Integrated release gate

One versioned release candidate after connected journeys and regression checks, not a stream of cosmetic APKs. Stable signing, production endpoint checks, no test secrets/data, full CI, visual inspection and precise device evidence. Keep iOS unsigned-build evidence separate from installable iPhone distribution. Report actual remaining blockers and unfinished capabilities; never translate a green test run into full completion.

## Working discipline

Maintain this plan against actual findings, not optimistic status labels. Each batch records what changed, before/after visual evidence, tests and remaining gaps. Continue independent engineering overnight; route only material unavoidable decisions to the parent. Do not wake the user for routine progress, create new paid services, touch unrelated phone data or ship a replacement merely because it compiles.

## Source-informed implementation now in progress

The first connected slice replaces four feature-introduction slides with one optional welcome and separate existing-member/account-creation paths, aligns the sign-in heading with that welcome, adds direct create/search actions to empty Home/Following/Profile, and refreshes Home after publishing rather than telling the user to pull down manually. This is working source, not a completed redesign or released APK. Preserve the requested floating glass bar. Contextual-help and actionable-empty-state rationale: https://www.nngroup.com/articles/onboarding-tutorials/ and https://www.nngroup.com/articles/empty-state-interface-design/ . Touch targets are checked against https://support.google.com/accessibility/android/answer/7101858?hl=en . Native Nepali copy review remains owed.

## Communication slice implementation

Calls and Live rooms now have visible entries below the Chats header instead of miscellaneous-menu placement. Inbox empty/error states have different actions, archived results cannot be overwritten by a late inbox response, and room title entry validates before submitting. Incoming call actions now preserve the ring and show a retryable error after a failed server action instead of pretending an answer/decline succeeded. Local fixture tests and actual small-screen pixels cover these changes; they do not settle real audio, permission refusal, backgrounding, reconnect or two-device gaps. Keep those in the release gate.

## Startup and complete creator-return follow-up

Measured fixture HomeShell startup reads dropped from nine to three by delaying unvisited destinations, not by hiding features. Visited destinations retain state. Background/hidden polling and tickers are gated. Reels and story creation now return to refreshed destinations, with in-flight/stale-response regressions and direct empty-Reels creation. Actual in-shell, small-phone Reels pixels exposed and fixed caption/actions under the glass bar. This completes more of the connected creator journey, not the physical media, performance, push, capacity or Nepal-specific feature gaps.

### Photo journey follow-through, November 17

The multi-photo experience was disconnected: ordinary posts used separate tiles, while the immersive card exposed only the first image and a fixed first-photo counter. A shared, lazy-built gallery now runs in Home and post detail. Swipe advances the image and count; tapping opens the selected image with pinch zoom, page navigation and an explicit close control. Closing preserves the inline position. Failed images have a retry rather than an unexplained blank. Existing single-image callers use the same viewer and retain their authorization headers on retries.

Evidence: 13 offline gallery tests, including both real PostCard treatments in light/dark at 320x640 with 1.8x text, plus the existing discovery journeys. Actual fixture PNGs were inspected. That inspection caught and fixed a black-on-black viewer title before handoff. The full non-render suite completed with 107 passed and one intentional live-test skip. Analyzer has no errors or warnings (22 information notices). This does not prove device swiping/pinch performance, production image loading or Samsung behavior. Native IME verification remains its own gate; no assertion was relaxed, and no new APK or production API deployment is part of this batch.

### Recovery continuity, November 17

Notifications now preserve the current list when refresh fails and show a retry notice, rather than silently ignoring the error. Empty lists remain refreshable. A shared loading guard prevents overlapping reads from racing. The share-to-chat sheet can retry loading its destinations without dismissal or sending a message. Four additional tests exercise empty-to-populated refresh, retained-list/retry, overlapping refresh and share-list recovery. Actual 320x640/1.8x fixture pixels were reviewed; a bulky, low-contrast failure notice was replaced before acceptance.

Latest local regression, including the photo work: 111 non-render, 177 screen-render and 4 base-render tests passed (292 total); one intentional live-test skip. Analyzer: zero errors/warnings, 22 information notices. This remains source-only product progress, not a complete-product or device-verification claim.

Native-input evidence is separate: CI43927332530 passed API, app and unsigned iOS jobs, but correctly failed the real keyboard inset assertion. Actual emulator pixels now show Option2 focused, yet Android reported no visible IME and both insets remained zero. The next diagnostic candidate runs that unchanged gate before any screenshot surface conversion, instead of trying to restore an already converted view. All focus, non-mocked-input, positive-inset, hit-test and above-keyboard assertions remain. No production setting or app behavior was changed to make the test pass.

### Creator review and draft safety, November 17

Story selection no longer uploads immediately. A review route keeps the selected file in memory, shows a photo or paused local-video preview, accepts the existing API's optional caption, and uploads only after Share story. Failed uploads retain the selection and caption. Video preview is manual-play, pauses under another route/background, and does not autoplay on return. A shared exit guard asks before discarding meaningful post/reel/story work and keeps an active upload on screen. Empty posts can still leave directly. This adds no background or persistent draft storage.

Nine creator tests cover explicit share, retained caption/file after a rejected upload, back/keep/discard, busy upload exit and English/Nepali small-phone/1.8x layouts. Two fake-video-platform tests cover manual playback and route/background pause. Existing camera and shell creator-return tests now require explicit story sharing instead of expecting selection to publish. Actual fixture pixels were reviewed and the review-page hierarchy simplified before acceptance. Nepali typography is checked; native copy review is still owed.

Current complete local batches: 122 non-render + 181 render tests = 303 passed, one intentional live-test skip. New screenshot helpers create their output directory themselves; the complete non-render run was also exercised after moving the old render directory aside. The fresh CI app failure on 10cb345 was these missing output-directory creations, not a green candidate. Fix is included here. CI10cb345 still failed native keyboard visibility even with the native gate before any screenshot conversion; API and unsigned iOS passed. Android logs say the FlutterView is not served. Do not claim that surface ordering fixed it.

Remaining creator correctness gap: neither story nor post upload has server-side idempotency. Explicit retry after a server rejection is exercised, but a connection loss after commit can still duplicate a retry. That must be designed and tested before claiming complete upload recovery. This candidate has not been deployed or released.

### Upload retry correctness implemented, activation held

The prepared receipt protocol is now implemented in candidate source. Same-intent/same-payload retries resolve to the original; changed payload conflicts; removed/expired originals stay gone. Keyed bytes commit with the resource and receipt in the DB. The receipt migration refuses destructive rollback after use. Client capability negotiation, stable per-draft intent, ambiguous legacy-outcome handling, original-content opening and explicit new-upload confirmation are connected to the creator UI. See [UPLOAD_RETRY_PROTOCOL.md](UPLOAD_RETRY_PROTOCOL.md) for scope and limits.

Rollout defaults OFF pending receipt migration and DB-media capacity/retention review. This is not a deployment or a claim that persistent local drafts, production upload delivery or free-tier capacity are complete. Live v35 is untouched.

Verification: API 107/855 on SQLite and PostgreSQL normal/cached; all ten real PostgreSQL races pass (66 assertions), including concurrent keyed file uploads and payload conflicts. Flutter 138 non-render + 181 renders = 319 passed, one intentional live-test skip; analyzer 20 information notices, no errors/warnings. Actual conflict/confirmation pixels in English/Nepali, light/dark, 320x640/1.8x were reviewed. The first notice layout hid its recovery actions behind long text; fixed and visually rechecked before acceptance. Keyboard-inset screenshots are simulated, not native-keyboard proof.

### Comments as a complete interaction, November 17

The comments sheet previously fetched up to 300 rows eagerly, had no retry, and could clear or touch an input after the user edited or left. It now requests one cursor page at a time, keeps loaded rows and drafts during errors, retries the same failed operation, and merges late pages without duplicating local sends or reviving locally deleted threads. Root/reply rendering is linear and lazily built. Large-text comment bodies no longer compete with two trailing action buttons in a narrow tile.

Sending freezes the draft and reply target until the result arrives. A rejected write keeps both. A lost response, 5xx or malformed success is treated as uncertain: ordinary resend stays off, review is offered, and preparing another comment needs an explicit confirmation and never sends. This is duplicate-risk handling, not server-side comment idempotency. New comment wording is distinct from upload wording. Closing has an explicit control, waits for mutations and asks before discarding a draft; barrier taps and sheet drags cannot silently discard it. Forced disposal remains safe. Deleting a selected reply target cannot silently turn the retained draft into a root comment.

The API reports how many comments a thread deletion removed, including replies not loaded on this page. Creation and deletion share a post row lock to keep the parent check and comment count consistent. Post and reel callers reconcile their counter from the canonical post when the sheet closes, including after ambiguous writes or an older API response. No API deployment is part of this batch.

Verification: 26 focused fixture tests include real PostCard and ReelItem sheet routes, barrier/drag protection, canonical count reconciliation, pending reads/writes, late-page dedupe, removed-thread tombstones, retry cursor preservation and forced disposal. Actual small-phone English/Nepali, light/dark, 1.8x reply/recovery pixels were inspected. The first recovery notice hid its second action at large text; shortened and rechecked. The keyboard gap in these fixtures is simulated, not native proof. Native copy review and persistent local drafts remain owed.

### Profile recovery and edit continuity, November 17

Member profiles now recover from a failed first read without leaving the page. Refresh errors keep the current identity visible. A confirmed follow/unfollow updates the known relationship/count before read-back, so a failed reconciliation cannot make a successful follow look undone. The read-back can be retried without repeating the mutation. Own-profile count refreshes are sequence-guarded so a late older request cannot overwrite post-publish counts; errors are visible and retryable rather than silently ignored.

Edit profile now owns/disposes its controllers, freezes fields during photo picking/upload and Save, blocks accidental exit during those operations, and asks before discarding unsaved text. A failed Save retains all fields. Success allows exit only after the guard observes the saved state. Photo saving remains an immediate, separate change: its confirmation explicitly says text still needs Save. Canceling or returning from a picker after forced disposal does not upload. This does not add persistent drafts or claim avatar exactly-once/lifecycle cleanup.

Small-screen inspection caught a truncated Nepali edit title and crowded English count labels. The title can wrap with a taller toolbar at large text; metric groups wrap as whole groups rather than splitting labels into isolated letters. English/Nepali edit, member/own profile, retry, and simulated-keyboard fixtures were inspected at 320x640/1.8x in light/dark. Native copy review is still owed. A fixture initially targeted the last mounted form field (username) rather than the lazy-built bio; keyed field targeting and explicit scrolling corrected that test before accepting keyboard-space evidence.

Verification: 31 focused profile tests. Complete local Flutter batches: 195 non-render, 177 screen-render, 4 base-render = 376 passed, one intentional live-test skip. Analyzer: 20 information notices, no errors/warnings. No API changes, deployment or APK publication in this batch. CI12cb11d passed API/app/unsigned iOS and failed only the preserved native keyboard gate; release skipped. Actual Option2 focus/no-keyboard image and zero/non-mocked insets were inspected separately. Full-product and physical-device gates remain open.

### Chat delivery recovery without destroying the next draft, November 17

Retrying a failed text message previously removed it, copied its body into the composer and called Send again. That erased a newer draft, lost the original reply target and generated a different client ID. Retry now sends the immutable original body/reply/random client ID directly. It never changes the current editor or reply. Pending retries cannot be stacked. Poll confirmation replaces pending or failed local copies using both sender and client ID; another sender's key cannot acknowledge the local message. A late transport error cannot downgrade a message already confirmed by polling. Confirmed messages sort by server sequence even when responses arrive in reverse order.

First-load and malformed-poll failures have recovery paths and keep the editor/current conversation. The UI says delivery is unconfirmed instead of claiming a failed response proves the message was not sent. Removed originals stop retry rather than generating a new message. Actual small-phone/large-text light/dark English/Nepali pixels exposed poor error-label contrast; error surfaces and text now use paired theme colors. These fixtures use simulated keyboard space, not native keyboard evidence.

The API's existing per-conversation/sender/client-ID unique key is preserved. Its lookup now runs under the same conversation lock as message creation and before writing private bytes. Membership is rechecked after acquiring the lock. Private DB-only bytes and the message commit/rollback together. Concurrent same-key text and media requests return one original, not a unique-key error or extra blob. A retry identifies the original even if the supplied content differs; it is not an edit protocol. Removed or pre-rejoin originals return410 and cannot resurrect content or bypass join-time history. Replays do not broadcast/push again.

Final group leave now removes current DB attachment bytes in the same transaction before deleting the empty conversation. Legacy B2 rows are deliberately left for separate reviewed cleanup; positive-public-reference access isolation still denies them. A test seeds legacy B2 metadata and forbids network calls to ensure this change never attempts remote deletion. No cleanup or deployment was run against live data.

Verification: API115/919 on normal/cached SQLite+PostgreSQL18;14 actual local PostgreSQL races/97assertions. New races cover four-way same-key text/media requests and last-member leave versus a send, including a seeded private blob. Flutter211non-render+177screen+4base=392passed, one intentional live-test skip;16 focused chat fixtures;analyzer21info, no errors/warnings. Persistent message outbox/drafts, in-app failed media retry, background reconnect and actual two-device delivery remain incomplete. Native IME, full-product and physical-device release gates stay open.

### Reading chat history without losing place, November 17

The conversation previously showed only the latest page. It now loads one earlier page on request using the API's existing exclusive before-sequence cursor. Errors retain the same cursor, loaded messages and current composer. Repeated taps cannot overlap requests; duplicate IDs merge once. Initial history stays a latest-page read even if a local send is acknowledged before it returns. The API regression covers three sorted pages, the exclusive boundary, empty end, join-time visibility and denial after leaving.

Earlier rows grow before a fixed scroll center rather than estimating variable bubble heights and jumping to a guessed offset. Two successive prepends, including negative offsets inside already loaded history, preserve the actual anchor's Y position within one logical pixel in fixtures. Incoming polling can complete during paging. Readers away from the bottom keep their position and get an explicit New messages action. At the bottom, new content follows normally. Send acknowledgements also respect a reader who scrolled away while waiting. Large-text inspection caught a two-line placeholder consuming composer space; the placeholder is now single-line while the actual message can still grow to four lines.

Verification: 14 focused history fixtures plus the existing 16 retry fixtures pass. Complete split Flutter run: 406 passed, one intentionally skipped live test. API116/940 on normal/cached SQLite+PostgreSQL18;14 real local PostgreSQL races/97assertions. Analyzer21info/no errors or warnings. Actual English/Nepali, light/dark, 320x640/1.8x history-retry pixels inspected. The first broad render process hit its command budget and was killed; its complete bounded rerun passed all181renders. This is synthetic layout and local concurrency evidence, not production message delivery, native keyboard or physical-phone proof. Durable drafts/outbox, failed media retention/retry and background reconnect remain open. No live deployment or APK publication.

### Retaining unconfirmed chat media, November 17

Photo and voice uploads now use the same immutable local-message delivery path as text. Private bytes, the original reply and random client ID remain only in memory for explicit retry; selecting or recording again is not required after a rejected, lost or malformed response. Poll confirmation replaces the local copy using sender plus client ID and frees its bytes. A late failed upload response cannot downgrade a poll-confirmed message. Retries do not alter a newer text draft/reply and cannot overlap for the same message. This uses the candidate API's replay behavior, not the post/story upload-intent feature flag.

There is at most one unconfirmed attachment on this screen. Attachment/record controls stay disabled until it resolves or the user explicitly removes its retry copy; text stays usable. Removing a copy confirms that it does not delete a message that may have arrived. Back waits for a pending upload and asks before losing an unconfirmed local copy, with the same distinction. Forced disposal remains safe. Copies are not saved across leaving, process death or logout. Pending recording and general text draft retention remain separate work.

Actual 320x640/1.8x English/Nepali light/dark media-retry and exit-confirmation pixels were reviewed. The first exit notice wrapped its long title badly and hid the end of the explanation behind scroll; wording was shortened and rechecked. Inspection also found the shared snackbar style dropping the chosen font/fallback; it now inherits the theme's body style. The local image fixture is synthetic. The voice fixture injects recorded bytes at the callback and is not microphone/codec/device evidence.

Verification:18 media tests exercise multipart bytes/key/reply preservation, response loss/malformed results, explicit copy removal, poll-before-error, pending controls, voice callback retry, picker/upload forced disposal, guarded back and large-text layouts. Complete split Flutter:128non-render+115journey+181render=424passed, one intentional live-test skip. Analyzer21info/no errors or warnings. API unchanged from116/940 and14localPG races97. No production deployment, new APK or native/device pass implied.

### Voice playback continuity, November 17

Private voice downloads and native source preparation now check visibility and the current source generation before resuming audio. Covered routes and backgrounding pause; returning does not auto-play. A request that finishes after exit/source replacement cannot start playback or update the departed widget. Loading disables duplicate taps. Pause/Play reuses the prepared source and position instead of downloading and restarting each time. Own-message control/progress ink now comes from the bubble's inherited foreground instead of painting the primary color on a primary background.

Verification:15fixtures use the actual VoiceBubble against controlled private-download futures and fake decoder/speaker events. They cover late downloads, pending decoder preparation, route cover, background/resume, changed URL, repeated taps, fetch/decode errors, completion and pause/resume without another download. Decoder failure follows the plugin's existing30second preparation timeout; the fixture advances that clock rather than treating it as an immediate error. Four actual320x640/1.8x EN/NE light/dark own/received-control PNGs reviewed. Complete split Flutter:143non-render+115journey+181render=439passed, one intentional live skip;analyzer21info/noerrorswarnings. Test-only platform interface is now an explicit dev dependency at its already locked version. No codec/audio-device/production proof. Recorder capture permission/start/stop disposal remains separate open work.

### Voice capture ownership and cleanup, November 17

Recorder capture now owns its start and finish futures through shutdown. Late permission or temporary-directory results cannot start capture after cancellation. If a native start is already in flight, cleanup waits for it to return before canceling/disposal; stop-in-flight similarly finishes before disposal. Captured bytes cannot trigger a send after leaving/backgrounding. Route cover or background cancels the in-memory recording without auto-restarting on return. Permission UI can itself make the app inactive: in that case granting permission does not silently start capture afterward; a fresh microphone tap is needed. A recorder first built while inactive cancels without requesting permission.

Send and discard are single-flight. All paths attempt cancellation and delete the recorder's own temporary paths; callbacks notify only once and only while mounted. Send reads the completed file only while active, then removes it; late stop/read completions cannot upload after exit. The existing120second recording-limit send behavior is preserved, not newly introduced. Time/status now stacks inside the flexible center so large-text English/Nepali labels do not collide with discard/send controls.

Verification:21new controlled-recorder/file fixtures exercise disposal at permission/directory/start/stop, background at permission/capture/stop, covered routes, short/denied/start-failed/stop-failed paths, send/discard duplicates, owned-file deletion, inactive first build, limit behavior and four EN/NElightdark320x640/1.8x layouts. Actual pixels inspected. Full splitFlutter164non-render+115journey+181render=460passed/1intentional live skip; final focused recorder check rerun after inactive-first-build cancellation refinement. Analyzer21info/no errors or warnings. Test-only recorder interface is now an explicit dev dependency at its already locked version. No real microphone/permission/codec/background OS or device proof. A hung native operation can delay cleanup because the plugin serializes calls; device validation remains required. API/livev35/uploadOFF/disabledpayouts unchanged.


### Recorder callback cleanup boundary, November 17

CI43959218322 found the file-deletion assertion could run after bytes were delivered but before asynchronous final cleanup. Production now awaits cleanup before the callback, then rechecks active visibility. The new test inspects the directory inside delivery; event-driven bounded pumping replaces the old fixed-time assumption. It preserves bytes-once and deletion assertions. Full local split461pass/1skip and analyzer21info/noerrorswarnings; not a green CI, device or full-product completion claim. Main journey reconciliation and release blockers are recorded separately in PRODUCT_RECONCILIATION.md.

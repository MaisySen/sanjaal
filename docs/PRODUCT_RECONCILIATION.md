# Whole-product reconciliation

## November 23 implementation/live/gate reconciliation

Private candidate through1486d77, followed by Android notification-open work.
This is engineering sequencing, not owner-facing release approval. Historical
rows below are not current claims of missing implementation.

| Area | Implemented now | Live/acceptance boundary | Remaining work type |
| --- | --- | --- | --- |
| Join/return | Localized auth/reset, signup-to-sign-in fallback, optional welcome/profile setup, secure refresh and generation-owned account recovery | Actual selected-candidate native Auth0/social callback, upgrade/restore/network remain unaccepted | Physical/provider verification, not missing basic form implementation |
| Home/profile/search | Ordinary retained feed, real create return, populated profile grids/counts/actions, people/tag search, comments/gallery/saved/activity recovery | Exact selected candidate scroll/codec/frame/memory/API timing and community depth remain unaccepted | Physical/performance; no fabricated seed activity |
| Creator | Native camera interface, flash/zoom/switch/timer and video pause/resume, review, explicit text/poll/encrypted-media saves, account-owned upload/retry | Scoped older simulator persistence/media evidence exists; no complete selected-candidate physical acceptance. No filters/multi-clip editor/background transfer/cloud sync | Capture effects/multi-clip are actual absent feature depth, not a release gate to silently claim done; requirements/design remain needed, no invented scope |
| Conversation | Search/create, explicit group draft, history anchor, immutable text/photo/voice retry, local chat text copies, identity retirement, group owner handoff/removal | Native copy restart prepared only; two-device/media/audio/network exact-candidate acceptance open. Existing group ownership/removal flags were false in11:15 live read | Physical; coordinated flagged rollout, not missing group-role source |
| Privacy/story | Enforced comments/share controls, close-friends/hide protected stories, text-only story replies and block behavior |11:15 authenticated live features advertised interaction controls/protected stories/story replies/polls/upload intents/posters/group member refs. This is timestamped evidence, not latest current state | Native/live journey verification. Public old links cannot be made private. No claim of full consent/legal review |
| Reports | Final review, receipts/history/operator commands, optional durable replay/member binding in source |11:15 live auth response omitted history/replay/member-ref features. Client remains on legacy keyless submission there | Migration/coordinated rollout/operator policy and staffing. No silent activation |
| Calls/rooms | Real SDK setup/teardown adapters, active/minimized calls, consent-bound controls and failure recovery | Real two-device media/routing/reconnect/background incoming absent. No OS call-service wake implementation | Independent OS background-call integration is missing, plus provider/physical proof; not solved by foreground polling |
| Push | Android token registration/session cleanup; iOS prepared adapter unselected. Android recipient-bound notification-open continuation source implemented | FCM delivery never established by mocks. iOS native config/APNs entitlement/key/consent/wiring and signed-device proof missing | Android tap source and pinned-SDK channel contract are local-tested only; iOS provider/capability and implementation gates remain |
| Wallet | Balance/history, unavailable funding/cash-out, replay-safe held transfers and review in source; provider services skeleton exists | Member transfer hold/default false; DisabledPayout; no live money movement approved | Provider/legal/product approval and bounded operational verification. Not a working cash-out product |
| Discovery/follow lists | Default-off candidate implementations and eligibility/contracts | Hard false config; revision-protected author opt-in/revocation UI and endpoints exist. Public-audience verification/review producers and operator removal policy/cadence are not a live service | Real missing operational/implementation depth plus policy approval. Do not activate to fill empty screens |
| Updates/distribution | Store-managed Play flexible-update adapter, stable-signing/finalizer contracts, iOS private archive route | No JS/Expo OTA system. Exact signed artifact/store upload/install acceptance and iOS launcher/export/tester choices remain | Reviewed complete batch and distribution/physical gates, not another slice build |
| Nepal-specific roadmap | Nepali/English support exists | Roman Nepali typing, Global Nepali Hour, Blood Connect and festival greetings are not implemented | Unspecified roadmap service work, requires usable requirements/provenance/consent; do not mark as complete or invent decorative placeholders |

Independent engineering is not exhausted. After the Android notification-open source correction, background OS incoming-call integration, Discovery
public-audience/review producers and operator operations, plus absent roadmap/capture depth are real open
product scope. They must not be collapsed into an owner-only blocker list. Pick
bounded work from current contracts first; service policy/money/credential scope
still constrains effects, not local inspection and preparation.

Source provenance: app/lib main/auth/capture/chat/story/member-controls/push/
wallet/update modules; api AuthController feature response and config files;
ios-push-client-preparation.md, story-replies-candidate.md and lifecycle records.
Live snapshot provenance: privately retained11:15 authenticated compatibility
read, auth/me200, conversations200empty. No new live verification is asserted.

## November 23 foreground call reconciliation and deletion branch qualification

After recipient-bound notification source4e50bb3, the HomeShell foreground call
consumer now rejects delayed snapshots across background-return or replacement
login, expired/absent ring deadlines, non-ringing states and unknown call kinds.
A later fresh poll can still present a current call. Seven synthetic invalidation
cases reproduced presentation before the fix; ordinary incoming and active-call
continuity remain covered. This does not add OS background wake, FCM call delivery,
CallKit/Android call-service integration or real two-device acceptance.

IncomingCallPage also now invalidates ringing actions while backgrounded, checks
that exact call read-only on foreground return, and discards status reads spanning
another lifecycle transition. An accepted action receipt crossing pause/resume
cannot automatically join media. If the exact current state is answered and this
screen's user previously chose Accept, it offers explicit Join only. No action is
resent. Five lifecycle regression cases cover cancellation on return, late accepted
receipts both sides of resume, stale read replacement and bounded read failure.
A following bounded foreground refresh now reads that exact call at most every
five seconds while the ringing route is current, stopping on terminal state,
error/malformed response, background, account retirement or disposal. The server
ring deadline remains authoritative. A quiet successful ringing refresh does not
replace the ringing label with an unknown-state flash. The consumer learns remote
end or answer-elsewhere without automatically answering, joining or repeating an
action. This is bounded foreground HTTP reconciliation, not immediate events or
OS background ringing. Four additional synthetic refresh cases cover remote end,
answer-elsewhere, single-flight malformed failure and lifecycle/account stop.

Account deletion is an additional integration/completion gap. Current integrated
Settings opens an email draft only. Separate preserved default-off request/status
and read-only planning source exists at account-deletion-private-regressions669470a
(public source aec4501), including bounded media inventory. It is not integrated
here, deployed or activated, and supplies no erasure worker or remote-identity
removal. Reviewed retention/processing notices, completion mechanism and provider
scope are still unresolved. Do not duplicate that intermediate implementation or
claim email handoff equals completed deletion.

## Pinned messaging adapter contract checkpoint

Four synthetic tests now exercise FirebaseMessageOpenSource through the installed
FlutterFire messaging method channel and real SDK RemoteMessage decoding. Cold
initial tap, opened-app event mapping, provider failure and unsupported iOS are
covered without requesting a token/permission or calling an external provider.
The core host and native channel replies are mocked. This narrows an adapter
contract gap; it does not prove native delivery, background process startup, FCM
credentials, signed-device tap behavior or the new sender's deployment.

## Navigation and capture correction, November 22, 2026

The integrated reference review reproduced a narrow-phone navigation problem:
with five destinations plus Search at 320 logical pixels, destination targets
were 46 pixels wide expanded and 41.2 compact. Search was 44 pixels. The local
correction spends horizontal capsule margin before reducing those targets and
sets Search to 48 pixels. All five destinations and the separate Search action
remain. The compact capsule still reduces its height; at this narrow width its
horizontal contraction is limited to preserve touch space. Wider reviewed
layouts retain their existing margins. No brand mark, route, API or capability
was changed.

Twelve geometry/action cases at widths 320, 360 and 390, with compact/expanded
and Search present/absent, pass the installed Flutter SDK's Android tap-target
guideline and explicit bounds/selection checks. This is widget evidence for
those shapes, not a native or whole-app accessibility audit. Usable widths below
302 pixels with all six controls are not covered by that claim.

The combined changed-scope preflight passed 201 selected cases spanning the
existing connected auth/media/chat/profile/reference routes, navigation targets
and live glass policy. After adding the SDK guideline assertion and correcting
its test-only semantics-handle cleanup, the twelve target cases and thirteen
reference cases were rerun successfully. Analysis of all three changed Dart
files is clean. Counts do not measure device speed or complete product acceptance.

Pixel inspection also found that earlier Settings reference captures were made
before route animation fully settled. Settled captures are sharp without an app
font or glass change, so the earlier blurred captures are superseded, not proof
of an application rendering defect. The reference fixture's incomplete wallet
payload and missing secure-store mock also produced a false wallet-failure
screen. The corrected fixture supplies a synthetic empty wallet with all money
paths off. It does not establish a live balance, payment or provider availability.
Image-only Reels fixtures remain control/navigation evidence, not playback proof.

This is a local source/review correction. No native build, push, signing,
installation, distribution or backend action was made for it. The earlier
compiler evidence below belongs to the earlier published runtime, not to this
changed navigation tree. Whole-product/brand and exact-device acceptance remain
open; no feature-status row is promoted by this correction.

## Delivery continuity correction, November 22, 2026, 19:20 AEDT

The review/batch condition is not a blanket source-push or engineering-build ban.
The original owner instructions cover public MaisySen project source and Actions
(November15), scoped Android private beta setup (November17), and one Sanjaal-only
Apple certificate plus private upload (November21). Those scopes do not expand
credentials, audiences, legal attestations or public-store release. Source review,
product design review, compiler validation, stable signing, private acceptance
installation and store/tester promotion remain separate stages. Earlier claims
that no signing or private delivery authority existed were too broad. Readiness
and current operational access must still be verified.

The consolidated runtime at local1d9dbb4 was published as the filtered snapshot
2e07112, without unpublished notes/history or review-only service prototypes:
https://github.com/MaisySen/sanjaal/commit/2e07112ceed3d5e44dc2cf37e308b4489573a6c9
Runtime/native/assets/integration/lock/API trees are identical; two prototype-only
test files are excluded. The combined local preflight passed186 selected cases,
not a complete product or performance test.

The isolated compiler-only run is finished:
https://github.com/MaisySen/sanjaal/actions/runs/44998923978
Both compiler steps succeeded. The iOS simulator payload/source collector passed
with Flutter3.50.0, Dart3.14.0, Xcode26.6 build17F113 and simulator SDK26.5. Android
produced its debug APK but the collector rejected native libraries outside ARM64.
The unsplit debug command did not match the collector's single-ABI contract.
That workflow/checker mismatch is not evidence of an app regression, but the
actual extra library list and post-build tracked-config check were not retained
or completed. The original run remains failed, not retrospectively passed.
No native application ran and no binary was preserved, stable-signed, installed,
uploaded or distributed. No backend deployment or capability activation occurred.

A local-only recovery prepares ABI inventory/hash and post-build-config diagnostics
before rejection, preserves the strict ABI requirement, and selects an explicitly
split ARM64 debug output for a future independently warranted native batch.
Eleven synthetic checker tests pass. No compiler job was rerun for that correction.
Current design/brand, native pixels/device feel, exact delivery-candidate acceptance,
scoped Apple CI identity, export determination and tester/distribution gates remain
open. Neither the Apple identity wait nor this collector failure pauses independent
product work. The backend rollout hold and default-off capabilities are unchanged.


## Earlier connected-product review, November 22, 2026

The delivery-continuity correction above is newer than this section. This section
supersedes only the older historical tables below; none is authority for an action.
This earlier review was reversible local work in `coherent-experience-review`, based on
protected baseline `bf13617be1a6432015face5020a4cbf0ac2be5d6`. The settled shared
session-recovery checkpoint is tree `b78cdc5d0a11d7a67e567f91db861c960ad389a3`.
The connected first-use checkpoint is tree
`e76fa41a1bb0e28dd4302dd4dcec55b75dd34a3b`. The acknowledgement and media
batch follows that checkpoint; its separately recorded tree is not a release
commit or an installed app.

### One direction, not another style restart

PR1 remains the product identity reference:
https://github.com/MaisySen/sanjaal/pull/1 . Owner-supplied Instagram examples
settle white light-mode surfaces, compact profile grouping, edge-to-edge content,
dark full-bleed Reels and content-transmitting glass navigation. They do not
specify a new authentication layout. Preserve the existing supported journeys,
real loading/error/empty states and signing/data identity. Do not restore old
onboarding claims about unavailable wallet funding merely to match an earlier
slide. Do not fill a new member's feed with fabricated community activity.

### Connected first use, exercised through the actual app root

`app/test/connected_first_use_test.dart` now enters the actual `SanjaalApp`, not a
collection of independently mounted destination screenshots. Its synthetic HTTP
journey goes from welcome to registration, empty Home, explicit text-post create
and confirmed feed insertion, people search, member profile, Follow, Message,
confirmed text send, back through the route stack, own profile edit/save,
Settings and back to the original Home post. The fixture checks the ordered
writes and rejects unexpected mutation/read paths rather than converting an
unhandled route into fake empty success. No real identity or service is used.

A connected failure test reproduced a genuine continuity defect: confirmed
signup followed by a failed automatic token grant left the registration form
active, so its primary action repeated signup. The local correction uses a typed
account-created result to switch to sign-in, preserve the entered identifier
and password, hide password visibility and keep the existing explanatory copy.
The next explicit tap retries sign-in, never signup. English and Nepali tests at
320x640 and 180% text check that transition and complete the subsequent sign-in.
Separate English/Nepali actual-root tests take an existing member from welcome
to sign-in, password reset, back to the same preserved form and successful
sign-in. Reset alone never opens an account.

Seven connected captures were inspected: welcome, registration, confirmed first
post, first direct message, edited profile, and the English/Nepali large-text
signup-to-sign-in recovery states. They use real widgets and synthetic people,
posts, responses and delivery. An optional root font override supplies host
Roboto for readable review; normal launches keep platform typography. Initial
host captures with block glyphs were rejected and replaced. These are layout and
route-continuity evidence, not native typography, keyboard, Auth0, performance,
translation-quality or two-person delivery acceptance.

Changed-scope validation after the correction: 120 selected Flutter tests passed
in one run, including five connected-root cases, authentication/recovery,
registration/session restore, Settings ownership and retained-tab/create-return
regressions. Analysis of the four changed Dart files is clean. These are not a
full-product suite, native check or speed measurement. Earlier failed setup
attempts and a mistyped nonexistent test target are not counted as passes.

### Acknowledgement ownership and connected media recovery

The later profile capture exposed a real continuity problem: the clean upload
success strip remained after the whole search/chat/edit journey. Clean success
acknowledgements now expire after eight seconds, or are consumed on a subsequent
route push, destination change or app background. Acknowledgement dismissal does
not clear durable recovery state, remove confirmed content, alter its revision
or send anything. Busy, uncertain and failed jobs remain visible until their
separate recovery steps are handled. The immediate post confirmation still
appears, while the later profile no longer carries unrelated post-success chrome.

Rendered upload actions now bind both session generation and the displayed job
marker and require the owning route to be current. A retained original/dismiss
callback cannot act on a replacement session, another job, an expired success
or a covered route. Twelve dedicated tests cover expiry, cover/return, tab
changes, background, busy/error retention, stale callbacks and opening the exact
current original. Timers belong to the strip and are cancelled on disposal.

`connected_media_journey_test.dart` follows actual root sign-in, Create, post
composer, denied-library fallback, explicit device-picker selection, photo review,
Post, lost response and tab navigation. The permission/picker/HTTP boundaries are
synthetic; no device permission or live upload occurs. With replay capability,
only explicit Retry repeats the original multipart bytes, caption and intent,
without reselecting the photo or creating another resource. Its confirmed photo
appears in Home and profile. Without that capability, Retry remains absent and
blocked: the member can check the original on Me, and the uncertainty marker
remains until deliberately handled. No tab change replays either upload.

The connected member journey also now rejects its first direct-text send,
explicitly retries the same request while preserving a newer unsent thought,
then verifies Stay preserves that thought before it is deliberately cleared.
This is route/editor continuity, not real delivery. Selected existing tests also
cover photo/voice retry bytes, lost-reply/poll reconciliation, pending-route exit,
chat history/session retirement and gallery/capture permission recovery.

Actual pixels were inspected for immediate confirmation, the later clean profile,
photo preview, replay-capable and legacy recovery, confirmed photo, legacy profile
check and the recovered chat with its newer composer text. One early photo
capture preceded async preview decode and was replaced after settling the
fixture. An early incomplete mock omitted Wallet's withdrawals read and produced
a misleading offline banner; that mock was corrected and the final fixture
asserts its full request set and online state. Neither was an application defect.
The error snack was allowed to expire before inspecting the later chat composer.
None of these images establishes native decoding/capture, keyboard, secure-store
restart, translation quality, server replay deployment or device speed.

The final combined changed-scope run passed 227 selected Flutter tests, including
the twelve acknowledgement cases, seven connected-root cases and existing upload,
chat retry/history/leave/session and capture/gallery tests. Analysis of all seven
changed Dart files is clean. The earlier 120-test checkpoint is historical to its
own source. Neither count measures device speed or completes native acceptance.

### Current journey matrix

| Journey | Grounded candidate state | Acceptance still open |
| --- | --- | --- |
| Join, sign in, recover and return | Optional welcome, direct registration/sign-in, localized form and password-reset paths; connected signup fallback now selects the correct next action. Current-grant identity retry and generation-keyed root keep old account views quiescent during unresolved replacement sign-in. | Real identity-provider callback/issuance, secure-store and native startup/restore/background/network recovery on the exact candidate. No live signup/reset was made. |
| Home, content and daily return | Ordinary scrolling Home with story row, real post cards and retained five-tab shell, not the historical media-first pager. Connected text/photo creation confirms and retains the new post through search/chat/profile/Settings navigation; clean acknowledgements are bounded and route-owned. | Populated/native scroll, loading feel and frame/memory/network measurement. Text fixture success does not prove real media upload/decoding. Empty community depth remains a product issue, not a reason to invent content. |
| Reels and media | Dark full-bleed destination, bounded player pool and route/tab/session retirement. Shared recovery gives a reachable current-account root action or actual signed-out sign-in; identity retry does not clear a replacement grant. | Exact native codec/audio/interruption/playback and physical device feel. Retired content and synthetic players are not playback acceptance. |
| Find people and content | Existing people/hashtag search and real profile/detail paths remain available. Populated profile grids have separate fixture evidence. Discovery has a default-off client/server candidate with explicit author choice and strict eligibility. | Discovery is not activated. Public-audience/review producers, approved rollout policy and removal cadence, coordinated deployed contract and real image/scroll proof remain absent or unapproved. Do not expand Discovery to substitute for full-product acceptance. |
| Create, review and recover | Existing explicit post/reel/story review, account-owned upload state and local draft paths are retained. The earlier in-memory-only draft statement below is obsolete. | Consult the exact lifecycle/draft/media records for their scoped native evidence. Automatic outbox, durable background transfer and cloud sync are not supplied by this review. Full media/permission/response-loss journey on the selected candidate remains owed. |
| Conversation and identity | Connected member search/profile/follow/direct-text recovery, newer-composer protection and own-name save return correctly in the tested path. Existing group/history/media and account-owned editor protections remain source work, not widened here. | Two-device delivery, real private media/audio, native network recovery, group-role behavior and full normal/large-text review of final routes. A mock acknowledgement is not a real received message. |
| Wallet, calls, rooms and push | Required destinations and honest unavailable states remain. No money/provider/sender activation or live room/call occurs in this review. | Provider/legal/operational gates and separately authorized rollout; two-device calls/rooms, consent/revoke, real audio routing/interruption and push foreground/background/logout-switch proof. Do not infer live capabilities from old tables. |
| Settings, privacy, language and proposed services | Existing supported settings and source-backed controls remain distinct from missing enforcement. English/Nepali fixture layouts are reviewed within named shapes. Proposed services remain design work, not implemented services. | Native-language review, broader accessibility/device audit, each missing server-backed privacy/audience flow and owner decisions for any service activation. Public links are not made private by local filtering. |

### Remaining coherent-candidate gates, in order

1. Finish current changed-scope checks and freeze one inspectable local tree.
   Review connected first-use and populated main destinations together against
   PR1 and the supplied owner references. A changed screen is not a reason for
   another product build.
2. Audit remaining real journey breaks in that tree, especially native return,
   media creation/recovery and conversation continuity. Preserve existing
   off/default capability behavior rather than inventing activation prerequisites.
3. Keep source, fixture evidence, native evidence, release artifact and installed
   device acceptance separate. Earlier native/CI facts below belong to their
   own source, not automatically to this tree. No new live/API/CI state is
   asserted by this local review.
4. Select and review one coherent candidate before any new build or distribution.
   Proper OTA/release-channel decisions remain separate; Flutter source work
   does not establish an Expo OTA path. Exact-candidate on-device review remains
   required before distribution. Never uninstall or wipe to bypass identity.

The retained signed iOS artifact is still 0.5.8+2013 in the separate release
lane. This review does not change, upload or distribute it. No commit, push,
merge, deployment, production migration, audience/consent change, provider
activation, paid service or new product build is authorized by this document.

## Historical checkpoints

November 20 addendum: the draft-only-in-memory statements in this historical
checkpoint are superseded by the encrypted creator-media and text/poll work in
[LIFECYCLE_DRAFT_CORRECTIONS.md](LIFECYCLE_DRAFT_CORRECTIONS.md). Explicit local
photo/video/story saves now exist in candidate source, with scoped native
process-restart evidence. They are not an automatic outbox, background resume,
cloud sync, production upload acceptance or an installed physical-phone update.
Other historical statuses also require their later exact verification records.

November 17, 2026, 08:25 AEDT. Candidate source through b9927b7. This is an engineering checkpoint, not a finished-product or phone-release claim.

## Acceptance criterion

The product needs a connected, credible first-use and daily experience. The user's criticism of the whole app is not answered by accumulating isolated reliability fixes. Preserve the requested floating glass navigation while improving what each destination lets a real member accomplish. Never fill an empty community with invented activity or activate payments to make a screen look complete.

## Connected journey review

| Journey | What actually changed in candidate source | What still limits the experience |
| --- | --- | --- |
| Arrive, join, return | One optional welcome; distinct registration/sign-in paths; shared wordmark, heading and neutral theme system; bundled Nepali fallback; secure refresh-store migration | Auth labels are partly English in Nepali. Native social callback, refresh issuance and physical secure-store restore are not proven. Auth0 offline access remains off. |
| Discover and return daily | Media-first Home pager, Following, story rings, search, notifications, current post detail and shared cards; actionable empty states; lazy first visits and retained tab state; requested glass bar retained | No genuine production scroll/performance evidence. Photo/story header and feed controls still need whole-journey feel testing on a small phone. A clean shell is not a distinctive Nepal-focused daily value proposition. |
| Create and see the result | Create selector; post/reel composer; story preview/caption/explicit Share; in-memory draft exit protection; publish return refreshes feed/reels/story rings; linked gallery/detail navigation | No durable local drafts or custom capture tools. Camera, codec and native keyboard are not proven. Replay receipts are source-only and OFF pending DB-media capacity, migration and retention review. Legacy ambiguous uploads require checking before retry. |
| Talk about content and continue a conversation | Shared-post context, inbox recovery, Calls/Live rooms visible under Chats; immutable text/photo/voice retry copies, server replay locking, earlier history and reading-position preservation; playback/capture lifecycle guards | New-chat search ordering and request/exit behavior remain a separate audited gap. No durable outbox, real background-network or two-device delivery proof. Audio fixtures use fake devices. Group administration still needs further async review and member-role depth. |
| Build an identity | Profile/current post continuity, edit-state protection, retry, follow reconciliation, saved content and create actions | Focused own-profile large-text fixture remains metric-heavy and vertically long. Generic `me_dark` fixture includes a missing-response error and is not successful-profile proof. First-use identity needs a clearer purpose and less empty space without hiding real failures or invented counts. |
| Understand value | Wallet balance/activity/send UI, explicit unavailable top-up/cash-out states; DisabledPayout remains bound | Wallet is a primary destination but its provider-dependent value is unavailable. Do not silently remove the requested destination, imply coins are withdrawable or activate a provider. Explain availability clearly and improve honest non-payment guidance. |
| Gather live | Calls/history and room host/speaker/raise-hand interfaces exist | No genuine two-device call, room audio, interruption/reconnect, push or OS lifecycle evidence. An attractive call fixture is not a working call. |
| Nepal-specific purpose | English/Nepali support and community-oriented content routes exist | Roman Nepali, Global Nepali Hour, Blood Connect and festival greetings are not implemented. These need usable requirements, consent/data safeguards and current content provenance, not decorative placeholder tiles. |

## Pixel evidence inspected

Actual fixture images reviewed include `shell_dark.png`, `chats_dark.png`, `wallet_dark.png`, `story_review_top_dark_en.png` and `profile_me_en_dark.png`, plus prior welcome/auth/create renders. The Home image is the current HomeShell, not the older standalone `feed_dark` render with a different navigation treatment. Its glass bar, media-card hierarchy and content controls are visible. Story review has a reachable explicit Share button. Chats exposes Calls/Live rooms. Wallet clearly says that adding coins and cash-out are unavailable. The profile fixture is deliberately large-text and demonstrates the current long metric hierarchy.

These images are generated from real widgets using synthetic data. They do not show a physical phone, real community activity, microphone/camera output, production messages or native keyboard behavior.

## Source, deployed, published and device are separate

| Surface | State at this checkpoint |
| --- | --- |
| Candidate | Recovered source through b9927b7 plus this reconciliation/release-gate correction. Latest full local Flutter result is 460 passed and one intentional live-test skip. API 116/940 and 14 real local PostgreSQL races/97 assertions are the latest checked backend result. Counts do not replace product review. |
| Live API | Last verified image is the isolated v35 media-security correction, not this full candidate. `https://sanjaal-api.onrender.com/api/v1/ping` returned 200/status ok/media b2 at 08:24 AEDT. Health alone does not identify the image or prove feature rollout. |
| Published Android | Release list checked at 08:24: v0.5.1 is still the latest preview, from 51c1c73, not current candidate. `https://github.com/MaisySen/sanjaal/releases/tag/v0.5.1` |
| Latest CI | Playback run `https://github.com/MaisySen/sanjaal/actions/runs/43957455274`: API/app/unsigned iOS passed, emulator pending at 08:24. Recorder run `https://github.com/MaisySen/sanjaal/actions/runs/43959218322`: API passed, other jobs pending. Later results belong in VERIFICATION_STATUS, not inferred here. |
| Native input | Earlier runs actually focus Option 2 but do not show a keyboard; platform/test insets are zero and mocked=false. The real assertion stays in place. No substitute simulated inset or synthetic screenshot is a pass. |
| Physical devices | No engineering-owned Samsung/TeamViewer evidence, real microphone/camera/codec/push/network test or two-device call proof. Separate device-access work is not duplicated here. |
| iOS | Unsigned CI build only, not installable signed distribution. |

## Release-process correction

The historical tag-release job depended only on API/app/iOS, omitting emulator, while the ordinary Gradle release build uses debug signing. A tag could therefore have published the wrong signing identity despite a failing native gate.

The candidate release job now depends on API, app, iOS and emulator. Publication is explicitly disabled in source with an `&& false` condition until stable-key signing and artifact verification are integrated. No repository variable, tag or release was changed as part of this source edit. Removing the condition without those checks is not a release path. The ordinary CI APK is compilation evidence, not the separately signed phone preview.

## Next implementation and release path

1. Close the new-chat search and async navigation gap, keeping the selected people and text stable and making errors recoverable. Then inspect the connected create-chat/group journey, not only an isolated empty screen.
2. Refine profile and first-use hierarchy with actual successful/empty/error fixtures at normal and large text. Make identity and the next useful action clearer without concealing errors or inventing activity. Keep approved destinations and payment containment.
3. Review the remaining main journeys together in light/dark and English/Nepali, with a compact list of features actually usable versus unavailable. Do not add fake roadmap surfaces to claim breadth.
4. Complete the native-input investigation without weakening the real assertion or blocking independent product work. Verify media/permission interruptions, restore/logout, and then real-device calls/push/network as access permits. Report each missing proof explicitly.
5. Select one reconciled release commit. Verify deployed API compatibility and capability flags; review migration, replay, storage capacity and retention before any broad rollout. Keep upload intents OFF and payouts disabled until their separate conditions are met.
6. Build and sign a legitimate production-endpoint phone preview with the stable identity. Verify package/version/certificate, no synthetic tunnel or test endpoint, API compatibility and anonymous download bytes. Publish/deliver it as a preview with precise remaining caveats. A CI artifact alone is not this outcome. Do not advise uninstalling or wiping user data.

Completion requires a usable integrated product and honest device/release evidence. This checkpoint establishes progress and the remaining route; it does not claim that the app now satisfies the brief.


### Subsequent source progress

The next member-discovery/conversation-creation batch closes the audited new-chat response-ordering, retry, pending-controls and discard gaps. It adds an honest unknown-creation outcome path and fixes title truncation in large text. This does not close the profile/first-use or physical-device gates above. See PRODUCT_QUALITY_PLAN.md and VERIFICATION_STATUS.md for scoped tests/pixels and current CI results.


Profile hierarchy follow-through: actions now precede real metrics, identity/count headings are smaller and large-text labels use readable rows. Member Message no longer splits inside a fixed half-width button. Normal and large English/Nepali create-action reachability was checked with actual pixels. At large text it still requires scrolling; the overall profile/first-use journey is not declared finished. The broader device, roadmap, wallet/provider and release limitations remain.

First-use form follow-through: English/Nepali labels, helper/errors and social/pending notices now match language; explicit password visibility and new-password autofill are present. Pending inputs are immutable and duplicate submission guarded. Thirteen offline regressions plus inspected large-text fixture pixels support the source change. Full local result is now 504 passed/one live skip, analyzer 21 info. The earlier partly-English form limitation is closed in source, not a statement about native social callback, secure-store restore or Auth0 refresh, which remain unproven/off as described above. Product and phone release are still incomplete.

Wallet follow-through: localized availability/history, coherent real/stale/error states, readable large-text amounts/actions, scrollable transfer form and one active operation now support the required destination without enabling providers. Ambiguous transfer outcomes block Send only in the current view; durable backend replay remains absent. Full local source checks now total 530 passed/one intentional live skip, analyzer 21 info. This improves the honest experience of unavailable money features, not their availability. Provider-dependent daily value, roadmap, native/device and legitimate release gaps remain.

Later reconciliation,09:39AEDT: the native fixture IME gate now passes with actual Gboard/235inset/unmocked evidence on826f6df, after expected notification permission setup restored native focus. Member-transfer source now has permanent replay receipts, secure saved-original reconciliation and a filled review/confirm/activity journey; localFlutter544pass/one skip, API121/973normal/cachedSQLite+PG and16PG races/118assertions. No rollout or wallet readiness is claimed: receipt capacity/retention and API-client migration/compatibility need review, native storage restore remains unverified, gifts/cash-out are separate, providers stay off. Legitimate stable-signed production-endpoint preview and actual-device/two-device proof remain open. Full-product daily value/roadmap work is not replaced by these fixes.

### Nov17,15:42 product continuation

The full vision remains open after the private beta installation. Source
follow-through now makes call transport state visible over participant video:
connecting, waiting for a remote member, connected, reconnecting and disconnected
are separate. A connected room alone is not presented as another member answering.
Media controls pause during reconnect while End remains available. Own camera
preview stays visible before anyone joins. Previously the preview existed only
inside the remote-participant branch, and the UI kept the literal Connected
state after initial setup even when transport changed.

Five simulated presentation/widget contracts and13 existing setup-cancellation
contracts pass. Eight light/dark call renders pass, including320px/180%text
waiting/reconnecting states. Actual pixels were inspected and a fixture-route
assertion prevents accidental fallback to an unrelated Post screen. These are
not real camera frames, audio, Samsung or two-device proof. Native CI, interruption,
audio routing, media recovery and real two-device calls remain required.
No live call was started, no account used and no money/provider enabled.

### Explicit local creator drafts,0.5.5+2010 candidate

Creators can explicitly save text and incomplete poll options, restore/edit from
Settings > Saved drafts and delete local copies with confirmation. The storage
path uses the existing platform secure-storage plugin with account-hashed keys,
eight drafts maximum, bounded schema, read-back verification, serialized writes
and random per-save revisions. A stale editor cannot overwrite a newer saved
copy. Corrupt/unreadable storage is not replaced. Switching accounts hides the
list/editor and blocks wrong-account posting. Restored polls still need current
server capability; nothing is sent merely by saving or opening a draft.

This is text/poll draft persistence only. Save refuses attached photos/videos
rather than silently dropping them. Media drafts, cloud sync, automatic outbox
and durable background upload are not implemented. Drafts remain on this device
after sign-out and are hidden until the same account returns; explicit deletion
removes them. A posted draft's saved copy remains until deleted, clearly disclosed
in the editor. Drafts are not silently posted or resubmitted. Native recovery
across process death, secure-store failures and reinstall/backup behavior still
need device testing. The CI startup path now includes a real-plugin synthetic
save/read/account-isolation/delete round trip, not physical-Samsung proof.

The previous2009 signed artifacts remain immutable and private. This batch bumps
the next candidate to2010 to keep source/artifact identities separate, not to
publish another drip release. Play2008 and the live3515 API remain unchanged.

### Notification account-lifecycle candidate

Notification registration now has explicit device/account adapters, owner/epoch checks and serialized network binding changes. Sign-out cancels the refresh listener immediately, drains an already-started register before removal, tries authenticated server removal, and independently invalidates the local FCM token. A permission dialog does not hold logout. Account switches invalidate the previous owner's local token before registering another owner; a failed invalidation blocks that cross-owner reuse. Repeated registration replaces rather than stacks listeners. Unsupported platforms fail honestly rather than registering an Android identity for iOS.

18 fake-device race tests cover permission/token/in-flight registration, queued/in-flight refresh, duplicate listeners, stale Session sign-out, account changes, no owner and cleanup failures. These establish callback ordering, not native FCM behavior. 13 auth widget regressions and19 creator-draft regressions pass independently. Two actual320px/180%text notification-status fixtures (English dark/Nepali light) were inspected after fixing a missing fixture back-arrow font. Nepali text still needs native-language review.

Status copy distinguishes device registration from actual delivery, and failed local cleanup from confirmed token removal. The server sender must remain disabled until an installed fixed build has genuine signed-in two-account/foreground/background delivery and logout-switch verification. No FCM credential/provider activation, real token generation, push send, production API/config change or device action was performed for this batch. Offline server removal and native token deletion can still fail, HTTP acceptance does not prove display, a different installation's old tokens are not cleaned here, and process-death/native lifecycle behavior remains unverified. Whole-product work remains open.

### Live-room microphone consent candidate

Room mic-control packets now require the actual SFU participant identity to match the API-returned host identity, the exact local target identity and a boolean allow value. Display names and packet-supplied identities grant nothing. A genuine host grant offers a muted stage place only; the listener must tap Unmute locally. Duplicate grants preserve the listener's manual muted/unmuted choice. Host Go live is the separate explicit local start action. Speaker revocation/leave serialize native disable after any already-started enable; queued stale enables are discarded. Pending native changes disable the mic control. A failed revoke is marked uncertain, blocks further enables and prompts leaving while disconnection is attempted, rather than claiming verified microphone-off.

17 fake-microphone policy/race tests pass, including arbitrary/missing sender, wrong target/type, invitation-without-enable, manual consent, duplicate grants, revoke/leave during in-flight unmute and native failures. 13 communication regressions passed separately;3stable-host stage tests and two actual320px/180%invitation/control renders passed. English dark and Nepali light pixels inspected; invitation and local mic control readable. Existing room chrome still has untranslated text; Nepali copy needs native-language review. These are synthetic widgets/adapters, not microphone capture, LiveKit permission propagation, physical mute or network delivery proof. No real room, token, recording or provider action was used. Older installed clients are not patched by a source commit; source-only fixes do not establish safety of those clients or existing sessions. Direct calls/API/data are unchanged. Real device sender/target/local-consent/revoke/leave verification is still required before lifting a room-use restriction.

Visual review follow-up: the first invitation fixture showed the old oversized large-text room empty-state hint clipped at its scroll boundary above the composer. Replaced that large-text empty state with compact complete localized text, re-rendered and re-inspected both actual images. A geometry assertion now requires the whole empty-state text to end above the composer. Earlier images are superseded for this layout check. No native/media claim is changed.

### Recovered encrypted-video preview integration candidate

The retained encrypted video can now play in post/story review from a bounded
in-memory native source, without a plaintext playback file, local HTTP server,
network URL or auto-upload. Opening stays paused. Route cover pauses it; session
retirement releases the preview. Unsupported formats/decoders retain the honest
unavailable message, not a misleading playable card. Attempted-send locks are
unchanged. Candidatea5cd088 has both-platform same-install process-death recovery,
exact bytes, deleted picker originals, native frames, manual Play/Pause,
route-return-paused and same-owner/new-generation retirement proof.18 actual OS
images inspected, including fixed Pause graphics. Full details and rejected
black-frame predecessors are in MEMORY_VIDEO_PREVIEW.md.

This source is now entering combined CI, not being distributed. Physical Samsung
acceptance, real OS-background interruption, production recovery and release
conditions remain open. No production QA, provider activation or money action.


## Recipient-bound notification destination, November 23

Private source follow-up to9df6132. Push sender now joins each token to its
actual user and adds recipient public ID plus open_version1 per device. Caller
metadata cannot override the binding. No schema/config/credential change or
provider activation is involved; existing old payloads remain supported as
explicit current-inbox offers.

The Android source parses bounded UUID destinations only for version1. Matching
current recipient offers Open conversation; all missing/malformed/unknown-version
or other-recipient message payloads offer only Open chats. Nothing reads or
navigates until an explicit app action. Even bound payloads supply no displayed
identity and never authorize a send. The authenticated conversation GET must
return the exact ID, known type and current title before ChatPage is shown.
404/410 is unavailable, network/malformed results are retryable without mutation.
Same-member login replacement retires a pending read. Event revision binds
retained callbacks to the displayed notification and prevents late cold-start
responses from replacing newer foreground events. Existing work stays under the
new route and returns intact.

17 dedicated synthetic cases pass. The65-case selected root/push/call/startup/
language run passes. Full disposable SQLite API suite:271tests,2441assertions,
six skips; focusedPush7/21. These are local source/fixture results, not provider
acceptance or PostgreSQL race proof. Current change adds no DB mutation or
migration. Changed Dart analysis is clean. EN/NE320x640/180% offer pixels and
English error/bound-offer pixels inspected; initial error back-arrow font was
missing in fixture, corrected and re-inspected. Native notification delivery,
Firebase event integration, exact signed-device/cold-start/account-switch and
production sender rollout remain unverified. No live notification, deployment,
build, signing, install or release was performed.

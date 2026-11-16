# Whole-product reconciliation

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

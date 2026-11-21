# Discovery implementation preparation

Source review: November 21 to 22, 2026, Australia/Sydney.

## Current local candidate status

This file preserves the baseline review below. Subsequent reversible local work now includes an authenticated, source-disabled Discovery controller, eligibility schema and metadata indexes, a thumbnail-only catalog, consent GET/PUT, a session-owned grid/route host, a post-consent screen, and default-off capability-gated entry/menu integration. Nothing is deployed or activated against a live service. The conservative explicit-opt-in policy is provisional and unapproved for rollout. No historical consent was backfilled.

Author consent, verified public audience, moderation approval and actual activation are four separate facts. The consent endpoint changes only the author choice and revision. It cannot approve moderation or verify a public audience. No review/audience producer exists yet; absent or pending facts stay ineligible.

The normal source config remains hard false. Auth/me now reports features.discovery_v1=false by default. Only an explicit true enables the local compatibility entry and author-only settings menu. Missing, false, string or numeric capabilities keep the existing people/tag search. Source integration is not live activation; no configuration was enabled outside isolated tests.

Baseline review status: complete-product preparation, not a shipped feature, live API assessment, or visual-port acceptance. The baseline review itself added no recommendation route, migration or service. The current local additions are recorded above. Existing people/#tag search is not the finished Discovery substitute.

## Intended journey

1. Open Discovery from the existing Search destination. An initial Explore surface shows eligible photo and reel previews. Keep the PR1 light surfaces, edge-to-edge three-column portrait grid and content-transmitting navigation. Do not add third-party branding, AI claims or fabricated engagement.
2. Search remains a deliberate mode: typing opens real people/#tag results, with clear/back returning to the prior Explore position. Existing search ordering, retry and session-retirement behavior must survive.
3. Filter choices must change actual returned content. Start with All and Reels only if the server supports both on the discovery contract. A Photos filter needs explicit image-only eligibility, not the current kind=post filter, which also includes text/polls. Topic chips appear only for real available topics returned by the service, not a hardcoded mock taxonomy.
4. Tapping a preview opens the existing post/reel detail route. Returning preserves scroll, selected filter and loaded pages for the same session. Grid previews never autoplay. Reel playback remains owned by the detail/reel lifecycle, not the grid.
5. Refresh requests a fresh result generation. Pagination appends unique public IDs. An unsuccessful refresh retains only still-fresh usable prior content and gives a retry action; withdrawal or freshness expiry clears it before another read. An initial failure has a distinct error state. Empty results are honest and keep search available. No endless spinner or invented fallback content.
6. Block/report changes invalidate affected discovery content. A retired session clears query, previews, pending work and any owner-specific cache before another account can see them.

## What the baseline source supplied

- `api/routes/api.php` has authenticated GET /posts and GET /users/search. There is no discovery/recommendation or topic-list endpoint in this tree.
- `PostController::index` supports kind=post|reel, following/all scope, hashtag, username and descending-ID cursor pagination of15. It excludes authors blocked in either direction. This is an existing feed, not a personalized recommendation ranking.
- `Post` uses soft deletion. Its current model/schema do not implement a general private-post audience or discovery moderation decision. Protected stories are a separate service, not discovery candidates.
- `Present::post` supplies public_id, kind, body, author, media type/url/mime/optional thumbnail_url, hashtags, counts, saved/reaction state, can_comment and can_share_to_chat. Those interaction flags do not make a public media URL private.
- `SocialController::search` returns people and hashtag matches. People are name/username substring matches, username-ordered, with mutual block exclusion. This endpoint does not return post-search or recommended tiles.
- `app/lib/search_page.dart` implements people/#tag search with a350ms debounce, request-generation protection, clear/retry and session retirement. `profile_pages.dart` and `feed_page.dart` already provide real three-column Posts/Reels poster grids. These are reusable layout/behavior precedents, not a connected Explore service.

These statements describe the pre-candidate source snapshot only. No production data, current inventory, rollout or live behavior is asserted.

## Required server contract, proposed

Choose and document an authenticated discovery contract before client integration. `/discovery` was the proposed name in the baseline. It now exists only in the disabled local candidate described above, not as a verified live service.

Request semantics:

- Bounded page size, opaque cursor, filter and optional supported topic identifier.
- Cursor bound to the query/ranking version and opening result generation. Reject malformed or incompatible cursors rather than silently returning unrelated content.
- An explicit cold-start mode that returns eligible recent content. Call it Explore/recent discovery, not personalized For you. A later ranking service needs its own correctness and safety review.

Response semantics:

- A bounded list of real post public IDs and the existing safe presentation fields needed for a tile and detail navigation.
- A real image or video poster URL, or an honest unavailable-preview state. Never send a video URL to an image decoder or invent a poster.
- An opaque next cursor or explicit exhaustion, supported filters/topics, and a ranking/version marker for reproducible pagination.
- No fabricated view counts, watch duration, personalized explanation, moderation approval or topic membership. Any such field must have a producing service and tests.

Eligibility and data safety:

- Authenticated viewer, both-direction block exclusion, non-deleted post, actual eligible media, and validated references. Apply eligibility before paging/ranking so excluded content cannot leak through counts or topic metadata.
- Never source protected story/chat/private-blob bytes into discovery, including conflicting media references. Existing public media must not be described as access-controlled merely because its post is filtered.
- Define recommendation moderation and author opt-out handling before amplification. The existing report-write route is not evidence of an adjudication pipeline or recommendation-safety status. Do not treat the absence of an explicit decision as approval.
- Keep public post audience, report handling and moderation policy decisions explicit. Do not silently invent a private-account feature or claim that this work supplies one.
- Rate bounds, indexes and query-count tests must be designed against the deployed database capacity before rollout. No new paid indexing/ranking/provider service is assumed.

## Implementation sequence

1. Resolve server eligibility/moderation and opt-out semantics. Record which content is allowed to be recommended and what removes it immediately.
2. Add a separately tested discovery query/presenter behind a capability flag. Reuse tested feed presentation and block boundaries without copying unchecked SQL or creating per-tile queries. Test SQLite and the actual PostgreSQL semantics locally.
3. Add contract/HTTP fixtures for first page, cursor pages, filter/topic changes, invalid payload, no poster, empty inventory, policy removal and unavailable service.
4. Add a session-owned Discovery state. Gate it on the actual capability response; existing servers keep their honest current search route until the coordinated service exists. That fallback is compatibility behavior, not completion.
5. Integrate the reference-aligned grid and real detail navigation. Retain existing search mode and all protected shell/media behavior.
6. Inspect exact-candidate matched pixels and measure actual decoded image/scroll/network behavior. Then run native/device acceptance against the coordinated service. No build, deployment or distribution is authorized by this sequence.

## Acceptance cases still required

All below are proposed checks, not reported passes:

| Area | Required proof |
| --- | --- |
| Discovery behavior | Real eligible content, working filters/topics, first load, refresh, exhaustion, stable deduplicated paging and return-to-grid position |
| Visibility | Mutual blocks, soft-deleted posts, unavailable/deleted media, policy removal and protected/private-reference exclusion at both list and byte boundaries |
| Ownership | Same/other-member re-login, replacement session object, late first/paged responses, queued filter/search changes and account-scoped decoded-image eviction |
| Error handling | Malformed tiles, broken image/poster, no inventory, offline initial/refresh/page failures, invalid cursor and explicit retry without duplicate pages |
| Interaction | Search/clear/back, profile/detail navigation, report/block removal and retained scroll/filter state |
| Accessibility | English/Nepali,320/390px widths,1.0/1.8x text, semantic tile labels, distinct >=44px targets, reduced transparency/motion and no count/overlay collisions |
| Resource bounds | No grid video players, bounded concurrent thumbnail fetch/decode, no request for invisible pages, no unbounded retained pages or per-item database requests |
| Native acceptance | Real service content, native image/video decode, frame/scroll timing, memory/network measurements and exact-candidate on-device review before any distribution |

The populated profile/search fixture delivered with this review does not satisfy this future Discovery acceptance matrix. It proves only the separately stated existing journeys and layout shapes.

## Local follow-through after the preparation checkpoint

For reversible development only, explicit author opt-in is the provisional recommendation policy. This is not owner-approved for activation. Missing/pending/rejected moderation and unknown audience/private-media/block/deletion/preview facts remain ineligible. No consent was backfilled and no existing post was amplified.

At the first primitive checkpoint, standalone Dart modules implemented the fail-closed predicate, same-origin public-media-reference preview selection, and bounded versioned paging with a source-Session ownership binding. They were not yet route-integrated. The later capability-gated integration is recorded below. The paging provider must still establish eligibility on the server. A syntactically valid preview reference is not proof of byte visibility, decode or moderation approval. No automated moderation system is implied. Local tests exercise these primitives, not a complete Discovery journey.

### Strict contract and fixture-driven screen

A proposed discovery_v1 parser now requires an explicit contract marker, bounded rows/cursor, real identities and explicit eligibility facts. Missing facts or moderation do not become default approval. It reuses the preview validator and rejects malformed envelope/identity data atomically. At that parser checkpoint the route was not registered. No live endpoint has been called by this work.

A separate DiscoveryPage widget consumes that pager and displays the existing PR-style three-column portrait grid, real image/poster references, optional functional All/Reels filters, search/open callbacks, refresh/retry, explicit Load more after an empty eligible page, and session-retirement clearing. Thumbnail decode dimensions are bounded to480x640, with fit policy rather than stretching. There are no grid video players, fabricated topic chips, hero ranking or invented view counts. The screen remains an unactivated candidate until the coordinated service, policy and exact-candidate review are accepted.

Changed-pixel fixtures cover320/390px,1.0/1.8x and light/dark. The small-width fixture uses Nepali with two new draft labels in the existing dictionary; native-language review is still required. A synthetic pushed-detail callback verifies return-to-grid retention, not actual PostPage/Reels service integration. Eleven screen tests and six proposed-contract tests pass separately from the prior26 primitive tests. The initial chip recoloring produced unreadable selected text and was rejected after inspecting pixels; explicit onSurface label color and neutral pill styling fix that variant. No new report package was created.

### Existing-route host follow-through

At the route-host checkpoint, an unregistered DiscoveryRoute owned the source-Session-bound pager and connects the screen callbacks to the existing SearchPage and PostPage classes. Its provider is mandatory, with no assumed discovery endpoint and no always-on capability. One focused widget test enters the actual PostPage against a GET-only synthetic Session, verifies the expected post read/body, returns without re-fetching Discovery, opens the actual SearchPage, and returns again. This does not verify real service eligibility, reel playback, live account state or shell activation.


## Local server and consent implementation, November 22

- `DiscoveryCatalog` applies consent, verified public audience, approved moderation, both-direction blocks and soft deletion before its bounded page selection. Every attachment needs known, positive-byte, MIME-matching public source metadata. Unknown/foreign secondary references cannot hide behind a safe preview. Private, chat and protected-story sources are excluded even when a blob flag conflicts. Image/poster references are checked separately. The reel grid response never includes a video source URL.
- The metadata query first selects at most 16 eligible posts (15 plus lookahead) within the same SQL statement/snapshot, then chooses one preview per post. The earlier whole-catalog window ranking was removed after local measurement showed it was expensive. Expression and source-reference indexes are a local migration candidate only. Deployed index construction still needs size/lock/capacity review.
- Signed keyset cursors bind viewer, filter and contract version. Query output omits blob payloads. The existing public-media route remains the byte-level authority. Recommendation opt-out does not revoke already-public links or cached pixels. Product copy promises removal from new Explore results, not retroactive erasure.
- `DiscoveryController` uses public-ID binding and owner-only consent reads/writes. Missing preference returns false/pending/unverified/revision zero without inserting a row. PUT accepts only author choice and revision. A post-row lock serializes first saves; a stale revision returns 409. Existing review/audience facts and original creation time are preserved.
- `DiscoveryConsentPage` is opened only from the capability-gated author menu. It loads a server value before showing a switch, keeps a local unsaved choice, saves explicitly, and shows confirmation only after a strict response with the expected next revision. Failure, malformed success or ambiguous save locks further edits until explicit reload. Pending writes cannot be dismissed as an ordinary draft. Same-member relogin retires the screen and discards late results. Public visibility and review status stay separate in the UI. Nepali additions are proposed wording, not accepted translation.
- The capability-gated `DiscoveryRoute` opens the actual existing Search/Post classes. Ordinary return preserves its grid without an unnecessary refetch. A confirmed local block/delete callback clears cached tiles before revalidation; a failed revalidation cannot resurrect those tiles. There is no remote moderation/consent push invalidation or invented report-adjudication system.

## Local verification and its limits

Isolated free PHP 8.4.28/Laravel and PostgreSQL 14.24 were extracted locally. Tests run with networking disabled, an isolated throwaway database/socket and no original .env. No deployed migration, production connection or signup was used. PostgreSQL is stopped after each run. The original source API dependency tree is untouched.

- 114 selected Discovery, member-action, shell-tab and poster Dart/widget tests passed together, including actual captured Laravel catalog responses through the Dart parser and actual captured consent responses through two explicit screen saves. This verifies response bodies, not mobile-to-server transport.
- Focused new/changed Discovery, Session, shell and test-file analysis is clean. A separate analysis of the entire feed file still reports two pre-existing diagnostics outside these edits. This is not a full-product analysis or suite pass. The shell-tab tests initially used hidden visual labels and failed on the pre-entry snapshot as well; switching the test finder to the existing accessible tooltip made all 10 actual shell journeys pass without changing nav behavior.
- Latest ordinary SQLite Discovery/Feed/Blocking selection: 27 passed, two optional capture tests skipped, 180 assertions. PostgreSQL selection including the guarded race test: 28 passed, two optional capture tests skipped, 190 assertions. Auth/negative-auth/socket-auth regression: 10 passed, 26 assertions. Optional capture tests pass when explicitly enabled.
- The race test forks two real local PostgreSQL workers, holds the common post lock, observes both workers waiting, then releases it. Exactly one revision-zero save commits and the other returns 409; stored revision is one with pending/unverified status. This proves that tested first-save overlap, not all deployment races. An early harness used a stale statistics snapshot and had cleanup errors; it was corrected, and its failed output is not evidence of a pass.
- Consent pixels were rendered at 320/390 logical widths, 1.0/1.8 text scales, light/dark. Actual narrow Nepali large-text and normal English pixels were inspected. Save remains reachable by scrolling. These are deterministic fixture/widget renders, not native/device acceptance.

### Synthetic PostgreSQL query measurement

One local process, PostgreSQL JIT disabled because the extracted runtime has no LLVM, five PHP catalog-call samples per shape, 10,000 synthetic posts and media rows. Dense means all eligible. Sparse means 1% opted in. Protected-source shape adds 10,000 story and 10,000 chat rows, including conflicting references, with sparse consent. Both candidates use the same conservative attachment predicate. Baseline has whole-catalog window ranking and no new metadata indexes; final uses bounded post selection and the proposed indexes. No production inventory or network latency is measured.

| Shape | Baseline PHP-call median | Final PHP-call median | Final EXPLAIN ANALYZE execution |
|---|---:|---:|---:|
| Dense | 56.11 ms | 3.75 ms | 0.58 ms |
| Sparse | 18.23 ms | 3.86 ms | 0.63 ms |
| Protected sources | 3571.64 ms | 7.10 ms | 4.11 ms |

These fixture measurements justify removing the demonstrated local scan cost. They are not a phone-speed claim, performance guarantee or deployed capacity acceptance. Multi-attachment growth, concurrent load, real database distributions, remote IO, thumbnail decoding, scrolling and native behavior remain to be measured. New indexes are not authorized for live execution.

Remaining activation dependencies: owner-approved eligibility/consent policy; real authorized moderation and audience-verification workflows; coordinated live capability/schema rollout and shell/owner-menu acceptance; deployed database/index/limits review; remote content-change handling; exact-candidate native/on-device acceptance before any authorized distribution. No new full product build, commit, push, merge, deployment or distribution was made for this work.


### Capability-gated source integration

- `DiscoveryEntry` is now used by the existing header/nav Search action only after an explicit `features.discovery_v1=true` response. Otherwise it returns the unchanged people/tag SearchPage. The explicit Find people action remains people search even when Discovery is enabled. The actual Discovery service provider requests `/discovery` and applies the strict v1 parser and 15-row bound. Startup still fetches only Home data, not Discovery.
- Session feature state defaults false, parses only boolean true and clears on sign-out. A later service-withdrawal notification retires an open grid/settings view without another read/write, clearing its content. Service withdrawal uses unavailable copy, not a false claim that the user changed accounts.
- The current post author's normal/immersive menu conditionally offers Discovery settings. Other authors and older/disabled services do not get that option. Opening it performs a GET only. Actual owner-menu and pushed-consent pixels were inspected at 390 logical width after loading the real icon/text fonts and removing the test debug banner. Existing popup chrome is retained rather than presented as a new style.
- Twelve focused capability/entry tests cover absent/false/malformed/true flags, sign-out clearing, no speculative startup fetch, actual Home-to-Explore/Search routes, Reels request semantics, return to people search, capability withdrawal, owner-only menu availability and GET-only entry. They are included in the 114-test selection above.

No production configuration, account, endpoint, consent or audience was changed. All positive-capability/mutation states above are isolated synthetic/local test scenarios.


## Remote freshness, cache isolation and adjacent session safety, November 22

This is reversible source work after the 00:25 checkpoint, not an enabled service or a complete-app acceptance result. No server source changed in this batch. Earlier isolated database/race/contract results remain scoped to their recorded server snapshot and were not rerun without a server change.

### Provisional remote-change handling

- The local route now uses a provisional one-minute freshness budget, with a five-second to five-minute injectable bound for testing. This cadence is not approved for live traffic. There is still no remote consent/moderation notification producer, immediate removal guarantee, or revocation of existing public media links.
- The freshness deadline is based on the successful first-page request start, not its completion. A response already older than that budget is not displayed. A failed or pending retained refresh cannot extend the earlier content's existing deadline.
- On expiry, cached metadata, cursor and decoded-thumbnail scope are withdrawn before one visible revalidation starts. A failed revalidation stays empty/error with explicit retry, rather than restoring old tiles. A covered route clears at expiry without issuing reads. Returning after expiry revalidates. A short, still-fresh Search/Post return preserves grid/scroll without an extra read.
- Backgrounding clears content immediately, including a route already covered by Search/Post. Background/covered views do not start revalidation. Resume/return revalidates when the route is visible. In-flight covered responses cannot publish into that retired request generation.
- Confirmed local Block/Delete still clears before revalidation. This is separate from asynchronous remote policy changes and does not claim a report has been adjudicated.

### Thumbnail transport and cache ownership

- Each visible result generation has an independent image-provider key scope. Replacement, filter reset, withdrawal, session retirement and disposal retire that scope, abort pending transport, and evict the exact resized cache keys. Reusing the same URL in a new scope requires a new load rather than borrowing the prior decoded entry.
- One scope allows four active fetch/decode jobs and a waiting queue capped at 48. Retirement rejects queued jobs and closes active clients. Thumbnail transport sends no authorization header, does not follow redirects, accepts only 200 image responses, caps both declared and streamed bytes at 4 MiB, and closes transport on its 15-second timer. Decode dimensions remain fit-bounded at 480 by 640. No grid video player was added.
- These are source and synthetic transport/cache bounds, not device memory, codec, battery, frame-time or network-capacity measurements. Existing public URL visibility remains a server concern, not a claim of cache erasure outside this app.

### Demonstrated post-card and Reels safety defects

Two isolated regressions were reproduced before their local fixes. A retained post delete dialog could issue DELETE after a same-member re-login even though the underlying detail had retired. A retained Reels destination could show its old Follow control and issue POST using the replacement login. Both reproductions were synthetic; no production deletion, follow or account effect occurred.

- Post cards and reaction buttons now bind to their opening session and post. Delete confirmation and reaction pickers close on retirement/disposal. Delete, save, reaction, comments-return and menu paths guard before writes and before applying late outcomes. Author/tag/gift entry callbacks also check the opening session. Eleven focused post-card tests cover same/other-member/logout, late success/failure, old picker choices, and ordinary Cancel/confirm behavior.
- Reels destinations and retained reel items now bind to their opening session. Retirement clears metadata/cursor, prevents upload callbacks from repopulating the list, disposes pooled playback, and suppresses late page, follow, comment-return and player-init results. Follow and navigation callbacks cannot borrow a replacement login. Existing three-player ownership, back-swipe retention, covered/tab/background pause and failed-player recovery behavior remain tested. Twenty-five media lifecycle tests pass, eight of them added for these session cases. This uses a fake video platform, not actual codec or speaker evidence.

### Changed-scope verification

- A 192-test Discovery/post/member-action/shell/poster selection passed with the actual earlier captured Laravel catalog and consent bodies. This includes 11 route freshness cases and nine thumbnail/cache cases. It predates the subsequent Reels extension and is not a full-app suite claim.
- After the Reels extension and final synchronous entry guards, a 75-test selection passed across media lifecycle, post-card ownership, polls, current shell tabs, Discovery capability entry and actual Search/Post routes. These selections overlap; their counts must not be summed as unique coverage. Final logs: `/tmp/sj-discovery-freshness-integrated.log` and `/tmp/sj-session-journey-final.log`.
- Final analysis of 12 focused new/changed source/test files is clean: `/tmp/sj-safety-freshness-analyze-final.log`. Whole-feed analysis retains its two previously recorded, unrelated info diagnostics. No full-project clean analysis is asserted.
- An additional old reference-journey file failed 12 cases because it still looks for removed nav text labels or a prior Settings position. The two representative failure shapes also fail with the preserved 844ee checkpoint source restored, recorded in `/tmp/sj-reference-baseline-check.log`. That file is not presented as a pass or silently rewritten to change the current interface. The 10 current shell-tab journeys pass in the final selection.
- Actual pixels were inspected for a decoded mountain preview and the same route after freshness expiry with an unavailable revalidation. The latter has no tile and keeps Search/Try again available. An initial blank pre-expiry capture was rejected; the retained capture waits for a non-null decoded RawImage. The retired Reels surface was also inspected, showing only session-retirement copy and no reel controls. These are 390-logical-width fixture renders, not native/device or real-remote-removal acceptance.

No full product build, commit, push, merge, deployment, live capability/consent/audience change or distribution occurred. The protected signed 0.5.8+2013 IPA still hashes to 559f122ab90b5b1a7b48acda8b249c0898dec93a4bb3f38161fb3a1c447bd0fe. Isolated server processes are stopped.

Remaining dependencies include the owner-approved recommendation/consent policy and cadence, authorized real moderation/audience producers, live database/index/capacity review, true remote-change signaling or accepted bounded staleness, accepted Nepali wording, and exact-candidate native/on-device acceptance before any separately authorized build/distribution. These changes do not establish full-app completion.


## Shared recovery and current-identity boundary, November 22 after 01:10

The parent rejected the first retired-Reels capture as incomplete recovery: it removed content and controls correctly, but left a pale surface telling an already signed-in member to close and sign in again. That capture is not accepted UX evidence. Content/player retirement remains intact.

### Reachable recovery, without replacing a valid login

- Settings and Reels now use `SessionRecoveryView`, sharing the existing Settings wording and explicit action. An already signed-in member gets Back to account. Only an actually signed-out session gets Back to sign in. The action pops retired routes to the live root without signing out, clearing credentials, replaying a mutation or replacing the new Session. Embedded feed recovery reuses the same body rather than nesting another app bar.
- The app root keys a fresh HomeShell only after the current account identity has loaded successfully. Old retained tabs and controllers do not become the new account's shell. During replacement authentication, the old root shell is removed rather than starting speculative current-account reads with earlier credentials.
- Eight recovery variants were inspected at 320 logical pixels and 1.8 text scale: English/Nepali, signed-in/signed-out, light/dark. Back and the filled recovery action are readable and reachable. Existing Nepali wording is reused; no new native-language acceptance is implied.
- Nine actual-app-root cases cover same-member re-login, other-member login and logout, each with no covering route, covering Settings, or Settings then Saved. Recovery returns to the current account or actual sign-in entry. The tests preserve generation and identity after tapping recovery, with no writes caused by the action. Root tests use an iOS target-platform variant only to avoid Android Firebase initialization in the host harness, not as native iOS proof.

### Failed identity load after a successful replacement grant

A separate synthetic regression showed that a replacement grant could succeed, `/auth/me` could fail, and the old account shell would remain. That was not a verified current identity, even though the Session still held an earlier user map. Evidence before the fix: `/tmp/sj-account-view-before.log`. No live account or credential was used.

- Authentication-in-progress and current-identity readiness are tracked separately from the credential generation. A failed current identity load opens the existing explicit startup-retry pattern instead of an old account shell. Identity payloads require a nonempty string public ID before becoming current.
- Retry uses the current grant to read identity. It does not ask for a password, replace credentials, restore an earlier grant, or clear a valid replacement login. Failed retries remain recoverable. Duplicate retries cannot overlap; late retry success/failure cannot overwrite a later login. Explicit logout still clears the recovery state and reaches actual sign-in.
- Authenticated token acquisition is blocked while the current identity is unresolved, except the precise GET `/auth/me` needed to verify it. This also protects upload/private-media callers using the common token path. Direct media headers and captured account-bound push cleanup are suppressed in that state, rather than pairing an earlier owner with replacement credentials. No automatic clear-on-generic-HTTP-error behavior was added.
- The existing retry screen was also inspected in English/Nepali, light/dark, at 320 logical pixels and 1.8 text. The first narrow Nepali button render crowded its two-line label against the outline. Added vertical button padding and inspected the updated pixels. The page scrolls so the complete retry action remains reachable. A standalone pixel harness initially retained Session's startup-loading default and disabled the button; it was corrected to match the real root's completed startup state. Those failed test outputs are not passes.

### Adjacent retained feed boundary

The real Saved/Hashtag feed primitive could still issue a refresh using a replacement login after its old post cards had retired. The synthetic before-test observed a second read from the old Saved route: `/tmp/sj-feed-session-before.log`. This was a read, not a production mutation or demonstrated cross-account byte disclosure.

FeedList now binds to the opening Session, clears its retained posts/cursor on retirement, blocks later reads/upload callbacks/insertions, and shows the shared reachable recovery body. Pending old responses cannot repopulate it. Twelve cases cover loaded/pending Saved and Hashtag routes across same-member re-login, other-member login and logout. Actual nested Settings-to-Saved-to-current-root return is included in the app-root cases above.

### Settled verification

- Final changed-scope selection: 221 passed in `/tmp/sj-recovery-final-integrated.log`, covering account identity/retry, Reels recovery, feed retirement, Settings boundary, media visibility, current shell tabs, restore/restore UI, auth/registration, post-card ownership, private-media/upload ownership, push registration/readiness and default-off Discovery entry. This is not a full-app or real-network suite. Earlier selections overlap and must not be summed.
- Eight focused recovery/auth/source/test files analyze clean in `/tmp/sj-recovery-final-analyze.log`. Whole-feed analysis still has the two previously recorded unrelated info diagnostics. No whole-project clean analysis is asserted.
- New image evidence: `reels-recovery-{en,ne}-{account,out}-{light,dark}.png` and `account-retry-{en,ne}-{light,dark}.png` under the local review directory. These are inspected fixture renders, not physical-device or service acceptance.
- No server/schema/consent/audience/moderation producer was changed in this batch. No server run, new full product build, package, commit, push, merge, deployment, activation or distribution was started. PR1 visual identity, exact-candidate/on-device and no-uninstall boundaries remain in force.

Remaining rollout/native/policy dependencies recorded above still apply. Shared recovery and these tested session boundaries do not establish full-app completion.

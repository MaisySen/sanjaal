# Screenshot-led product follow-through

November 17, 2026. Work in progress, not a product-completion claim. The published0.5.2 preview predates this direction and remains an engineering baseline. No new APK delivery or publication is approved by this document. Original private screenshots are not committed.

## Integrated source changes

- Home is an ordinary scrolling feed with stories, author, body/media and actions in order. Story-row and feed-filter states remain alive during scroll/filter changes. The five destination states remain lazily mounted and retained.
- Reels has one destination-owned, three-player window: previous, current and next. Warming never autoplays neighbors, and disposal, route, tab and lifecycle pause guards remain. Adjacent back-swipes reuse the same player. This is bounded memory, not a promise that all historical videos remain cached or offline.
- Profile uses compact avatar/name/real-count grouping, full-width normal-size actions, supported Posts/Reels tabs and a tight three-column grid. Text-only posts remain readable tiles. Repost/tagged tabs are not faked.
- Home and Me expose Settings from the explicitly requested top-left hamburger. Settings has search, grouped destinations, theme/language selection, real Saved/notifications/blocked/profile/wallet/support paths and sign-out. Missing enforcement is unfinished work below, not simulated toggles.
- Navigation compacts while scrolling/watching and expands on touch. All five semantic destinations and at least normal phone-sized touch targets stay available. Large text and assistive navigation retain the expanded visual form; reduced motion removes animation. Reel controls reserve the maximum bar clearance in both visual states, including bottom safe area.
- The in-app logo is an English Sanjaal lockup with the repository's original mountain/network symbol. It is original artwork, not evidence of separate logo approval. Nepali language support remains. About reads actual platform package/version metadata instead of the stale0.3.0 display constant.

## Upload journey and safety

The real shell's post/reel/story flow hands an immutable approved snapshot to one app-lifetime job. The composer closes before the HTTP reply, leaving tabs usable. A top strip shows preparation, multipart-stream progress and server finishing separately. A sent body is not called published until a complete server response identifies the resource.

Confirmed resources are inserted directly and deduplicated against late list responses and later acknowledgements. Own profile counts refresh separately without replacing the content list. A server-confirmed result remains visible even when a subsequent read is old or fails. A failure retains the original in-memory snapshot. Explicit safe retry repeats its original intent/data; it never silently constructs a new upload. Unknown results on the currently deployed legacy upload capability cannot retry.

Before any upload request, an account-scoped encrypted-storage marker is written and read back. Successful completion clears it with read-back. A restarted app with an unresolved marker pauses new uploads and asks the member to check their profile; it never auto-replays. Marker/read/write/clear failures fail closed. Logout/account changes invalidate pending preparation and prevent stale results/progress entering another session. The marker stores no caption, media or tokens. Media/snapshot jobs themselves are not persisted across process death. This is not an OS background-upload service; keep the app open. A native durable background transfer service is still unfinished.

## Reference Settings applicability and unfinished implementation

These remain part of the full-build request where applicable, not closed by documenting the gap:

| Reference option | Current grounded state and remaining work |
| --- | --- |
| Accounts Centre / personal details | Sanjaal Edit profile works. Password/security/session-management flows need first-party Auth0 account handling. Do not imitate Meta Accounts Centre. |
| Saved | Existing authenticated Saved destination. |
| Archive | Chat archive exists; own post/story archive and retention/restore still need implementation. |
| Your activity | Notifications and wallet history exist. Broader own content/interactions activity needs endpoint and management flows. |
| Notifications | Real registration status and activity destination; push delivery remains unverified. Per-category controls need actual delivery enforcement. |
| Time management | Needs local usage accounting/reminder enforcement and accessibility review. |
| iPad-specific service | Third-party service excluded. Sanjaal tablet layout remains a separate responsive verification target. |
| Subscriptions / Meta One / Instagram Plus | Third-party offerings excluded. No invented Sanjaal paid subscription or money commitment. |
| Account privacy | No toggle yet. Needs follow-request authorization, list/detail/search/story/call/chat audience rules and media authorization together. Existing public post/story media links cannot be assumed private. |
| Close Friends | Needs relationship management and server-enforced audience selection, including media access. |
| Crossposting | Needs explicitly linked destinations and per-post approval; no silent external sharing. |
| Blocked | Existing server-backed block/unblock list and content/contact exclusion. Further privacy rules need integrated regression tests. |
| Hide story/live | Needs per-member audience enforcement across list, view, media and live join/token paths. |
| Friends feed activity | Needs a defined supported Sanjaal activity model and actual visibility rules. |
| Messages and story replies | Chat exists. Message-request/reply audience settings need server rules. |
| Tags and mentions | Hashtags exist; user tagging/mention permissions and notification enforcement are unfinished. |
| Comments | Added account-wide new-comment/reply audience: everyone, people the owner follows, or nobody else. Server enforces it, owner exception is explicit, existing comments remain readable and deletable. Per-post overrides and deeper moderation remain unfinished. |
| Sharing | Added server-enforced switch for new share-to-Sanjaal-chat messages, with owner exception. UI explicitly says this does not retract old messages or make public links private. Broader reshare audiences/media privacy remain unfinished. |
| Restricted / Limit interactions / Hidden words | Needs server-backed moderation settings and enforcement, not local-only privacy switches. |
| Follow and invite friends | Search/follow exists. Invite/link sharing needs an explicit user-selected destination; no contact upload without scope. |
| Favourites / Muted accounts | Chat mute exists. Feed favourites/account mute still need storage, filters and management. |
| Content preferences / Like and share counts | Need actual preference persistence and consistent feed/reel rendering. Never invent engagement counts. |
| Device permissions | Existing native permission requests/recovery copy. A system-settings shortcut and accurate current-status screen are unfinished. |
| Archiving/downloading | Existing manual photo view; permission, storage, retention and export/archive routes unfinished. |
| Accessibility | System text scaling, semantics, reduced motion/transparency have implemented paths and fixture checks. A full accessible settings/control audit remains owed. |
| Language/translations | English/Nepali device preferences work. Native-language review remains owed. |
| Media quality | Existing upload bounds/compression are not a user-facing quality selector. Needs actual transport/storage quality behavior. |
| App website permissions | No third-party app authorization feature exists to revoke. First-party authorization/session management still needed. |
| Family supervision / Teen accounts | No such enforcement exists. Needs policy, age handling, permissions and tested server rules before exposing controls. |
| Account type/tools | No fake creator/business tiers. Creator tools and permissions need actual backed flows. |
| Fundraisers | No service or payout scope; not activated. |
| Orders/payments | Existing honest coin wallet/history; no merchant activation, real funding or payout. Existing money/rollout restrictions remain. |
| Help / Privacy / About | Working support-email handoff, policy/About and licences. Policy content needs review against each new implemented capability. |
| Account Status | No invented compliance/restriction status. Needs actual moderation decisions and an appeal/review path. |
| Meta AI / Threads / Edits / More from Meta | Third-party services excluded, not copied into Sanjaal. |
| Add account / Log out | Sign-out exists. Multi-account switching and token isolation are unfinished. |

## Remaining integrated proof

Custom gallery/capture layout parity, deeper applicable Settings enforcement, native durable background transfer, live Auth0/device restore, media/camera/audio permission recovery, network interruption, real Samsung installation of this candidate, two-device calls/push and signed iOS distribution remain unfinished. Mock HTTP, generated images and fake video-platform tests do not establish any of those outcomes. No live API migration/provider change is included in this source batch. No third-party branding/private reference photos are published.

## Interaction controls follow-through

Authenticated `/auth/me/controls` reads/writes only the current member. A revision-guarded transaction locks the always-existing owner row, including competing first saves. Comment and new shared-post sends take the same owner lock before checking policy. Already-completed share replay returns the original result, never a fresh send. Feed/reel presentation batches controls and follow-direction checks rather than one controls query per post. Blocking still wins.

The app exposes Comments and sharing only when `/auth/me` advertises `interaction_controls`; old servers get no nonfunctional switch. Loading failures do not populate guessed defaults. Saving waits for a validated confirmation; stale, transport-loss or server-error outcomes require explicit reload, never automatic replay. English and Nepali copy explains exact limits. This is a limited interaction setting, not account privacy. No migration has been applied to the deployed API by this batch.

Local checks for this follow-through: 125 API tests / 1022 assertions on SQLite and a local PostgreSQL service; two dedicated PostgreSQL multi-process control races / 17 assertions; 53 focused Flutter settings/comment/player tests plus large-text small-phone light/dark English/Nepali fixture inspection. Fake video and HTTP tests remain synthetic and do not prove codecs, device playback or live API behavior. Native CI for the prior integrated source is tracked separately.

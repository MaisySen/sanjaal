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

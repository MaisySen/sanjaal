# Profile moderation ownership and content recovery

Thirteen settled old-source checks at d17db81 reproduced repeated confirmations, overlapping pending actions, retained menu actions over a covering route, a block result popping that cover, stale block/unblock choices after refresh, and confirmation callbacks dismissing a different route or completing twice. An intermediate negative run checked some routes before their exit animation finished; only the settled 13-failure run is the navigation negative evidence.

## Changes

- The profile takes one action lock across its menu confirmation, request and any verification read. Start requires its current route, verified profile and a choice consistent with the current blocked state. Dialogs and results stay bound to the original profile read/snapshot and login. Busy state is released in finally.
- Shared report/block confirmation callbacks finish only their captured current dialog, once. A retained choice cannot close a cover. Returning from that cover does not replay the choice; the person must choose again.
- A confirmed block can pop only the original current profile route. A covered completion preserves the cover and rereads the profile. An attempted block with an uncertain response, and an Unblock attempt with either a success or failure response, get a profile read rather than an automatic write retry. Cancel makes no request or extra profile read. This is one mounted page's sequencing, not a server ordering/replay protocol.
- Read failure keeps the readable profile snapshot, locks new actions and offers read-only retry through the existing profile recovery. A later valid read can unlock actions without resending moderation. Login replacement and disposal retire late results.
- The existing profile progress bar also covers pending actions. Unblock uses its already-existing Nepali translation.

## Blocked content follow-through

Keeping a covered profile mounted exposed a separate content path: its existing grid could retain cached posts or accept a late feed reply after the profile became blocked. ProfilePosts now omits its feed children when this profile's loaded blocked flag is true. Existing feed children are disposed, cached tile callbacks retire, and late replies cannot restore them. The header and a localized blocked-status message remain scrollable. A later valid unblocked profile read mounts a fresh feed; an initially blocked profile does not request its feed.

Three corrected negative controls, with this new suppression disabled, failed for cached content, pending content and the initially blocked/unblock transition. The cached control first proves its tile was loaded. The original content probe had not finished loading that tile and is not counted as cache evidence. This is suppression inside this profile only, not global cache invalidation or proof of live server enforcement.

## Verification

44 new cases in profile_menu_ownership_test.dart, profile_menu_recovery_test.dart and profile_blocked_content_test.dart cover the negative shapes, uncertain request/read recovery, actual menu/cancel use, original-read binding, same-member login/disposal, fresh content after Unblock and narrow large-text states.

Current selected invocations, all concurrency 2:
- Group A: 154 passes across new_chat_receipt_test, new_chat_journey_test, group_drafts_test, profile_chat_receipt_test, profile_identity_read_test and member_actions_session_test.
- Group B: 122 passes across new_chat_return_ownership_test, group_creation_receipt_test, profile_menu_ownership_test, profile_menu_recovery_test, profile_journey_test, blocked_recovery_test and profile_blocked_content_test.
- Group C: 57 passes across chat_screen_session_test, communication_journey_test, chats_entry_ownership_test and connected_first_use_test.
All filenames are .dart in app/test. These are three completed selections, not one whole-suite run. They overlap earlier evidence and are not production latency measurements.

An earlier 16-file selection passed 328 before the blocked-content addition. The later 17-file attempt was incomplete when the command limit ended after 211 passes and no reported failure. Its cause is unestablished; no test processes remained afterward. The completed narrower selections do not retroactively complete that attempt. Earlier new-fixture tooltip, live-animation waiting and toast/title matching mistakes were corrected before the final selections. Failed/intermediate runs are not counted as passing.

Focused analysis of the three changed source files and three new test files has no errors/warnings and two existing infos: one profile underscore and one UI import. No full-project analyzer claim.

Actual 320x640 / 1.8x English/light and Nepali/dark pending, read-recovery and scrolled blocked-content captures were inspected. Progress, retained header, disabled controls, recovery copy/retry and blocked status are readable/reachable at the captured viewports. This is not device, full-screen reference or linguistic acceptance.

## Limits

Server moderation targets still resolve usernames. This does not independently authenticate profile identity/claims, validate all response schemas, prevent or undo a wrong server mutation, cancel issued requests, persist uncertain recovery across restarts, serialize other mounted pages/devices, invalidate every app cache or prove all block/report effects. The shared helper's HTTP success interpretation is unchanged. Report retry/idempotency and every other caller's start lock remain separate work. Failed verification retains the last readable snapshot; it does not claim the server reverted an attempted operation.

Profile Message and parent inbox navigation still need their separate covering-route review. Other profile/follow/media/group operations, full journeys, provider/native behavior and product/reference/release acceptance remain open. Default-off capabilities and backend runtime are unchanged.

No live moderation/account/data action, source push, backend rollout, deployment, native build, signing, installation or distribution occurred.

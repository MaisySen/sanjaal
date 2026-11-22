# Chats creation, conversation and return handoff

## Bounded changes

The parent Chats page now requires its current route, active tab and original login before an entry can start. Calls, Live rooms, New chat, row opening, row-menu opening and the archive toggle use that guard. A retained row must still be the exact row in the current list. These checks do not authorize or undo server work.

New chat keeps one opening lock through the child and its resulting conversation. The parent checks its original route again after the child returns. A checked child receipt opens the conversation directly, without waiting for an unrelated inbox GET that previously did not supply the conversation being opened. Back from the conversation then refreshes the inbox. This removes one source-level dependency, not measured phone latency. Receipt validators, request bodies and default-off capabilities are unchanged.

The child also signals uncertain creation, including its existing covered-result and saved-attempt paths. Back to Chats or system Back after uncertainty causes a normal-inbox read, not another creation or automatic conversation opening. An uncertain return from Archived switches to Chats and removes the wrong-scope list before reading. New creation and archive switching remain gated until a valid normal-inbox payload is accepted. A malformed payload or failed read does not release that gate. The gate belongs to this mounted inbox, not a persistent replay protocol.

Pending recovery shows progress. An empty pending inbox no longer shows the Start a conversation prompt as though it had finished loading. A failed read preserves existing rows when available, with the existing read-retry notice. A held retry repaints progress and keeps its notice retry disabled. An untouched cancel preserves archive scope and adds no inbox GET. Existing readable chats are not blanket-locked behind creation recovery.

## Verification

Thirteen corrected old-source cases at 32b0af8 failed: eight retained entries under cover/inactive tab, a replaced row, two child-return ownership cases, the blocking pre-open inbox read, and the missing uncertain-return refresh. The original critical-path fixture selected a different stable member ID from its receipt; it was corrected and all thirteen negatives were rerun. The corrected log is the negative evidence, not the initial run.

There are 27 new passing cases across chats_handoff_journey_test.dart and chats_handoff_recovery_test.dart:
- The thirteen original shapes and four retained More/row-menu cases.
- Four uncertainty/read-recovery combinations from Chats and Archived, with held reads and success or failure, retained callbacks, read-only retry and no automatic create/open.
- Actual direct and group create > open > one synthetic accepted text > Back > refreshed title/preview, with one creation and one send each.
- Untouched Archived cancel, system Back after uncertainty, malformed inbox recovery and cached-row recovery, including held retries.

Current completed selections, each concurrency 2, filenames under app/test:
- New cases: 27 passes in the two handoff files above.
- A: 150 passes in chats_entry_ownership_test, new_chat_receipt_test, new_chat_return_ownership_test, group_creation_receipt_test, group_drafts_test, new_chat_journey_test, communication_journey_test and connected_first_use_test.
- B: 108 passes in chats_menu_ownership_test, chats_settings_pending_test, chats_settings_lifecycle_test, chats_settings_recovery_test, chat_screen_session_test, chat_visibility_read_test, chat_exit_continuity_test, profile_message_route_ownership_test and profile_chat_receipt_test.
- C: 4 passes in ios_push_readiness_test and api_keepalive_test, preserving the unsupported-iOS/default-off path and synthetic client/session isolation checks.

All names have .dart suffixes. A includes the existing actual-root new-member signup, person search, follow, chat, profile edit and Home return variants. These are completed local selections, not a whole-suite, provider or production result. Counts overlap prior checkpoints.

Focused source/new-test analysis has no errors or warnings and three existing source infos. New test lint findings were fixed. git diff --check passes.

Early recovery assertions saw routes still leaving, and an untouched-cancel probe saw both Back controls during entry; fixtures now wait for the relevant transitions. Settling is not used while the recovery GET is held. The extra held-retry probes then found a real missing repaint at read start. They failed before that repaint correction and pass after it. Visual review also found the premature empty-inbox prompt, which was replaced by the existing loading state.

Eight actual captures were inspected at a 320x640 logical viewport, 1.8x text, EN/light and NE/dark: pending uncertainty, failed read, accepted synthetic message and returned inbox. Progress, disabled creation/archive controls, error/retry and returned previews fit these snapshots. Conversation and inbox titles/previews use existing ellipsis at this width; the composer hint is also shortened. This is bounded snapshot inspection, not full reference, physical keyboard, linguistic or device acceptance.

## Limits and remaining work

A valid list read is permission to resume normal explicit choices, not proof that a previously issued creation never happened. Absence from the inbox does not settle a server operation. Already-issued HTTP is not canceled. Fresh creation still targets usernames; first-response authenticity, server-side ordering, wrong-creation prevention/undo and global/restart replay protection are not solved here. Saved-attempt protections remain as before. The optional child signal is wired into the inbox path, not a claim about every other caller.

Native/provider/cold-start/background, physical-device performance, full product/reference acceptance and private release delivery remain open. No live conversation, message, read acknowledgement, account or data action was taken. No source push, backend rollout, deployment, native build, signing, installation or distribution occurred. Apple identity setup is separate.

Shared leave-confirmation follow-up: [Draft-exit route ownership](draft-exit-route-ownership.md) checks connected group/chat/editor draft leaving. It does not complete the wider limits above.

# Profile-to-chat receipt consistency

Follow-up to profile identity recovery. Five old-source synthetic negatives at f79caee opened a ChatPage after the profile Message response described the wrong selected member, the wrong signed-in member, a group, no members, or a blank conversation ID.

The profile Message handoff now checks the returned receipt before navigation: a nonblank string conversation ID, direct type, exactly two member maps with nonblank usernames, exactly one current signed-in public ID, and exactly one selected public ID with its selected username. Member order does not matter. The owner and selected IDs must differ. Only a consistent receipt reaches ChatPage, which can then perform its existing message reads.

A failed request or invalid receipt leaves the profile readable, shows localized refresh recovery and disables profile actions until a valid profile read. Retry performs only the profile GET, not another conversation POST. A later explicit Message action can try again after verification. A read returning another public ID at the same username does not reopen controls. No claim is made that a failed/malformed/lost response means no conversation was created.

The completion also belongs to its original profile read and snapshot. A superseding read, replacement login or disposal cannot navigate from that old request. Busy state is released in finally when the original session/page remains active. A retained Message callback cannot bypass a currently blocked profile. No new conversation request body, backend contract or server runtime was introduced.

Verification:
- 29 new synthetic cases cover the five negatives, missing/type-invalid response fields, wrong target username, duplicate/extra/malformed members, both member orders, one pending POST, actual Back, 200-malformed/422/503 recovery with no automatic POST, superseding profile reads, a blocked refresh, late valid/error replies after same-member login/disposal, replacement-person recovery, and EN/light plus NE/dark large-text failure/retry rendering.
- One current 10-file profile/member/first-use invocation passed 175 tests. Files: profile_chat_receipt_test, profile_identity_read_test, profile_count_payload_test, profile_journey_test, own_profile_route_ownership_test, member_actions_session_test, other_profile_list_entry_test, follow_list_test, first_use_test and connected_first_use_test, all .dart under app/test.
- A separate current 20-file cross-area invocation passed 231 tests, using the set in chats-settings-pending.md. These runs overlap and are not a single whole-project result.
- The connected registration/post/search/follow/chat/edit/home synthetic journey passes. Its old minimal conversation fixture now includes both source-API member identities; this is fixture repair, not provider acceptance.
- Four actual 320x640 / 1.8x captures, initial failure and scrolled actions in English/light and Nepali/dark, were inspected. Retry, retained identity/counts and disabled actions remain readable and reachable. Test actions wait for scroll/route animations to settle; the first expanded attempt also used the tooltip wrapper as an IconButton finder and was corrected before passing. Those initial fixture failures are not runtime defects.
- Focused analysis over profile_pages.dart, ui.dart and the two changed/new test files has no errors/warnings and two existing infos. Initial context-across-await infos in the candidate were fixed with explicit mounted checks before the final run. Not a whole-project analyzer claim.

Limits:
- This checks consistency of one authenticated response with the selected profile. It does not independently authenticate the returned conversation ID/member claims or prevent server-side wrong-account creation before the reply. Username-based server targeting remains a separate gap, unchanged. A first profile reply with an incorrect ID under the expected username is also outside this check.
- Other chat creation/entry surfaces are not covered by this profile-only validator. The New chat flow still needs its own selected-member/receipt review. No complete messaging/privacy acceptance follows from this change.
- In-flight server work is not canceled. No cross-process persistence, server ordering, native/provider validation, real-device speed, or final reference acceptance is claimed. Existing API timeouts and default-off privacy/native restrictions remain unchanged.

No live conversation, message, read receipt, moderation, account or data action; no source push, deployment, backend rollout, native build, signing, installation, store or distribution action occurred.

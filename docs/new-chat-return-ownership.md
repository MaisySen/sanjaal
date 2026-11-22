# New chat return ownership

Four old-source negatives at 62c7b32 showed a successful create reply popping a covering route, a retained Back to Chats callback popping that cover, duplicate Back callbacks popping both New chat and its parent, and another POST being issued between a successful result and its return frame. An additional intermediate-candidate negative showed covered row/query callbacks still starting work.

New chat completion is now one-shot and belongs to its original current route. It takes the completion lock before waiting for the frame that updates the exit guard, then checks the captured route again before popping it. Session replacement and disposal still retire the completion. Closing state is included in the action lock, so retained selections cannot issue another POST in that frame. Covered routes also lock query/selection actions at callback execution.

A valid create reply arriving while covered, including a cover inserted during the return frame, does not pop another route or auto-open the chat later. It releases busy state into the existing uncertain-result recovery. When the user comes back, the readable selection/plan remains and Back to Chats can leave only this route. A covered retained Back callback is inert. The group plan and existing replay markers remain unchanged; covered completion cannot trigger a second creation or an unrelated discard dialog.

This fallback does not assert that nothing was created. It deliberately asks the user to check Chats. It does not reconcile the creation or promise an immediate inbox refresh; existing inbox refresh/poll behavior remains in place. No issued HTTP/server work is canceled.

Verification:
- Eleven new cases cover the five negative shapes, a cover inserted during the completion frame, same-member replacement/disposal before that frame, a covered group completion retaining its plan, and EN/light plus NE/dark large-text recovery with actual return to the parent.
- A current 11-file selected invocation passed 222 cases, concurrency 2: the 10 files in new-chat-direct-receipt.md plus new_chat_return_ownership_test.dart. Includes valid direct handoff/Back, profile receipt, group draft and connected first-use regressions. Not a whole-product/native result; counts overlap earlier runs.
- The first four-file integration attempt was incomplete when its 90-second command limit ended after 35 passes and no reported failure. Its cause is unestablished. The four-case focused run then passed, followed by the expanded eleven-case run and the completed 222-case selection. Those runs do not retroactively complete the timed-out attempt.
- Focused analysis over chat_pages.dart and the new tests has no errors/warnings and three existing infos. One new braces info in the initial candidate was fixed before the final analysis.
- Actual 320x640 / 1.8x EN/light and NE/dark captures after returning from a cover were inspected. Recovery copy and Back to Chats fit and remain reachable; retained selections remain visible and disabled. No redesign, physical-device, linguistic or final reference acceptance is claimed.

Limits: this is one mounted creation page's start/return ownership. It does not certify every navigation callback or parent inbox handoff; independent covering-route races elsewhere remain possible. Group receipt identity/type/member validation and server username targeting remain separate open work. First-result/receipt consistency is not independent authenticity. Debounced/already-issued search or server work is not canceled. Restart, provider/native, latency, release and full journey acceptance remain open.

No live chat/group/message/read/account/data action, source push, deployment, backend rollout, native build, signing, installation or distribution occurred.

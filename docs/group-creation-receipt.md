# Group creation receipt consistency

Seven old-source negatives at 227393e showed group creation accepting a direct conversation, a wrong selected member, a missing owner, an extra member, omitted members, a wrong title or a blank conversation ID as a successful handoff.

A group creation now captures copies of the selected stable identities before starting its existing request. The returned group must have a nonblank ID, group type, the exact requested title, creator role owner, exactly one current owner ID and exactly the originally selected member IDs/usernames. Member order is irrelevant. Invalid expected identities, duplicate IDs/usernames and malformed member lists are rejected. The expected selection remains bounded to 1-49 other members, as in the source API.

An inconsistent receipt stays on the existing uncertain-result recovery instead of returning it to Chats. The selected plan remains readable, Create remains gated and Back to Chats works without another POST. This is not proof that no group was created. Group request bodies, server runtime, stored attempt markers and member-ref capability/default-off behavior are unchanged. Saved-group identity preflight remains in place. The two older intended-success fixtures now include the source API's title, group type, role and actual member identities; their former minimal maps were not membership evidence.

Verification:
- 21 new cases: the seven negatives, wrong role/username, duplicate/malformed members and missing/type-invalid fields, positive one/two-person selections in both member orders, and two localized large-text recovery/Back cases.
- A current 12-file selected invocation passed 243 cases with concurrency 2. It is the 11-file set in new-chat-return-ownership.md plus group_creation_receipt_test.dart. Includes saved-group replay/default-off/session regressions, direct/profile receipt and return ownership checks, and connected first use. Counts overlap earlier runs, not a whole-project or API/native acceptance result.
- Focused source/helper/three-test-file analysis has no errors/warnings and six existing infos, three in Chats and three in the older group-draft tests. No claim of full-project analyzer cleanliness.
- Actual 320x640 / 1.8x English/light and Nepali/dark wrong-receipt recovery captures were inspected at the scrolled return-action viewport. Recovery text, Back to Chats, retained disabled people and disabled Create remain readable/reachable. This is not a full-screen reference, device or linguistic acceptance claim.

Limits:
- This checks one returned receipt against the captured plan, after the server may have created a group. It neither prevents nor undoes a wrong server-side creation, independently authenticates returned claims, nor supplies a server replay key. No automatic resend/reconciliation is added.
- Fresh groups still use username-based server selection; only the existing saved-group member-ref path has its current server check. That targeting gap, direct/unblock username gaps and server-max read acknowledgement remain unchanged.
- Other group operations, permissions, membership changes after this response, owner handoff, native/provider execution and complete group/product/reference/release acceptance remain open. The extra ledger note covers creation receipt only, not group completion.
- No in-flight cancellation, persistent recovery beyond existing stored markers, global ordering or production latency improvement is claimed.

No live group/membership/account/data action, source push, backend rollout, deployment, native build, signing, installation or distribution occurred.

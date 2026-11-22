# Profile identity read recovery

Follow-up to profile count recovery. Four old-source synthetic negatives showed another person's counts being accepted beneath the signed-in identity on initial load and refresh, an initial other-profile read accepting the wrong username, and a refresh accepting a different public ID under the same username. A retained Follow callback could then act on the unverified profile.

A profile read now requires nonblank string public_id and username fields as well as the existing count validation. Own-profile counts must match the signed-in public ID. An other-profile response must match its route username and, after the first valid read, the accepted public ID. A failed read does not replace a readable snapshot. An unconfirmed own first read remains unavailable rather than zero. The existing localized retry recovers after a valid response.

Other-profile follow, message, menu and member-list actions are disabled during a read and after a failed verification. Their execution handlers also reject retained callbacks. Report/block confirmation activity checks include current mounted/session/profile verification. A valid retry restores the applicable actions, while blocked members and default-off member-list policy remain gated. Independent own-profile Edit/Saved/settings routes remain available.

Fixture correction: older own-profile journey/count fixtures returned another member's ID, and several route-only fixtures omitted identity. Their intended valid responses now use the signed-in public ID and username. Historical green counts were not owner-identity evidence. Existing count/recovery expectations were retained and rerun with corrected identities, including delayed old-owner completions. The intentionally wrong follow-list owner fixture was not changed.

Verification:
- Four old-source negatives reproduced before the source correction.
- Eighteen new synthetic cases pass: the four negatives with retry, missing/blank identity fields, retained Message/report/block/unblock/followers/following callbacks, and four own/other EN/light and NE/dark narrow 1.8x text fixtures. Retained Follow is covered by the original refresh case. All four actual image captures were inspected: failed initial own counts are unavailable; other-profile prior counts remain readable; disabled actions, failure copy and retry fit the captured viewport.
- Completed bounded runs: 48 profile/count/identity checks before coverage expansion, 79 own-route/member-action/list/first-use checks, 18 expanded identity checks, and a current 20-file cross-area run with 231 passes. These sets overlap and must not be added. The 20-file set is the one in chats-settings-pending.md.
- First integration attempt was incomplete after 36 passes/12 invalid-own-fixture failures and its command timeout. After fixture repair the bounded groups passed. A later 27-file combined attempt was also incomplete at its 95-second command limit after 319 passes and no reported failing test. That is not a completed suite or a runtime latency finding. The separate completed runs above do not retroactively complete it.
- Focused source/five-test-file analysis has no errors/warnings and one existing editor underscore info. No claim of full-project analyzer cleanliness.

Limits:
- Validation is local to this mounted profile and the response received. The first other-profile public ID is not independently authenticated; an endpoint returning a wrong ID with the expected username on its first read remains outside this check.
- Username-based follow/direct-message/moderation requests still have a server-side identity race. The client check is not a server precondition or cancellation guarantee. Already-issued requests are not canceled.
- Missing/null counts keep the prior partial-response contract. This is not complete schema, provider, restart or native acceptance. Existing API timeouts are unchanged, and test counts do not measure device feel or production performance.
- Exact reference, physical-device, export, private delivery and full-product acceptance remain open. Privacy/native default-off restrictions and existing signing/distribution gates are unchanged.

No live relationship, profile, account or data operation, source push, deployment, backend rollout, native build, signing, installation, store or distribution action occurred.

Follow-up: [profile-to-chat receipt consistency](profile-chat-receipt.md) adds profile Message response checks and refresh recovery. It does not repair the server username race or other conversation-entry flows.

Moderation follow-up: [Profile moderation ownership and content recovery](profile-moderation-ownership.md) adds the profile menu's action/dialog/return sequencing and blocked content retirement. It does not close profile Message or parent inbox covering-route review, server username targeting or complete moderation acceptance.

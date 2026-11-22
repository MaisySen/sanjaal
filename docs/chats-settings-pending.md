# Inbox settings pending-operation recovery

Follow-up to the per-sheet callback correction at 6886d9d. Six prior-source synthetic negatives showed that a new sheet could send another settings PATCH while the previous write or reconciliation was still pending, a failed reconciliation had no visible retry, and a committed-but-lost response was not followed by a read.

The current mounted inbox now serializes settings changes through PATCH and its fresh list read. This is a page-level settings lock, including other conversation rows. A localized progress line explains the wait. Opening/reading a conversation and returning remain available. Archive-filter changes and unrelated inbox refreshes wait during the operation. Pre-change list reads are invalidated before sending the PATCH, so they cannot replace the visible snapshot while it is pending.

A failed or lost PATCH reply is followed by a fresh read, not another PATCH. Failed reconciliation retains the readable snapshot, shows refresh recovery and keeps setting actions gated until a valid read. The retry performs only a GET. Pending retry is visible, duplicate retry callbacks are suppressed, and the retry button is disabled and dimmed while it runs. No automatic PATCH resend or 'Saved' claim was added.

Reconciliation requires boolean pinned/muted/archived fields in returned rows before reopening controls. Malformed, null or missing flags do not replace the prior snapshot. Outside a pending reconciliation, missing/null fields retain the previous partial-response behavior; wrong-typed present flags are rejected. Two older fixtures were expanded from partial rows to the source API's boolean fields and reflect the resulting mute/pin state. Backend runtime and request bodies were not changed.

Validation:
- 28 new synthetic cases cover reopened same/different setting and row callbacks, pending reconciliation, lost reply, failed read/retry, missing/null/string flags, polling and retained archive/refresh callbacks, pre-change responses, same-member replacement/disposal during write/read/retry with successful and failed replies, and actual conversation entry/Back during a held setting request.
- One current 20-file cross-area invocation passed 231 tests with concurrency 2. This is the 16-file set listed in current-verification-d944b67.md plus chats_menu_ownership_test.dart and the three chats_settings_pending/lifecycle/recovery files. These counts overlap, not add to earlier runs. The older different 15-file concurrency-1 timeout remains incomplete and its cause remains unestablished. Focused source/tests analysis has no errors/warnings and four pre-existing infos.
- Visual fixtures cover English/light and Nepali/dark at 320x640 / 1.8x text and 390x844 / normal text. Pending write, failed read and pending retry pixels were inspected. A first Nepali recovery image squeezed the status into a narrow column despite green tests. The shared Chats/Calls/Rooms refresh notice now wraps status/action when space is tight and stays one compact row at normal scale. Disabled retry text is dimmed. This is bounded fixture readability, not complete reference/device acceptance.

Limits:
- Serialization and the recovery gate live in one mounted inbox. They do not persist across forced removal, process death or a newly created inbox. Already-issued HTTP/server work is not canceled. There is no server-side version/precondition or global serialization claim.
- A fresh read describes the returned current-filter list, not every conversation or proof that this exact request caused its state. The source list is capped at 100 conversations before archive filtering. Absence does not prove where a conversation went. No success toast or causal-write guarantee was added.
- A timed-out request may still execute at the server; a later read does not provide transactional ordering against that work. Existing API timeouts and provider performance were not changed, and no latency/battery gain is claimed.
- Server-max message-read acknowledgement and username-based direct-chat/unblock identity gaps remain separate, unchanged protocol concerns. Full product/native/provider/reference/release acceptance remains open.

No real conversation setting, moderation, message, account or data operation, source push, native build, signing, installation, distribution, provider change or backend rollout occurred.

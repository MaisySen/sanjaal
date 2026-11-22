# Inbox menu callback ownership

The inbox settings sheet now owns its action callbacks. Each callback checks the original active session, its mounted/current sheet, its exact current conversation-row object and a one-shot submission flag before closing that sheet and sending a PATCH. It no longer closes whichever route happens to be current. Menu entry uses the existing shared destination lock so duplicate opens cannot stack sheets. The lock is released after the sheet closes.

Six old-source synthetic negatives were reproduced across the targeted runs: two PATCHes from one callback, mutation after dismissal, mutation while a different route covered the sheet, duplicate sheets, opening from an outdated row callback and mutation from a sheet whose row snapshot had been refreshed. The initial fixture looked for a ListTile, but inbox rows are InkWell; it was corrected before the verified negatives. In the expanded run the dismissed-case old handler removed the inbox, so the added reopen check also lost its row; the earlier minimal negative directly recorded its unexpected PATCH.

Seven new cases cover those shapes plus ordinary current-row selection. Normal completion and dismissal can reopen a new menu. The selected menu, Chats entry, chat-session, visibility and communication groups passed 67 tests. Focused analysis has only the three existing chat-source infos. Layout and API request bodies were not changed; no new pixel/device/reference acceptance is claimed.

At the 6886d9d checkpoint, the submission flag belonged to one sheet and did not serialize distinct menu cycles while the preceding request was pending. The follow-up in [chats-settings-pending.md](chats-settings-pending.md) covers that interaction within the mounted inbox, including read recovery. It does not provide persistence or global/server serialization. Earlier broader 196-case evidence stays anchored to d944b67 and is not inherited as current evidence.

No real conversation setting, account, message or data operation, backend runtime/rollout, push, native build, signing, installation, distribution or provider change occurred.

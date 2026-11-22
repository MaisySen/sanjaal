# Blocked-people action ownership

Four old-source synthetic negatives showed retained Unblock callbacks bypassing the disabled button: two DELETEs could overlap before a rebuild; a callback could mutate while refresh was pending; a removed row remained callable; and a replaced snapshot with the same displayed username remained callable.

Unblock now checks mounted state, the original active session, read/write locks and exact current-row identity at execution time. It takes the write lock synchronously before the request. A current row remains actionable after refresh, and existing post-write reconciliation/error recovery stays in place. The screen layout, API request and default-off controls were not changed.

Validation:
- Five new cases cover the four negatives and a fresh-row-after-refresh positive case.
- The selected action, blocked recovery, settings session boundary and settings search-return groups passed 39 cases. This includes pending success/failure after replacement login, refresh reconciliation, retry and duplicate-action coverage.
- Focused source/test analysis is clean.
- Existing 320x640 / 1.8x retry pixels were regenerated and English/light and Nepali/dark inspected. Heading, refresh control, error and retry remain readable without clipping. These are synthetic retry screens, not physical-device or full reference acceptance.

The blocked endpoint still addresses a username. Exact local row ownership does not provide a stable person-ID check at the server if a username is reassigned between display and execution. That separate source protocol gap remains open; no backend runtime or rollout change was made. No live moderation, message, account or data action occurred. No push, native build, signing, installation, distribution or provider change occurred.

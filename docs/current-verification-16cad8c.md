# Current source verification checkpoint

Behavior source: `16cad8ca25e5166a1aa799b0a24571bdc95f75b9`. No native or release action.

- Account payload/recovery/session restore/registration/follower group: 83 passed, including the actual-root malformed-feature replacement case. Focused account source/test analysis is clean.
- Added cold-restore regression: the rotated synthetic refresh grant survives malformed optional feature data; identity stays unopened and current-grant recovery succeeds without another refresh exchange. All nine dedicated atomicity tests passed afterward, focused analysis clean. No runtime source changed for this additional case.
- Current route/connected integration: 30 passed with concurrency 1 across Chats entry, Calls/Rooms entry, other-profile member-list entry, connected first-use and connected media. These are synthetic fixtures and not physical-device/native provider proof.
- A larger 15-file concurrency-1 attempt was terminated at the command's 120-second limit after 23 passed while a Chats Calls reopen case was running. It remains incomplete. That exact case then passed alone in one second, and the later 30-case batch including its whole file passed. The original stall's cause is not established and no corrective runtime change was made. Do not label the larger batch all-green or inherit earlier counts as current.

The current ledger has 130 original rows, 41 bounded current notes and 89 not reaudited. That is an inventory, not an acceptance percentage. Default-off follower/privacy, Firebase startup consent, physical media/device/reference, separate Apple identity, provider setup, export and signing/install/distribution gates remain open as previously recorded. No source push, native build, live account/data deletion, provider action or release occurred.

# Profile Message route ownership

Three old-source negatives at 4bb7606 reproduced a retained Message callback starting a request while the profile was covered, a valid direct receipt opening Chat over a covering route, and a valid receipt opening Chat while its profile was leaving.

Message now captures its original route and requires that route to be current before starting its existing request. The existing selected-member/direct receipt validation is unchanged. After that validation, navigation again requires the original route to be current, with no await between the check and push.

A valid result arriving while covered or leaving does not open Chat or start message reads there. While the profile remains mounted, it uses the existing localized uncertain-result copy asking the person to check Chats before starting again. It locks actions behind the existing profile read recovery. There is no automatic replay after returning from the cover. Try again performs only the profile GET; another Message attempt still needs an explicit choice. A departing profile is allowed to leave. Already-issued server work is not canceled or undone.

Verification:
- Five new cases: the three old-source negatives plus EN/light and NE/dark recovery/action/explicit-read-retry cases at 320x640 and 1.8x text.
- A completed current seven-file selection passed 120 cases, concurrency 2: profile_message_route_ownership_test, profile_chat_receipt_test, profile_menu_ownership_test, profile_menu_recovery_test, profile_blocked_content_test, profile_identity_read_test and member_actions_session_test, all .dart in app/test. Includes the preceding 44 moderation cases and existing receipt/session checks. Not a whole-suite or latency result; counts overlap earlier runs.
- Focused profile source/new-test analysis has no errors/warnings and one existing underscore info. Two new test braces infos were fixed. The initial visual probe omitted the layout frame after scrolling back to retry and failed before retry completed; the fixture was corrected before the passing run, without another source change.
- Four actual EN/NE recovery and scrolled-action captures were inspected. Error copy, read-only retry and disabled actions fit the captured viewports. This is not full-screen reference, physical-device or linguistic acceptance.

Limits: this covers one profile's request start and receipt-to-navigation ownership, not the parent inbox handoff or every profile/media callback. The first accepted profile and returned conversation claims are not independently authenticated. Server targeting remains username-based; this cannot prevent or undo wrong server creation. The original request body, receipt validator and default-off capabilities are unchanged. Cross-page/server ordering, persistence, provider/native, complete product/reference/release acceptance remain open. Previous wider selections remain anchored to their own commits, not relabeled as current here.

No live chat/message/read/account/data action, source push, backend rollout, deployment, native build, signing, installation or distribution occurred.

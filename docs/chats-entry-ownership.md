# Chats entry ownership

Local source correction for conversation, New chat, Calls and Live rooms entry routes. No real call, room, microphone, camera, message or account action was performed.

Corrected negative fixtures demonstrated duplicate routes for all four current entry points, Calls/Live rooms callbacks opening after replacement login, and an earlier New chat callback reviving when the original account returned. Existing New chat/conversation replacement-login checks already blocked those retained callbacks; they remain regressions, not newly fixed defects. The initial conversation fixture incorrectly expected a ListTile rather than the real InkWell; corrected fixtures were rerun against old source and produced seven expected failures with two existing passes.

Entry navigation now shares a single-flight lock until the selected route returns. Mounted/session checks cover the auxiliary Calls/Rooms buttons too. Session invalidation permanently retires the inbox state, clears rows/errors, cancels polling and closes an outstanding menu as before. Replacing the Session object also invokes the retirement check. New-conversation return can still refresh the inbox and open the returned conversation. Current routes can reopen after Back.

Nine new entry cases plus existing chat-exit, communication-journey, chat-session and localized-communication groups passed 73 tests sequentially. Focused analyzer has no errors or warnings, with three pre-existing informational lints in the unchanged message UI. Inspected actual current English/light and Nepali/dark inbox/recovery captures at 320x640 with 1.8 text: Calls/Rooms, retry and rows remain readable. No native media, delivery, polling performance, two-device or full-product acceptance is claimed.

No source push, build, signing, installation, distribution, provider activation or data deletion occurred.

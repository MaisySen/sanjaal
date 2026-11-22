# Chat read visibility checkpoint

The conversation read loop now waits while its route, tab or app is hidden. A reply already in flight is ignored if it completes while hidden: it does not change displayed rows, typing, pagination state or the read acknowledgement. Return continues from the last retained displayed sequence. Account retirement and disposal wake a waiting loop so it can exit rather than resume under a later login.

The inbox's existing 12-second timer now skips ticks while another route covers it, the tab is inactive, the app is not resumed, or the account is stale. It does not immediately poll on return; its next existing timer tick can read again. This is reduced unnecessary work, not a measured latency or battery improvement.

Five old-source negatives were reproduced:
- Background and covered-route first replies each issued a hidden read acknowledgement.
- Covered inbox made four reads rather than one across three separate timer ticks.
- A ChatPage actually constructed in a synthetic paused frame made two reads before resume rather than none.
- Background inbox made four reads rather than one across three separate timer ticks.

Eight new synthetic widget cases cover those five shapes plus normal established-history long-poll cursor recovery and paused disposal/same-member replacement login. The established-history fixture retains sequence 1 after a hidden sequence-2 reply, then requests after_seq=1 and displays sequence 2 after return. Held HTTP responses are completed during cleanup.

Validation:
- Selected visibility, chat session, exit continuity, history, retry, communication journey and Chats entry groups passed 101 tests with concurrency 2.
- After a braces-only analyzer cleanup, all eight dedicated cases passed again. Focused analysis has no errors or warnings and the three existing chat-source infos.
- An initial replacement-login fixture mounted a new page while framework frames were paused. Its widget tree did not build until resume and therefore correctly belonged to the replacement login. That was not a stale-loop failure. The retirement test now initializes the original page before pausing; startup uses a forced synthetic frame and checks that the page exists before asserting no requests. Ordinary paused frames do not prove startup initialization.

Limits that remain open:
- An already-issued HTTP request is not canceled. Network, server and mobile lifecycle behavior still need real-device/provider acceptance.
- The server read endpoint (ChatController::read) uses the server's current maximum message ID, not a client-supplied displayed cursor. A new message arriving between GET and the read POST can still be marked read. This client correction does not fix that protocol race or prove exact displayed/painted read semantics.
- Earlier-page fetch, send/retry behavior, restart persistence and the backend read contract were not changed by this correction. No visual design change or new physical/reference acceptance is claimed.

No live message/account/data operation, backend rollout, source push, native build, signing, installation, distribution or provider configuration occurred.

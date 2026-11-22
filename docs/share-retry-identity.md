# Share-to-chat retry identity and confirmation

Seven old-source negatives reproduced two user-visible problems. A fixture that committed a message then lost the reply received a different client ID on retry and committed twice. Six empty or mismatched successful response shapes were still accepted as 'Sent'. No real message or live duplication was produced.

The client now holds one recipient/post/client-ID tuple for an unresolved share in the open sheet. Retry addresses that same tuple. Other recipients are disabled until this attempt is resolved or explicitly abandoned. 'Sent' requires a message ID and matching recipient, client ID, sender and post kind. A non-null shared preview must match the selected post; a null preview is allowed because an already-sent post may later disappear. Unknown/invalid receipts remain unconfirmed, not successful.

Recipient reads reject malformed IDs/titles and duplicate IDs before displaying destinations. Current-row, mounted, session and single-flight checks prevent retained or overlapping callbacks. Session retirement clears the local attempt and closes an old exit dialog without sending under a replacement login.

Interaction choice: this sheet now has an explicit Close control and does not dismiss through barrier taps or drag. A pending request cannot be closed. An unconfirmed completed request asks before closing, warns to check the original chat and explicitly says the retry is not kept. This is in-memory recovery, not persistent draft/restart support. Forced route removal, process death, or closing and opening a new share attempt can still lose that identity; do not claim protection across those boundaries. There is no automatic background resend.

Validation:
- New share widget coverage has 18 cases for lost replies, receipt mismatch, original-recipient lock, busy/close races, null-preview receipts, session change, recipient read recovery, Back and EN/NE narrow large-text exit flows. The final selected share-retry, existing share-session and discovery groups passed 41 tests.
- Three source-API tests passed 33 assertions against explicitly forced in-memory SQLite with provider configuration disabled. The added shared-post replay case confirms the original receipt survives post deletion, returns a null preview and leaves one message. Existing text-message idempotency and shared-preview cases also pass. An initial new fixture expected conversation creation to return 200; corrected it to the API's actual 201 before the pass. No backend runtime code changed.
- Actual 320x640/1.8x English/light and Nepali/dark recovery and exit pixels were inspected. The original chat is visibly retryable, other recipients are dimmed and warning/actions remain readable. Focused analyzer has no errors/warnings and two existing underscore infos in the unchanged shared-post image builder.

The original share-session success fixture had used an empty JSON receipt. It now returns the source-backed message shape instead of allowing an unverified success to pass. PHP reports the pre-existing unavailable GD extension; these text-only tests do not establish image behavior. No physical gestures, live delivery, provider, frozen-server image or native/restart acceptance is claimed.

No live account/message/data operation, source push, native build, signing/install/distribution, provider change or backend rollout occurred.

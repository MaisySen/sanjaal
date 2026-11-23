# Explicit local chat text copies

Private source candidate, not a release or physical-phone acceptance.

ChatPage now offers Save chat text for typed text and Saved text to deliberately
restore or remove the local copy. Opening a conversation never inserts or sends
saved text. Restore over different typed text requires confirmation. A selected
reply is not overwritten. Attachments, reply metadata, voice, failed sends and
outbox state are not persisted by this feature. The existing route-back guard
continues protecting those in-memory changes.

The saved copy deliberately survives sending, with this stated before restore.
It is reusable text, not evidence that a message is pending or delivered. It is
not automatically deleted after sending, because a transport result is not an
instruction to destroy the user's saved copy.

Storage uses the existing secure-storage dependency, hashed account/conversation
keys, version and 4000-rune validation, revision checks, serialized writes and
readback after save/remove. At most 20 copies per device are allowed; existing
copies are never evicted to make space. A write or removal error disables draft
actions until an explicit read reconciles storage. Input remains on screen.
Copies for other accounts are neither displayed nor restored. A save already
started under the old session may finish into that old account's key only.
Session retirement removes draft dialogs and clears the old composer.

Evidence: 18 actual ChatPage fixture journeys, five store tests and nine existing
exit-continuity tests; broader chat, inbox, media, retry, ownership and visibility
selection totals 291 tests across 20 files. Tests use synthetic APIs and a
secure-storage platform mock, including held/lost writes, lost acknowledgements,
failed removal, unreadable storage, account/session changes, covered/disposed
routes and retained dialog callbacks. They do not prove native persistence.

Pixels: 320x640 logical size, 180% text, English/Nepali, light/dark. Saved entry,
scrollable explanation/actions and simulated 280px keyboard inset inspected.
The initial keyboard layout and scrolling-title evidence was rejected on review.
The corrected composer is full width above a single icon-action row with named
tooltips and accessibility labels. The dialog title and Cancel are fixed; an
always-visible scrollbar marks the bounded content region. Opening and
scrolled-to-remove states are separately inspected in all four combinations.
The keyboard fixture is an inset, not a real IME.

No new native dependency, backend flag, report migration, launcher, build,
signing, TestFlight audience, compliance attestation or production change.
Native process restart and physical Samsung/iPhone review remain required in
the next reviewed combined candidate, not a build solely for this slice.


Connected root integration now also exercises the actual first-use path: signup,
post, member search/profile/follow, failed message/retry, explicit save of newer
unsent text, deliberate leave to profile, reopen, explicit restore/removal, then
profile edit and back Home. Message attempts remain exactly two, one initial
failed attempt and its retry; saving/restoring adds none. Five connected tests
passed. The full-width composer is also inspected in that settled root capture.


## Next combined native batch, prepared but not executed

The native chat-copy helper seeds through ChatPage, captures the real-keyboard
boundary, explicitly saves and records the synthetic conversation and copy
revision in application support. The existing host driver terminates the seed
process and starts the same installation. Recovery checks the exact account,
conversation, revision/text and unchanged server messages before presenting an
empty composer. Cancel leaves it empty; explicit Restore fills it. Removal must
clear secure storage without clearing the composer or creating any message.
Another synthetic account cannot read the copy. API and auth fixture origins
must both be loopback port8002 with API path `/api/v1`.

The pixel manifest now requires four additional boundaries, 40 in total. The
existing frozen workflow tree pins deliberately remain unchanged. They must be
re-reviewed and advanced to the complete chosen candidate before any combined
native dispatch. No push, dispatch, native build or signing was done for this
preparation. Earlier 311e497 native evidence does not cover these changes.

Harness-only contract command, mocked storage/API/keyboard, not native proof:

```
flutter test --no-pub --dart-define=API_BASE_URL=http://localhost:8002/api/v1 --dart-define=E2E_TOKEN_BASE=http://localhost:8002 test/native_chat_text_restart_helper_test.dart
```

The dedicated contract passes save, dispose/reopen, explicit restore, removal,
zero sends and all four capture names. Host tests pass 13 pixel-packet, four
same-container process-driver and22screenshot-monitor checks. Native runtime
execution and actual native pixels for this prepared harness remain unverified.


## Conversation identity retirement follow-up

A retained ChatPage state could previously receive a different conversation ID
and keep the old composer/copy controls under that new identity. Two regressions
failed before correction. The screen now permanently retires on a conversation
or Session-object replacement, closes its dialog, clears private screen state
and stops old read continuations. Switching the ID back cannot revive it. The
localized explanation asks to close and reopen, not to sign in again for a
conversation-only change. Existing saved text remains under the original key.
Two same-state replacement cases cover an open saved-copy dialog and retained
remove callback, no message sends and no read/write into the new conversation.
The corrected English320x640/180% retired screen was rendered with real Roboto
and inspected. Initial block-font fixture output was discarded.

The exact c93043c normal sweep covered198files,2652passed/11skipped across26
batches with unchanged lib/test/integration source hashes. It predates this
retirement follow-up. Full analysis had zero errors,15warnings and193infos;
all15warnings were internal SDK hooks in unchanged native-call contract tests,
byte-identical to311e497. Skips were one discovery capture, one isolated server
contract, one opt-in live API, one loopback-only helper and seven Impeller-only
shader checks. The loopback helper passed separately with its required defines.
Do not call this a fully green analyzer or a native/full-product acceptance.

After retirement correction:22session tests,59chat retry/history/exit/media,
36copy/visibility/connected tests and the dedicated loopback helper passed.
The final selection reruns session/connected/language coverage after the copy
change. Changed-source analysis has no errors/warnings and three existing infos.
No native execution, public source push, build or release occurred.

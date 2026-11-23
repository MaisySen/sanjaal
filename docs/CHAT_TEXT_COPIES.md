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

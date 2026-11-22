# Saved-draft route ownership

Local source correction only. All drafts in these tests are synthetic. No live account, saved user data, published content or external service was changed.

The saved-drafts page used an owner/generation comparison without binding the Session object or permanently retiring the route. Negative widgets showed that a replacement Session for the same member kept the old list usable, an account switch followed by restoration revived a retained text-draft callback, repeated callbacks opened duplicate editors, and a disposed callback raised an exception.

The page now uses the existing session-bound lifecycle contract. A retired route clears its text/media list and read errors, stays retired when an account returns, and rejects replacement Session objects. Reopening Settings > Saved drafts creates a fresh route for the current session and can load that account's stored drafts. No stored draft is erased by retirement.

Text-draft navigation now holds the existing busy guard until Back, requires a current row, and checks mounted state. Current drafts can reopen after Back. Stored-draft read, media-open and local-delete entry points also reject a disposed page. Existing revision checks and explicit local-delete confirmation remain unchanged.

Five dedicated route/confirmation cases plus existing text-draft and media-draft widget suites passed 46 tests sequentially. The new stale deletion-confirmation test preserves the synthetic draft through an account switch and return. Focused analyzer is clean. Actual EN/light saved-list and NE/dark conflict-recovery captures at 320x640 with 1.8 text were inspected: list, delete control and recovery message remain readable. These are mocked storage/widget results, not native encryption, restart, media selection, live publication or full-product acceptance.

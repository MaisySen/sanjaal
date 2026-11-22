# Member report follow-through

Source candidate, November 22, 2026. Not deployed or a staffed moderation service.

Members can submit a reason, receive a private receipt, open its original report,
return through Settings > Your reports, and refresh review progress. Returning
from detail updates the existing list row without losing earlier pages. English
and Nepali use the shared reviewed header and existing theme.

The authenticated API exposes owner-scoped GET /reports and GET /reports/{receipt}.
POST /reports creates the receipt and initial event in one transaction. The new
migration backfills historical receipts without inventing a review or date.
Private numeric report/reporter identifiers are not returned. The client exposes
history only when /auth/me advertises report_history. Legacy submission remains
available without an unsupported history link. An uncertain result offers
readback, not automatic resubmission.

Operator commands:

- php artisan reports:queue --limit=20
- php artisan reports:status RECEIPT in_review
- php artisan reports:status RECEIPT closed

The queue is bounded and read-only. Status writes are locked and idempotent;
closed reviews cannot move backwards. These commands do not remove content,
restrict accounts, send notifications or establish a review deadline. A submitted
reference is historical input, not verified ownership of a current username.

Verification: full default Unit/Feature suite on disposable PostgreSQL 18.7,
232 tests / 2197 assertions, with four explicit discovery capture/race/plan opt-ins
skipped. The route-cached run has the same result. Full SQLite suite: 232 tests /
2168 assertions, six skips, including PostgreSQL-only checks. The separate report
operator concurrency suite observes two real backend processes waiting at the
same row lock before release; duplicate starts, close-versus-start and duplicate
closures retain legal, idempotent histories. Malformed operator receipts now fail
validation before PostgreSQL can reject a UUID cast. The HTTP route already
rejected malformed receipt paths.

96 focused Flutter tests and focused analysis passed at the report checkpoint.
Normal-size light/dark English/Nepali history/detail pixels and narrow large-text
receipt/list/detail/timeline/error/empty layouts were inspected. Fixtures are
synthetic. These checks are not installed-device or deployed-service evidence.

Rollout remains held. Migrate and switch writers/capability coherently, then
verify against the deployed API and installed clients. A backend-independent
client upgrade does not make this server feature available. Durable submission
replay, report-context attachments, immutable target binding, an operator UI,
policy/staffing and enforcement remain separate work. No build, provider,
production data, moderation decision or notification was activated.

## November 23 client review checkpoint

Private client candidate on the df1b7ce baseline adds an explicit final review.
Selecting a reason no longer submits a report. The review shows the type,
selected profile name or post author/caption when available, the original target
reference and selected reason, with Cancel and Send report. Display context is
not transmitted as evidence and does not establish immutable server target
binding. Existing legacy submission and capability-gated receipts are unchanged.

The existing action owner also owns this second dialog. Cancel, system back,
same-member re-login, a covering route and retained/double callbacks cannot
bypass the explicit send or cause a second write. Existing cross-member and
pending-result retirement checks remain in the regression set.

117 synthetic Flutter tests passed across report review/history, member actions,
profile-menu ownership/recovery and post-card session behavior. The two new or
changed core files (actions and review fixtures) analyze without issues; the
broader four-file check retains three pre-existing informational lints in feed
and profile. A negative control removing the final review failed because a
write had occurred before confirmation. English/Nepali light/dark pixels at
320x640 with 180% text were inspected after reducing the overlarge title and
shortening redundant help. Content can scroll independently of action buttons.
This is source-only local validation, not a native build, live moderation report,
backend deployment, physical-device acceptance or app distribution.

Parent pixel review caught crowded Nepali send text in the first checkpoint;
that earlier visual acceptance is withdrawn. The revised button uses explicit
1.6 line height and 14px vertical padding. Readable context is primary and the
post UUID is now behind an expandable secondary Reference detail. Review tests
open/close that reference, then verify original-target submission. The four
updated narrow/large-text captures are the replacement visual evidence.

## November 23 private replay backend

Optional submission_id UUIDs are reporter scoped and normalized. The server
fingerprints the exact type, target, reason and nullable note. Replaying the same
payload returns the same receipt and current progress; a changed payload returns
409 without a new event. A nullable compound unique constraint plus serialized
reporter row lock prevents duplicate concurrent writes. PostgreSQL locks and
statements have bounded timeouts; a timed-out write does not retry automatically.
Legacy keyless requests retain prior behavior. The additive migration does not
assign keys to historical submissions. Capability is advertised only when both
columns exist. No client uses it yet at this backend checkpoint.

Cached and uncached full disposable suites: PHP8.4.27/PostgreSQL 267 tests,
2417 assertions, five explicit skips; SQLite 268/2420/six skips. Eight new replay
feature tests cover identical/rebound/cross-owner/current-status/normalization/
validation/distinct keys/transaction failure. Dedicated PostgreSQL18 processes
exercise actual row contention: three tests, 46 assertions cover duplicate,
conflicting and bounded held-lock retry. Removing the reporter row lock causes
an observed concurrent unique-constraint failure, restored code passes again.
No production migration, publication, provider action or build was run.

## Private client replay checkpoint

The client now uses replay only with both history and replay capabilities.
Before the first HTTP write it saves and reads back the submission UUID in the
existing secure-storage facility under an account-hashed key. An explicit retry
of the same type/target/reason reuses that UUID across store instances. It never
retries in the background or sends from another account. A verified matching
receipt clears only that intent; invalid or uncertain results retain it. Current
in-review/closed progress from a replay receipt is accepted without replacing it
with a fabricated received status. Storage errors or failed readback stop before
HTTP, and pending saves recheck route and session ownership before sending.
Legacy servers receive no unsupported key. Bounds: eight unresolved intents per
account, original references/reasons only, no credentials or content snapshots.

132 synthetic Flutter tests pass, focused analysis clean. Additional checks
cover new-instance persistence, independent account/payload keys, concurrent
prepare serialization, stale cleanup, storage bounds/corruption, uncertain HTTP
followed by same-key explicit retry/current receipt, legacy compatibility,
unreadable storage, same-login/other-identity changes while storage is pending,
and a lost write. These are storage-plugin mocks, not physical encrypted-storage
or process-kill acceptance. Eight EN/NE light/dark first-send/retry layouts at
320x640/180% text were rendered; retry copy was shortened after initial scroll
clipping. Nepali action padding from the parent review is preserved. Post caption
is a bounded preview; full UUID is optional secondary Reference. No published
source, app build, production migration or real report has been made.

Remaining limitations: no native encrypted-storage/restart proof, no pending
report recovery list when original content disappears, no cross-device retry
identity, and no immutable server subject binding. Existing retention and
moderation policy/staffing decisions remain unchanged. Do not deploy this whole
private tree as an unreviewed replacement for the bounded production overlay.

## Combined native acceptance preparation

Superseding the earlier checkpoint limitations: device-local pending recovery
now exists, including unreadable-storage and stale-refresh fail-closed behavior.
Capable member reports bind the reviewed immutable profile ID, reject a renamed
or reused handle before first acceptance, preserve the first receipt on exact
replay, and refuse client downgrade. Legacy/historical references stay unbound.
The final focused Flutter suite passes149 tests. Full cached/uncached backend
matrices pass SQLite270/2438 assertions/six skips and PostgreSQL269/2435/five
skips. Independent PostgreSQL18 race coverage passes5 tests/73 assertions.

The next native batch combines the existing full product journey with report
response loss after a real local commit, followed by same-installed-app process
termination and relaunch. It requires exact pending key/member restoration,
other-account isolation, Cancel/no-write, explicit same-key retry, one original
receipt and cleared local intent. Five report OS frames join the prior31
boundaries. Host process IDs, VM PID and unchanged app/data containers are checked.
All runtime/API tree pins are fixed in the reviewed workflow. No signed artifact,
store upload, production migration or live report is part of this validation.

Preparation checks are not native results: 4 synthetic host checks,22 screenshot
monitor checks,13 pixel-envelope checks,7 diagnostic checks, clean two-file
integration analysis, and actual isolated-loopback fault/replay contract passed.
Local device discovery exposes no Android/iOS device. Native plugin/restart
execution, physical Samsung/iPhone behavior and owner-phone delivery stay open.
The reference appearance/launcher decision remains separate and unapplied.

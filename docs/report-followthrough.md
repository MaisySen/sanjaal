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

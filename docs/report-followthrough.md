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

Verification: 25 SQLite API tests / 190 assertions; 96 focused Flutter tests;
clean focused analyzer and diff check. Normal-size light/dark English/Nepali
history/detail pixels and narrow large-text receipt/list/detail/timeline/error/
empty layouts inspected. Fixtures are synthetic, not installed-device evidence.
The new migration and operator status race have not been tested on PostgreSQL.

Rollout remains held. Migrate and switch writers/capability coherently, then
verify against the deployed API and installed clients. A backend-independent
client upgrade does not make this server feature available. Durable submission
replay, report-context attachments, immutable target binding, an operator UI,
policy/staffing and enforcement remain separate work. No build, provider,
production data, moderation decision or notification was activated.

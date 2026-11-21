# Account deletion: request plumbing, not rollout

Base product source: `a4b99e2385add30b159cd7edb3c04b827a387cb2`.

## What this change does

- Adds authenticated self-only GET/POST `/api/v1/auth/me/deletion`.
- Stores at most one request per member, with a public reference, requested status and the notices/policy version the member confirmed.
- Serializes creation on the member row. Retries return the same record, including when new intake has been disabled.
- Rejects another user ID, client-selected status or request ID. This endpoint cannot mark requests complete.
- Replaces the settings email launcher with an in-app confirmation/status page. A timeout or unknown POST result requires a status check before another submit.
- Retires the page on account/session change. Local interface text supports English and Nepali. Processing and retention notices are displayed as supplied, not silently translated or invented.
- Defaults intake OFF. No environment-only switch. `enabled`, `completion_mechanism_verified`, a policy version and nonempty processing/retention notices must all be set in reviewed source before intake can open.

A read-only `php artisan accounts:deletion-plan <existing-request-uuid>` command now returns member-scoped dependency counts and operational holds without personal content, provider calls or writes. It has no apply mode and always reports deletion not allowed and inventory incomplete. This is not a consistent database snapshot or exhaustive media inventory. Three additional planner tests pass (41 assertions), including a SQL listener requiring every planner query to be SELECT and HTTP fakes proving no provider calls.

There is no account deletion worker, remote identity deletion, data erasure, deployment or activation in this change. Request intake by itself does not satisfy completed account deletion. No real requests were submitted while developing it. Screenshots use synthetic notices explicitly identified as non-production.

## Why email is not the completion path

Apple requires apps supporting account creation to let people initiate account deletion inside the app. Apps outside highly regulated industries should not require email, phone or support flows. Manual completion can be allowed, but a reasonable processing period must be disclosed and completion confirmed. Whole-account associated data includes shared user-generated content, except legally required retention.

Checked official guidance: https://developer.apple.com/support/offering-account-deletion-in-your-app/

## Source-backed completion dependencies

1. **Stop identity resurrection.** `api/app/Auth/Auth0Guard.php::userFor` recreates a local member from a still-valid Auth0 identity when no matching local row exists. Local-row deletion alone is insufficient. Remote identity/session revocation and an appropriate anti-recreation rule need verified provider permissions and a reviewed retention basis for any tombstone. Sign in with Apple token revocation must be checked if that provider is enabled.
2. **Do not erase financial history by cascade.** User foreign keys on wallet entries, topups, withdrawals, gifts and transfer replay records currently cascade. Deleting the member could erase ledger/reconciliation evidence and affect the other side of a transfer. Real balances and outstanding transactions must be handled, not silently confiscated or refunded. Which fields must be retained, for how long and under which basis is not decided here.
3. **Shared conversations need deliberate handling.** `conversations.created_by` references users without cascading. Shared group ownership/member references must remain coherent while the departing member's personal content is removed. Do not delete other members' messages or whole groups by accident.
4. **Media is not a simple FK cascade.** Posts carry paths; chat and protected stories refer to media UUIDs; `media_blobs` has storage metadata without a direct member FK. External B2 keys, thumbnails, DB blobs and references must be inventoried before erase. Existing ownership/classification and same-object/reference protections must apply. No bucket-wide orphan sweep.
5. **Preserve anti-replay behavior.** `UploadIntent` uses durable receipts to stop delayed retries recreating removed content. Removing user-bound receipts or allowing old Auth0 tokens to recreate the member would defeat that boundary. Retaining identifiable replay data also needs a purpose/retention decision.
6. **Reconcile external/in-flight work.** Push tokens, calls/rooms, media uploads, pending transfer/topup/withdrawal operations and retry jobs need a deletion generation or equivalent fail-closed barrier before irreversible work begins. An existing account request is not such a barrier.
7. **Truthful completion evidence.** Only mark deletion complete after scoped storage/identity/data erasure and required retention handling are verified. Store minimal audit evidence, not copies of erased personal content. Confirm completion through a verified approved channel. Do not claim immediate deletion, a turnaround time, backup-erasure guarantee or retained-fields policy without a real process.

## Remaining owner/operational decisions

- Reviewed retention treatment for financial/reconciliation records and backup lifecycle, including what the person is told.
- A real completion operator or worker and an accurate processing notice. No staffing or turnaround commitment is invented.
- Provider identity/storage erasure capabilities and permissions, plus a completion confirmation route.

These remain rollout blockers, not reasons to stop implementing the independent source work. The frozen engineering artifact/source is not replaced by this branch.

## Local evidence

- Request controller + auth tests: 17 tests, 57 assertions, SQLite fixtures only. Not a PostgreSQL concurrency proof.
- New UI: 16 focused widget/renderer tests, including settings navigation, same-member reauthentication, English/Nepali, light/dark, 320px/1.5 text scale with routed back navigation. Actual screenshots inspected.
- No native/product build was run for this change. The branch is excluded from the general build workflow to avoid an unreviewed full build. There is no new secret-consuming or deployment workflow.

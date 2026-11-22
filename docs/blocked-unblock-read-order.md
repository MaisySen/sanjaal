# Blocked-list read/write ordering

Local source correction only, November 22, 2026. No real member blocked/unblocked, API deployment, signing, native build or distribution.

## Demonstrated race

The blocked-list screen correctly locked repeated Unblock actions, but manual refresh remained available during the pending DELETE. A refresh could start a pre-write GET, make the post-write reconciliation GET skip because loading was true, then publish the old blocked roster after the write succeeded. The negative synthetic test observed two reads where only the initial read should exist while DELETE is pending.

## Change

Refresh toolbar, read-failure Retry and the retained pull-refresh callback now wait while a moderation write is pending. The internal post-write read has a narrow afterChange flag so it can reconcile while preserving the mutation lock. Existing loading and session-active checks remain. Failure unlocks manual read recovery without inventing successful removal; reconciliation-read failure can retry without resending DELETE.

## Checks

Three new synthetic cases cover pending-write manual-refresh exclusion, write-failure unlock and read-failure recovery after successful write. Blocked recovery plus settings session boundary suite: 29 passed. Focused analyzer: no issues. Earlier negative fixture fails on pre-correction source as expected.

Inspected regenerated English/light and Nepali/dark retry pixels at 320x640 and 1.8 text scale: title, refresh affordance, error and Retry fit. This is a bounded unchanged-layout check, not native moderation or broad privacy acceptance. No new visual design introduced.

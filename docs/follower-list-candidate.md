# SJ-027 follower-list candidate

Local source-only preparation, November 22, 2026. Not deployed or enabled. No relationship data was read from a live account, no member relationship changed, and no native build, signing or distribution occurred.

## Product slice

When the server explicitly advertises `follow_lists`, Followers and Following counts on another member's profile and the own-profile tab open a read-only member list. Opening a row opens that member's profile; returning refreshes the list so a removed or blocked member can disappear. Opening a profile twice is guarded. There is no follow/unfollow mutation on this list.

The current server config is hardcoded false, not enabled by an environment variable. The current deployed API does not advertise the capability. Existing clients keep inert counts when it is absent. A directly constructed disabled list does not issue a request. Sign-out clears the capability.

The API returns at most 30 public member cards per page, using an encrypted cursor bound to the viewer, owner and direction. No raw numeric id, email, phone, authentication subject or relationship metadata is projected. Both directions of blocking filter rows before the page limit. A blocked owner returns 404. Deleted users are excluded through the join and normal foreign-key cleanup. Cursors are validated and cannot be moved between viewers, owners or list directions.

The UI uses lazy rows, explicit Load more, initial/refresh/page failure recovery, and empty states. Pagination failure puts Retry at the list end, near the failed action, while retaining existing rows. A malformed root, owner, direction, member, cursor or oversized page does not partially publish. Session identity/generation and immutable route target bind the page; old callbacks and late results cannot borrow a replacement login, even for the same member.

## Visual checks

English/light and Nepali/dark at 320x640 and 1.8 text scale: inspected loaded, empty and initial error views, plus routed Back and enabled profile entry. The first English profile capture split Followers into a final isolated letter. Changed large-text count layout to intrinsic-width wrapping and re-inspected the correction: the labels and counts align without that split. Normal-size counts keep the existing row layout. The pagination-error capture also shows the retry at list end. These are synthetic pixels, not device or design acceptance.

## Checks and limits

- 27 dedicated Flutter tests passed, including capability lifecycle, lazy rows, pagination retry, route return, session replacement, malformed responses (including wrong known owner id) and visual fixtures.
- Five new API tests cover default-off/authentication, direction/projection/deletion, block filtering, cursor binding/pagination and bounded query count. A broader selected API run passed 16 tests and 181 assertions, excluding the existing avatar test.
- The first broader API run was not green: 17 tests, one error because this local PHP runtime cannot load GD and the existing avatar test requires GD. This is not avatar acceptance and is not hidden by the later filtered run.
- Focused new-file analyzer is clean. Wider profile analyzer retains its pre-existing unnecessary-underscores info; no new runtime issue was reported there.

## Remaining gates

This slice does not implement private accounts, follower requests/removal, message requests or mention policies. A privacy/rollout decision must define which owners' relationship lists may be disclosed before activation. That decision is not inferred from existing counts. Production query-plan/index review for large follow graphs, enabled API/client integration, real blocked/deleted/resume reconciliation and physical-device acceptance remain open. Encrypted cursors require the normal configured Laravel application key. Existing list counts may include rows intentionally filtered from the permitted list; the UI does not promise equality.

No full-product completion, live enforcement or latency claim follows from these selected tests.

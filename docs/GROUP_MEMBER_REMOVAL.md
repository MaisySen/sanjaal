# Owner-only member removal

Candidate source, November 23, 2026. No backend rollout or activation.

Group info now opens Manage members independently of the ownership-handoff
capability. The current owner selects another stable member, reviews the group,
identity and consequences, then confirms. The returned snapshot must preserve
the owner and all other members while excluding exactly that selected member.
Unknown or malformed results require an explicit reload, not another blind write.
The sole remaining owner gets an explicit empty state and cannot remove themself.

`GROUP_MEMBER_REMOVAL_ENABLED` defaults to false. Advertising the capability also
requires the existing ownership-version migration. Keep it off pending the
matching client, migration and operational review. This adds no admin tier,
message-retention policy, deletion, provider activation or payment behavior.

Removal uses the same conversation-row lock and monotonic confirmation revision
as handoff/add/leave. Messages and media remain for continuing members. Reinviting
someone uses the existing fresh join boundary; their old message retry and reply
references cannot reveal earlier history.

The message poll waits without holding the membership lock or fetching bodies.
Its final read holds a shared conversation lock, rechecks membership and reads the
current join boundary. Two real PostgreSQL regression checks fail with the old
read method: a revoked waiting request returns 200, and a removed/reinvited request
returns a message sent during its absence. Both pass with the new final read.
This does not recall already received copies or promise revocation of activity
metadata from an already subscribed socket.

The client treats a group access 404 as an unavailable view. It stops polling,
retained send/retry/record/call actions and typing. Already shown text remains
selectable; unsent composer text remains available read-only. No automatic rejoin
or draft deletion occurs. A hidden completion cannot dismiss another route's
keyboard. The unavailable view scrolls at large text sizes with a keyboard.

Verification: API default suites, SQLite 252 tests / 2317 assertions / 6 skips;
isolated PostgreSQL 252 / 2346 / 4. The dedicated ownership/removal suite passes
28 / 273, including six independent-worker row-contention cases and two paused
poll revocation/rejoin checks. Flutter has 503 passes across 21 selected files,
including 18 removal tests, not a full current 177-file sweep. Actual fixture
pixels for selection, success, unavailable/draft preservation and EN/NE large-text
confirmation were inspected. No native-language or native/device acceptance is
claimed. The successful native run at824119b predates both group features.

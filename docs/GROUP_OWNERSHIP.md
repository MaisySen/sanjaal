# Explicit group ownership handoff

Candidate source, November 23, 2026. No backend rollout or feature activation.

An existing owner can open Group info, choose Group ownership, select another
current member and confirm the handoff. Both remain members. The new owner gets
the existing rename authority; the former owner loses it. This is not member
removal, an admin tier, account deletion or a change to message retention.

## Availability and safety

- `GROUP_OWNERSHIP_ENABLED` defaults to false. The authenticated capability also
  requires the `ownership_version` migration. Keep it off pending the matching
  client, migration and operational review.
- A dedicated membership-checked read avoids relying on the inbox window.
- Each confirmation binds the group, current identities, membership, roles and
  monotonic ownership version. The server rechecks owner authority under the
  same conversation-row lock used by membership changes.
- Both role updates must affect one row or the transaction rolls back. An
  ownership round trip cannot revive an old confirmation.
- Membership, messages, history boundaries and personal chat settings remain.
- The client validates the returned successor and membership before showing
  success. A failed or malformed acknowledgement requires an explicit reload,
  not another blind transfer. Group info refreshes the role before restoring
  its rename action.
- Covered routes, old reads, replacement sessions and a changed group cannot
  reuse a retained confirmation. A pending write blocks Back until its bounded
  request ends. Older servers have no ownership entry or dead reload action.

## Initial feature checkpoint

- API default suites: SQLite 242 tests, 2239 assertions, 6 skips; isolated
  PostgreSQL 18, 242 tests, 2268 assertions, 4 skips.
- Dedicated PostgreSQL feature and contention suite: 13 tests, 121 assertions.
  Both independent worker backends were observed waiting on the same row before
  release. Cases cover competing successors, target leave and original-owner
  leave. The fixture checks its actual disposable server directory before reset.
- Flutter: 485 passes across 20 selected group, chat, session and render files,
  including 16 ownership tests. This is not a full current 176-file sweep.
- Inspected actual fixture pixels for the normal phone page and success state,
  plus English/Nepali 320x640 large-text confirmations. All consequences and
  both confirmation actions are readable. This is not native/device evidence
  or a native-language review.

The successful iOS run at `824119b` predates this feature and does not verify it.
No isolated build or push was made for this change. Signing, phone installation,
production behavior and the wider product delivery remain separate work.

## Coherent batch review

The current frontend sweep covers 177 unique top-level test files with 2485
passes and 10 explicit skips, frozen at runtime tree
`cc9b261b25956923a1d8c4e0fde25d9780de5aeb`. Confirmed receipts also carry the
current title, membership and role back into the chat, including when the
parent's follow-up read is still pending. The held-read handoff/reopen regression
fails before that correction and passes afterward.

Native first-use input/validation and group creation/removal/handoff/history
coverage is prepared and compiles. First-use validation submits no provider
signup, sign-in or reset request. Actual native execution of this batch is still
pending at this checkpoint. The standalone analyzer was not verified after its
timeout; compiler and widget results do not replace native execution.

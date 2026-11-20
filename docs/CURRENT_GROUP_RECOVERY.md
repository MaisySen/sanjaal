# Exact current-product saved-group recovery

This isolated branch exercises the combined7f98487 application without changing
app/lib, app/android or app/ios. Earlier group Save/process-restart evidence was
on older product source. The fixture uses the real New group, search/selection
and Save controls with synthetic search replies, then simulates a lost creation
reply after verifying the native attempted marker was written.

Each native runner installs once, terminates the seed process, starts another
process without clearing data, and verifies the recovered exact title/member
identity/attempt marker, other-account isolation, blocked re-create and explicit
Keep/Delete. All API behavior is a local test double; no actual group, invitation,
message or production request occurs. Both native results and actual captures
need inspection. A green build alone is not physical acceptance, server replay
implementation or distribution.

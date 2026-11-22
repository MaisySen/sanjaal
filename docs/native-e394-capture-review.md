# Native capture review, November23

Exact e394 native run45066782995 failed at the post-input native display boundary.
The host simctl screenshot process timed out twice at20seconds. A prior real
keyboard capture recovered on its second attempt, about39seconds after request.
Five tab capture acknowledgements preceded the failure, but their PNGs were not
in the old15-name export list, so their pixels cannot be accepted retrospectively.
No text-input UI assertion failure or app crash is established by these records.
https://github.com/MaisySen/sanjaal/actions/runs/45066782995

The next test-only correction budgets two45second host attempts and a120second
application-side acknowledgement deadline. It retains process-group killing,
reaping, fresh attempt paths, request identity, fail-closed acknowledgement and
the overall driver/job bounds. This is a bounded timing experiment, not a proven
fix to the unknown simulator-host stall. Runtime app/lib is unchanged.

The exporter now names all31 current intended journey boundaries, including
five tabs, video poster, post/status/upload/chat/rooms and group/device views.
A source parity test prevents silently omitted journey names. Total encoded
source-PNG budget is24MiB; per-image remains4MiB and packets24000bytes.
No private account or provider data is admitted by the disposable fixture.

Local review:13packet/export tests,22capture-monitor tests,5Dart barrier tests
passed. Focused Dart analysis reports no issues. These are harness checks, not
native success, provider/device acceptance, signing or phone delivery.

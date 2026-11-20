# Long call-status containment

Independent full-app review found CallView renders unbounded service/permission
status text above an Expanded media region and fixed controls. Long messages at
small dimensions/large text can consume the available height, causing overflow
and hiding the End control. This candidate gives status a bounded, scrollable
share while retaining all text, video space and fixed call controls. It changes
no microphone, camera, room, network or permission behavior.

The changed-source regression uses the actual CallView with synthetic long
errors, small portrait and landscape dimensions, 1.8x text, English/Nepali
content, a reachable/tappable End control and scrolling to the final error line.
A negative control restores the old unbounded layout and must fail the same
regression. Actual rendered pixels and complete tests are required before
acceptance. No real call, camera, microphone or distribution action is involved.

Candidate647295f passed66 focused tests and1132 whole-suite tests with one
opt-in live skip. The old-source negative control reproduced514pixels of
RenderFlex overflow; restored source passed8/8cases. All eight actual renders
were inspected, including both landscape modes and full final error line with
reachable End. This is offline layout evidence, not actual-call/device proof.
https://github.com/MaisySen/sanjaal/actions/runs/44686021900

Visual follow-up: light-theme disabled microphone/camera icons inherited dark
colors on the fixed dark call bar. The overflow result stands, but whole visual
acceptance was withheld. Explicit white54 disabled foreground and a state-style
assertion now require these controls to remain visible without enabling them.
Updated renders must be inspected before acceptance.

3fc9ee2 stopped in the new style test: material_ui's tooltip finder resolves
the RawTooltip wrapper, not IconButton. The assertion now selects IconButton
by its tooltip property directly. No product behavior or contrast color changed.

Corrected478d7c8 passes66 focused,1132 full/one live-only skip, old-layout
514pixel overflow negative and8/8restored. All eight updated images inspected:
light-theme disabled camera/microphone now remain visible in white54, End stays
readable/reachable and the final error line scrolls fully into view.
https://github.com/MaisySen/sanjaal/actions/runs/44689259582

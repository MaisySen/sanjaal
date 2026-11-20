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

Visual follow-up: light-theme disabled microphone/camera icons inherited dark
colors on the fixed dark call bar. The overflow result stands, but whole visual
acceptance was withheld. Explicit white54 disabled foreground and a state-style
assertion now require these controls to remain visible without enabling them.
Updated renders must be inspected before acceptance.

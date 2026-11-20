# Media safety language and exit coverage

CallView and RoomView previously rendered fixed safety status strings directly,
leaving capture-uncertainty warnings in English even with the app set to Nepali.
Call microphone/camera accessibility labels bypassed translation too.

Both views now use the existing translation path. Fixed call connection and
capture warnings, camera/microphone labels and camera-preview semantics have
Nepali entries. Unknown service text is unchanged, not discarded or reinterpreted.
This is presentation only, with no change to capture, signaling or terminal guards.

Actual prefs.lang en/ne tests render the exact call/room safety warning at
320x640 and 640x320, light/dark, text scale1.8. They require the language-specific
message, complete scrollable text, visible reachable End/Back, disabled or absent
media controls, and actual route exit without a capture toggle. Separate coverage
checks known fixed labels and preserves an unknown service detail.

Historical cb3093d CallView and RoomView sources must each fail the Nepali-warning
regression; restored sources must pass before the whole suite. Actual screenshot
inspection remains required. Coverage and glyph rendering do not replace native
Nepali editorial review. No real call, room, hardware or network is involved.

Initial candidate747e44c passed85focused/1175full(one live-only skip),17restored
and both historical negatives. Initial16 images were inspected; Nepali call
warning at bottom scroll clips its first line as expected for scrollable text,
but the initial/top visual state was not captured. Follow-up adds explicit
initial top-position and final bottom-position geometry checks and separate
captures for every variant. No simultaneous whole-paragraph visibility claim.
https://github.com/MaisySen/sanjaal/actions/runs/44706833913

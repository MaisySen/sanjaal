# Direct-call media failure containment

A failed native microphone/camera toggle acknowledgment can leave capture state
unknown. Previously CallPage displayed a temporary error and unlocked controls.

CallMediaGuard now blocks parallel changes and latches a terminal failure before
awaiting independent microphone-off, camera-off and disconnect attempts. Failure
of one cleanup operation does not skip the rest, and no later toggle is allowed.
CallPage marks the call failed, sends its existing scoped end action, preserves
its persistent warning and reachable End control, and does not claim that a
native stop succeeded. Session retirement cannot publish a late success. Existing
release ordering waits for the outstanding change before final room disposal.

Adapter tests cover success, cleanup failures independently and together, original
error preservation, a slow stop blocking another change, and owner retirement.
Mutation controls remove cleanup or remove the terminal latch and must fail the
regressions. These are mutation controls, not execution of the historical page.
Exact warning renders cover 320x640 and 640x320, light/dark at text scale 1.8.

This does not prove hardware capture stopped, LiveKit behavior, a real call, or
production signaling. No new distribution, production operation or money path.

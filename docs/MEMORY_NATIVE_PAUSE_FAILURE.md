# Android recovered-video pause containment

Source audit after e453 found that the Android adapter swallowed a MediaPlayer
pause exception, so Dart channel-error containment could not see that exception.
Pause failure now latches native failure, hides the surface and independently
attempts listener removal, player release, display release and byte-source
clearing. Failure of one cleanup no longer skips the others. Late prepared or
completion callbacks cannot revive a failed or detached player.

The native-adapter harness compiles the actual production Kotlin file against
small deterministic Android/Flutter fakes. Nine cases cover ordinary explicit
controls/disposal, channel and lifecycle pause exceptions, five independent
cleanup exceptions and a late prepared callback. Historical e453 pause and cleanup
negative controls and a missing late-callback guard mutation must fail on the
specific assertion. These are adapter ordering tests, not decoder, physical
shutdown, or secure-erasure proof. Exact-source Android emulator recovery is a
separate workflow job. Flutter full/channel tests run independently. No iOS
native source changes, production writes, upload, release or wallet change.

Isolated b1721d7 passed both workflows, adapter9/restored9 and all3 intended
negatives, Flutter64focused/1182full (one live-only skip)/13restored.
Exact-source Android restart passed;9captures inspected, single install/same
package path/UID10192 across confirmed force-stop without clearing. Seed still
is splash, not visual seed proof. Route return is paused0:03. Combined checks
remain separate until their exact-head run completes.
https://github.com/MaisySen/sanjaal/actions/runs/44718815336
https://github.com/MaisySen/sanjaal/actions/runs/44718815170

## Allocation and prepare callback follow-up

A second source audit found assignment after MediaPlayer configuration, leaving
cleanup without ownership when configuration throws. The allocation is now owned
before any setter or preparation call. Prepared callback fit/seek exceptions
retire the player rather than escaping that callback. Seven additional actual
production-adapter cases inject six setup exceptions and a prepared seek failure.
The earlier nine cases and three negative controls remain. Exact5fe historical
setup and prepared-callback negatives fail on missing release and escaped seek
exception. Local protected/restored16 pass, five specific negatives reproduced.
No real native-fault injection, physical shutdown or erasure claim. Actual decoder
restart and Flutter integration verification remain separate CI checks.

Isolatede2c310b CI passed native16/restored16 and5specific negative controls,
Flutter64focused/1182full (one live-only skip)/13restored. Exact Android restart
passed,9images inspected; sameUID10192/package path across confirmed force-stop,
single install/no clear. Route return paused0:02, seed still splash. This is
separate from subsequent combined/current-head verification.
https://github.com/MaisySen/sanjaal/actions/runs/44723655963
https://github.com/MaisySen/sanjaal/actions/runs/44723655787

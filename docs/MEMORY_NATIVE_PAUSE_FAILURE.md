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

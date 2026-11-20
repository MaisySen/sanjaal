# Native pause wall-clock evidence

20November2026. Acceptance-test improvement only, no production player changes.

The earlier native recovered-video integration test advanced Flutter test time by800ms and checked the displayed position. That was useful for widget state, but did not guarantee a corresponding interval of real native-decoder time. Do not describe that assertion as a measured800ms native pause interval.

The revised fixture keeps polling while at least1600ms of actual elapsed time passes through real asynchronous waits. Post manual pause, story manual pause and post covered-route return must keep their displayed clock fixed with Play available and Pause absent. The20-second synthetic fixture must still be before17seconds when measurement starts, so reaching its natural end cannot satisfy this check. Native playback must already have advanced before these pause checks.

The same one-install/two-process encrypted-draft recovery, frame-color gate, package/container/PID checks, uncertain-send locks, no API calls and session-retirement checks remain. The screenshots still show native frames, not proof of hardware shutdown, audio silence or decoder-memory erasure. Display-clock stability is not a sub-second latency benchmark.

Exact Android and iOS runs and their current logs must be reviewed before treating this test change as verified. The combined5280d57 checkpoint is being checked independently.

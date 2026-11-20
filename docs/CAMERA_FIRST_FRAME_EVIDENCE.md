# Initial Android camera display evidence

The bd595eb emulator camera screenshot was black inside the camera preview even though its photo pixel checks, later recording, and extracted poster passed. Those later checks do not prove the initial preview was visible. This is a test-evidence gap, not an established device-camera bug.

The isolated native-camera-first-frame check samples the central display region from the actual adb screencap before accepting the camera screenshot or tapping the shutter. It allows at most twelve attempts, with real 300 ms waits and Flutter frame pumps. A dark or low-variation display fails explicitly. It never retries a recording, upload, or user action. The fixed authenticated CI bridge returns PNG bytes only for its camera fixture action.

This is an emulator readiness check, not a camera latency benchmark, hardware test, Samsung acceptance, or production proof. The prior black frame remains part of the prior run evidence.

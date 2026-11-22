# Device access, source candidate

Settings search and Your app and media open the shared reviewed Device access
screen. Native Android reads current camera/microphone grants and separate media
permissions for pre-33, 33 and selected-access 34+ devices. iOS reads AVFoundation
authorization and read/write Photos authorization, including limited access.
No permission prompt, capture, library enumeration or network request is made.

Open device settings is explicit. Returning to the foreground re-reads current
grants; states are not persisted. Loading/error states never invent permission.
Session replacement retires pending reads. Read/settings failures remain
recoverable. Permission is not hardware, recording or playback verification.

111 combined report/device/settings/member-action Flutter tests pass, including
15 new bridge/parser/navigation/resume/failure/session/layout cases. Focused
analyzer and diff check are clean. English/Nepali normal and large-text fixture
pixels inspected. These are mocked-native/widget checks, not native execution.

The Android DeviceAccessChannel class now passes a targeted Kotlin 1.9.24 compile
against official Android API 36 revision 2 and Flutter engine
371f77202a73e8dff57a8b3bff75bca55c090aee. This is an API/signature check, not a
Gradle application build, MainActivity integration or permission execution proof.
The coherent iOS simulator run at immutable source
824119bae97ca82e271865e31fe6e6323765fd74 passed:
https://github.com/MaisySen/sanjaal/actions/runs/45026094286 . It compiled the
actual simulator app and exercised Settings search, the real permission channel,
matching displayed states, native host screenshot and Back. On this fresh
simulator all three displayed permission rows were Not requested. Reconstructed
native PNGs were checked against every packet, size and SHA256, then visually
inspected. The screen and settings action fit and were readable. Home, Settings
and a chat with the actual iOS keyboard were also inspected. This is synthetic
local-API simulator evidence, not an installed-device or production-service result.

The frozen app/lib tree a4d991ef9c996d75b6dc0f193d628da3cd7bbe2d also passed
all 175 top-level Flutter test files in successful bounded batches: 2447 passes,
10 explicit opt-in/renderer skips. This is regression coverage, not latency proof.

Granted/denied/limited permission matrices, actual OS-settings opening and return,
Android application integration and physical-device hardware still need matching
validation. No new app dependency, manifest permission, deployment or installable
release was introduced. The native workflow uses the standard public macOS
runner with no artifact upload or cache export. Its native frame log packets are
evidence transport only, not a phone-delivery artifact. This checkpoint does not
close installed-device acceptance.

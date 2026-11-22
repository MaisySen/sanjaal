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
The coherent iOS simulator flow now includes Settings search, the real permission
channel and matching on-screen states, but that added flow has not run yet.

Full native compilation, actual permission-state comparisons, limited-selection
behavior and OS-settings return still need matching native validation. No new
app dependency, manifest permission, deployment or installable build was
introduced. This source checkpoint does not close installed-device acceptance.

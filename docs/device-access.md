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

Android and iOS channel compilation, actual permission-state comparisons,
limited-selection behavior and OS-settings return still need matching native
validation. No new SDK dependency, manifest permission, deployment or build was
introduced. This source checkpoint does not close installed-device acceptance.

# Native preview state reply containment

20 November2026. Defensive protocol handling, not a claim that malformed replies were observed on a real device.

The previous Dart preview ignored a null reply after the native state call completed. After readiness, the startup deadline had been cancelled, so a series of null replies could leave stale playback controls indefinitely. Missing boolean state could also leave an indeterminate preview. Channel timeouts and thrown errors were already contained, but did not cover these successful malformed replies.

The preview now retires its native view, stops polling and shows the existing honest fallback when a state reply is null, lacks the required booleans, or has missing/non-finite/negative numeric position or dimensions. The selected encrypted draft remains selected. No upload, disk plaintext, autoplay or new account access is added. Native disposal remains best-effort, not proof of hardware shutdown or secure erasure.

Sixteen fake-channel tests cover eight malformed shapes before and after readiness. Late well-formed responses cannot recreate the retired view. A negative control replaces only the Dart implementation with exact42109dc and requires the null-after-readiness regression to fail for its intended missing-dispose assertion. The existing swallowed-channel negative, restored tests and full app suite remain.

Acceptance still requires exact-candidate Android/iOS native regression and the separate physical Samsung/real-device gates. This document is a test plan until the corresponding logs are reviewed.

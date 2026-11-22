# Optional profile setup

Local source candidate for SJ-016. No live registration, profile write, permission request, build, installation or distribution was performed.

A newly registered account receives an optional profile step only after its automatic sign-in and current account read succeed. Continue opens the existing main app without saving profile data or requesting camera/library access. Add a name or photo opens the existing EditProfilePage. Its explicit Save uses the normal profile API; cancelling preserves the offer. Saving does not force completion or prevent Continue.

The offer belongs to the registration's signed-in session generation. Logout, replacement sign-in (including the same member), failed registration and failed automatic sign-in cannot borrow or resurrect an earlier offer. Retained callbacks cannot finish a newer registration's offer. Existing sign-in and credential restore do not create an offer. This is an ephemeral convenience step, not persisted onboarding enforcement: closing and restoring the app can bypass it. Profile editing remains available later.

English and Nepali copy is present. A fixed safe-area Continue action remains visible while explanatory content scrolls. Inspected actual synthetic captures at 320x640 logical size and 1.8 text in English/light and Nepali/dark, before and after scrolling, and the normal-size connected registration capture. Both actions are readable and reachable. This is widget-render evidence, not native/device or linguistic acceptance.

The local sequential auth/entry/connected first-use group passed 69 tests. It includes 12 new setup cases and 7 registration-session cases, overlapping the dedicated 19-test run. The connected synthetic journey now registers, sees the optional step, continues, creates a post, finds and follows a member, chats, edits profile and returns home. Focused analyzer over the five changed behavioral/test files is clean. Whole-app analyzer reports 196 informational lints, no errors or warnings; it is not a clean whole-app analyzer claim.

The setup fixture deliberately forwards non-GET account requests, so zero-write assertions cannot be made green by swallowing PATCH. One earlier save-fixture failure and the connected journey's obsolete direct-to-feed expectation were corrected before the passing runs. These tests use mocked HTTP, storage and platform channels. Provider signup, actual media selection/upload and physical-device acceptance remain open.

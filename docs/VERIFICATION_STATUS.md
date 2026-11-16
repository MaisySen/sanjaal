# Verification status

Last updated Nov 16 2026. Publisher: Fintex Australia Pty Ltd, ABN 60 688 406 108, contact@fintex.au.

The emulator CI job runs against a local fixture API with a synthetic member. It is not live evidence and not a physical device.

| Flow | Status | Evidence |
| --- | --- | --- |
| App launch, signed-in feed, profile | Passes on emulator (fixture) | emulator CI |
| Like tap | Passes on emulator (fixture) | emulator CI |
| Rooms list screen, wallet screen | Passes on emulator (fixture) | emulator CI |
| Compose post (typing) | FAILING, unresolved | "Found 0 widgets with type TextField", cause unknown |
| Start a chat and send (typing) | FAILING, unresolved | same finder error |
| Room join, audio, token flow in the app | Not verified | LiveKit transport only checked with two synthetic clients, not the app |
| Push delivery | Not built live, not verified | sender is server-side code only, no credentials deployed |
| Dark mode | Not captured on a device | |

The emulator job is no longer marked continue-on-error, so a failing flows test shows as a failed job. Do not read a green run as proof of the failing flows above.

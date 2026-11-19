# Isolated room and saved-draft corrections

November 19, 2026, source verification only. This does not replace the exact Samsung acceptance record or authorize release.

## Room join ownership and cleanup

Source `334ac63cd04d8629f418f6fb119d7ab2f5f50ad0` checks page ownership before token acquisition, native connection and host microphone setup. Leaving during a pending token request cannot start a late native connection. Native disconnect/disposal is ordered after any already-started setup operation. A failed setup also stops the microphone and disconnects, even if microphone teardown fails.

Exact focused verification: https://github.com/MaisySen/sanjaal/actions/runs/44495738110

- Analyzer: no issues.
- 46 room/call lifecycle and presentation tests pass.
- Negative control removes the after-token ownership guard. The delayed-token regression then fails because native connect runs after closure. Restored production source passes all 11 room lifecycle tests.
- Unsigned iOS release compilation passes. This is not signing, installation, real microphone/camera behavior, background incoming calls or two-device audio proof.

## Revision-bound local draft deletion

Source `a9a05ae` requires the saved revision before deleting a local text/poll draft. An older Delete confirmation cannot erase a newer saved copy. The list reloads the preserved newer copy and shows a recovery notice. Media drafts and automatic upload continuation are not added.

Exact focused verification: https://github.com/MaisySen/sanjaal/actions/runs/44496496723

- 22 focused storage/widget/render tests pass.
- Negative control disables the delete revision check. The stale-delete regression fails as expected; restored source passes all 22 tests again.
- Light/dark English/Nepali recovery renders at 320 logical pixels and 1.6x text were inspected. The notice, preserved draft and deletion control remain readable.
- Storage is mocked. These are not native Keychain/Keystore restart, process-death or hardware proofs.

## Combined source validation

Combined source `810b7c97db9187d8fbd5a8f6c2d082d3b4ad5350` fixes the two native fixture cleanup callers to pass their saved revision. Exact whole-app run: https://github.com/MaisySen/sanjaal/actions/runs/44499154832 . 932 tests pass with one intentional opt-in live skip. Analyzer has zero errors/warnings and 87 informational notices. The earlier combined run found those fixture omissions and was corrected before this run. Focused counts must not be added to whole-suite totals.

## Multipart session ownership

Source `7bc0664e9b2a30923fef4f11bc926d868fe0f8f9` checks the session generation before token/send and after response for post, upload and avatar mutations. Progress from a superseded session is ignored. A delayed old avatar response cannot replace the next session's user.

Exact whole-app run: https://github.com/MaisySen/sanjaal/actions/runs/44500230484 . 945 tests pass with one intentional opt-in live skip, zero analyzer errors/warnings and 87 informational notices. A negative control removing the avatar response generation guard fails as expected; restoring it passes all 13 focused cases.

Workflow-only source `ca37a02c043d0aaf549242126871ef037f7f3654` has byte-identical app runtime and passes unsigned iOS release compilation: https://github.com/MaisySen/sanjaal/actions/runs/44501123048 . This is not signing, installation or device behavior proof.

## Private media session ownership

Source `de35f056177d3967f3e9fd4aa9913904864e63b7` checks session generation when acquiring private media headers and returning downloaded chat bytes. Checking account ID alone did not reject a delayed response after signing into the same account again. Seven focused cases cover chat/protected-story bytes after logout, another account, same-account new login, and a superseded token/header wait.

Exact whole-app run: https://github.com/MaisySen/sanjaal/actions/runs/44502888171 . The missing after-response generation guard makes the same-account delayed-byte regression fail; restoring source passes all seven focused cases. Whole-app: 952 pass with one intentional opt-in live skip. Analyzer: zero errors/warnings and 87 informational notices. Results are preserved in the run artifact. Native compilation of this newest runtime is a separate required checkpoint, not inferred from the earlier ca37 run.

## Immediate local sign-out boundary

Source `82bf84f5855901fd7e9305db6a4d90ecafb125f1` clears local identity and advances the session generation before waiting for notification server/device cleanup. Delayed private bytes are rejected during that cleanup. Late cleanup cannot clear a replacement login. The fixed old-token device-removal callback does not refresh credentials, follow redirects or read the new session's credentials. Local device invalidation is attempted even if server removal fails.

Exact whole-app run: https://github.com/MaisySen/sanjaal/actions/runs/44504302962 . 961 tests pass with one intentional opt-in live skip. Analyzer has zero errors/warnings and 87 informational notices. A negative control awaiting notification cleanup before local clear fails with the identity still present. Restoring source passes all 27 sign-out and push-registration cases. These are synthetic HTTP/storage/device callbacks, not FCM delivery or hardware sign-out proof. Native compilation of this runtime is a separate checkpoint.

The Samsung remains on the separately installed exact `0.5.6 (2011)` candidate. Neither correction has been installed there or accepted on a device. No API deployment, production room, real user-draft mutation, paid service, wallet activation, store upload or public release is part of this source batch.

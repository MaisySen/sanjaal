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

The integration branch combines only these corrections above `7d1107629a7d912c8fb8edf2d1e9065a8ee42583`. Whole-app Flutter regression is required after combination. Focused counts must not be added to whole-suite totals.

The Samsung remains on the separately installed exact `0.5.6 (2011)` candidate. Neither correction has been installed there or accepted on a device. No API deployment, production room, real user-draft mutation, paid service, wallet activation, store upload or public release is part of this source batch.

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

Exact whole-app run: https://github.com/MaisySen/sanjaal/actions/runs/44504302962 . 961 tests pass with one intentional opt-in live skip. Analyzer has zero errors/warnings and 87 informational notices. A negative control awaiting notification cleanup before local clear fails with the identity still present. Restoring source passes all 27 sign-out and push-registration cases. These are synthetic HTTP/storage/device callbacks, not FCM delivery or hardware sign-out proof. Workflow/docs-only source `5464a9f4d02d5f8ce663e932bf729def38da352d` passes Android debug compilation and unsigned iOS release compilation: https://github.com/MaisySen/sanjaal/actions/runs/44505286136 . App runtime, iOS, Android and pubspec files are byte-identical to 82bf84f. This is not signing, installation or device proof. The earlier private-media-only runtime also compiled unsigned for iOS: https://github.com/MaisySen/sanjaal/actions/runs/44503936650 .

A separate whole-pipeline validation branch runs existing local API/Postgres concurrency fixtures, app/finalizer contracts, Android release and bundle compile, Android emulator fixture drivers and unsigned iOS compile. A pass on that branch must be recorded from its exact run, not inferred here. No stable-key signing or distribution is requested.

## Upload uncertainty marker ownership and native persistence

Source `07c8f13b3293018bc31adea4e204fdba43952f4f` binds marker deletion to an expected ID and serializes writes/clears per account across store instances. A new marker cannot overwrite an unresolved different one. Exact run: https://github.com/MaisySen/sanjaal/actions/runs/44511720206 . Whole app 966 pass, one opt-in live skip; analyzer zero errors/warnings, 88 info. Removing expected-ID checking fails the stale-clear regression; restored 34 focused upload/store tests pass.

Source `9c9fef1562eda39ac8e4066139d74d1d57720ee4` binds UploadCenter generation to the Session generation as well as account identity. Pending preparation cannot use a replacement same-member login. Exact run: https://github.com/MaisySen/sanjaal/actions/runs/44513221500 . Whole app 969 pass, one opt-in live skip; analyzer zero errors/warnings, 88 info. Negative control fails; restored 37 focused upload/store tests pass.

Native Android emulator evidence `fffe8d60ffdf81c332875ba655816c7d5e839130`: https://github.com/MaisySen/sanjaal/actions/runs/44516747249 . The actual secure-storage plugin wrote and read a random run-specific synthetic marker. A force-stop left no app PID. The same installed binary was relaunched without uninstall, rebuild or clear, with identical UID/package path; the new process retained the exact marker. Recovery paused uploads and exposed no retry. Cancel preserved the marker, explicit Discard cleared it, zero request closures ran. Three native screenshots were inspected. This is durable uncertainty-marker proof, not persisted media jobs, automatic resume, Samsung acceptance or iOS persistence.

The first native experiment rebuilt/reinstalled between phases and returned null, so it is not valid same-installed-binary process-death evidence. The next harness stopped on a brittle UID parser before restart. Neither failed harness is counted as native recovery proof or a confirmed app-storage defect.

The preceding full integrated pipeline at `5d0cebd09801d67265e2fc47ef0936685541514b` passed all seven required jobs, including five Android emulator drivers and 28 inspected native PNGs: https://github.com/MaisySen/sanjaal/actions/runs/44507020036 . It predates these marker/generation changes. A new whole-pipeline run must independently validate this runtime before combining that earlier evidence with it.

The Samsung remains on the separately installed exact `0.5.6 (2011)` candidate. Neither correction has been installed there or accepted on a device. No API deployment, production room, real user-draft mutation, paid service, wallet activation, store upload or public release is part of this source batch.

## Exact integrated and visual follow-through

The marker/generation runtime completed all seven required full-pipeline jobs at `3b39b36f19f8ae5b22b5112d7ea88ab36ecb178f`: https://github.com/MaisySen/sanjaal/actions/runs/44518820649 . Actual whole-app 969 pass, one intentional live skip, analyzer zero errors/warnings and 88 info. Android release/bundle, unsigned iOS package, disposable API/Postgres fixtures, finalizers and five emulator drivers passed. Release and preview publishing skipped.

Three of that run's 28 captures were transient rather than settled visual proof: composer enabled label, wallet loading, lost-reply strip. Harness-only `7605cb172396db27b72ce1d13455e49fc7416ccb` adds enabled-button checking and settled rendering waits. Its five emulator drivers pass: https://github.com/MaisySen/sanjaal/actions/runs/44522528554 . The three actual PNGs were inspected: Post label visible, wallet loaded with disabled money controls, and the lost reply showing Try again and Details. Runtime/native/pubspec files are unchanged from 3b39. This does not establish physical-device retry or production latency.

## Discard-confirmation ownership

Source `da353c245339e342c11f242a47492ba4dda2ebaf` binds a pending upload Discard dialog to both its original session generation and marker ID. An old confirmation cannot clear a newly recovered or replacement warning. A fresh confirmation still works. Exact whole-app run: https://github.com/MaisySen/sanjaal/actions/runs/44527422952 . Actual 971 pass, one intentional live skip; analyzer zero errors/warnings and 88 info. Removing the snapshot guard fails both adversarial widget cases; restored 39 focused upload/store cases pass. This is synthetic widget/storage evidence. A new full integrated run is required for this runtime, not inferred from 3b39.

## Overnight iOS native evidence, November 20

Integrated `4801171d2f6e76c7f7ce21dd916b17ddb8419933` passed all seven required jobs: https://github.com/MaisySen/sanjaal/actions/runs/44529118659 . Whole app 971 pass, one live skip, zero analyzer errors/warnings and 88 info. Its 28 Android native PNGs were inspected, including settled Post label, disabled wallet and lost-reply retry. No distribution or production requests.

iOS simulator flow source `507ef2cfcfb52b85629c5a511a14b65ad8c59a2e` passed: https://github.com/MaisySen/sanjaal/actions/runs/44548201339 . Runtime/native/pubspec byte-identical to 4801171. Direct simulator launch and existing-app VM attach replace a failing log-reader startup discovery path. Suite-owned semantics initializes before per-test baseline and disposes afterward; leak assertions remain intact. Actual Keychain migration/clear, local text-draft owner isolation, session restore, AVFoundation synthetic video/poster, five tabs, post, server-confirmed local chat, empty Rooms and Settings passed. Fifteen synchronized actual OS screenshots were inspected. The first composer keyboard has iOS onboarding overlay, not a clean composer keyboard proof. Prior failed input/semantics runs remain failed and are not counted as acceptance.

iOS uncertainty-marker restart source `53fa7135fc278197fe3857c00f6f8bd1fff1cb2e` passed: https://github.com/MaisySen/sanjaal/actions/runs/44560054946 . One install, identical app/data paths, observed seed PID 22790 terminated and verified absent, recovery PID 25216. Actual Keychain retained the exact random marker; recovery pauses/no retry, Cancel preserves, explicit Discard clears, zero request closures. Three synchronized OS PNGs were inspected. The preceding run passed storage assertions but its seed native PNG was overwritten by the recovery monitor, and is not seed visual proof.

These results are local/simulator evidence, not physical iPhone or Samsung acceptance, media persistence/resume, real Auth0/APNs/FCM/calls, signing/store release or production latency. Samsung remains on the separately installed 0.5.6/code2011 historical candidate; full device acceptance stays open. Production uploads/concurrency remain held after the unresolved database OOM. No tuning, support correspondence, payment or deployment is authorized by these results.

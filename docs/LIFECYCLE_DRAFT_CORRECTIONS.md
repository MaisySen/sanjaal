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

## Further native acceptance evidence, November 20 overnight

iOS fixture manual-retry source `687334cae92c332a7b2858c2f2810a2d744c4e98` passed: https://github.com/MaisySen/sanjaal/actions/runs/44566153232 . One after-commit 503 caused visible Try again/Details without false success. Exactly one marked post existed before and after explicit retry. Synchronized OS failure/success PNGs were inspected. The same run passed previous local iOS app flows. Replay is fixture-only, not enabled in production.

iOS saved text/poll restart source `b840dd415f6e4cd663ca1cafbb8f575fa2d60880` passed: https://github.com/MaisySen/sanjaal/actions/runs/44572117649 . One install, identical app/data paths, seed PID26686 terminated/absent, recovery PID27970. Actual Keychain preserved exact random caption/options/revision; other-owner storage was empty. Saved drafts reopened the exact fields in the composer. Keep preserved the revision and explicit Delete cleared the saved list. Three synchronized OS screenshots were inspected, including the native keyboard below caption/options.

Android saved text/poll restart source `bb63b26f48c395a01f20c7c14480dc089b065199` passed: https://github.com/MaisySen/sanjaal/actions/runs/44580977909 . One install, seed PID5955, force-stop/noPID, identical UID10192/package path, recovery PID6184 using existing-app attach. Actual secure storage retained the exact caption/options/revision with separate-owner isolation. Reopen, Keep and Delete assertions passed. Both drivers reported two framework tests passed. Three actual app captures were inspected; Flutter-converted Android screenshots omit OS keyboard/status pixels and do not prove native IME geometry. The first attempt stalled at surface capture without a pump; the next reached final deletion but failed repeated surface conversion. Those are not counted as completed native checkpoints.

All overnight harness branches preserve app runtime/native/pubspec content from integrated4801171. No need to repeat unchanged full green CI merely to attach harness history. Unit/widget results, emulator flows, process restart, physical device acceptance and production recovery remain separate evidence classes.

### Remaining completion gates

- The Samsung installed historical7d/code2011 candidate has not received these newer runtime fixes. Exact replacement candidate finalization, safe in-place update and complete physical acceptance still need their own evidence and existing authority. No uninstall/data wipe workaround.
- Physical deterministic retry/process death, distinct Reel identity/playback/audio/retention, reference comparison, two-device chat/calls/push and Play update remain open. Local fixtures do not close them.
- iOS physical installation/signing, real identity-provider login, APNs/call behavior, permissions and hardware media remain unverified. No paid Apple commitment is authorized.
- Saved text/poll drafts and uncertainty markers survive tested process termination. Media jobs do not persist or automatically resume. Reboot, reinstall, cloud restoration and cross-device behavior are not proved.
- Production upload/concurrency QA remains held after the November19 database OOM. Current root cause and free-provider support eligibility remain unresolved. No further speculative tuning, paid resize, support send, production fault injection or load experiment follows from this evidence.
- Wallet funding/transfers/cash-out stay unavailable until separately verified. No money path, public release or new audience was activated overnight.


## Encrypted creator-media drafts, November 20 morning

The November 17 text-only checkpoint above is historical. Candidate
`af8e92f1b84572a83afe7d338de99a347660dc4c` adds explicit local saves for photos,
videos/reels and stories. It does not add an automatic outbox or background
upload resume. Saved story audience is preserved exactly as followers, close
friends or only me; unknown/missing values are rejected rather than broadened.

Media bytes are AES-GCM encrypted in the application's private support storage.
Per-account index/key material uses secure storage, owner directories are hashed,
immutable randomized file revisions are committed before their verified index,
and stale revision/state stamps cannot overwrite or delete a replacement draft.
Reads authenticate all saved bytes before handing them to an editor. Bounds are
four photos or one video/story, 25 MB per file, eight drafts/100 MB per account,
and 256 MB across device media drafts. Cleanup is confined to recognized private
owner paths and rejects symlinks. Encryption/decryption runs off the UI isolate.
Saving/opening does not send. A manual send reopens saved encrypted bytes rather
than trusting a mutable picker file. An attempted saved upload disables ordinary
Post/Share and requires explicit preparation of a separate upload. Existing
upload-uncertainty recovery remains a separate gate.

Exact regression run: https://github.com/MaisySen/sanjaal/actions/runs/44597313840 .
Analysis and 34 focused tests pass; whole app 1006 pass and one intentional live
skip. An unreadable text index no longer hides healthy media, or vice versa;
unreadable bytes are preserved. Synthetic large-text/inset captures verify the
warning/caption correction, not native keyboard geometry or the entire story
paragraph/footer layout. The paragraph is fully reachable at a separate scrolled-bottom position in four
English/Nepali light/dark large-text/inset captures. Bounds assertions and pixels
were inspected in https://github.com/MaisySen/sanjaal/actions/runs/44601314810 .
That run timed out later in a separate chat screenshot harness; it is not a full
regression pass. Caption and paragraph captures are separate scroll positions.

Last completed two-platform native checkpoint:
`6c06174c21a9745486d0fdaa9d8ae1b83a5fc682`,
https://github.com/MaisySen/sanjaal/actions/runs/44593185698 . One installed binary
on each emulator/simulator saved synthetic photo, video and only-me story,
deleted picker originals, terminated the app and recovered exact metadata and
SHA-256 bytes in a different process with identical install/data identity.
Other-account access was rejected. Manual reopen, attempted Post/Share disabled,
Keep and explicit Delete passed. Actual native/app pixels were inspected.

The newer af8 iOS native job also completed successfully in the exact regression
run above. One install, same app/data containers, seed PID25738 terminated and
recovery PID28651. Both driver processes passed and five synchronized OS images
were inspected. Caption is complete; the privacy paragraph in the initial story
frame extends below the scroll viewport. Full paragraph access is covered by the separately scrolled synthetic layouts
above, not inference from native recovery success. The af8 Android job
failed before app execution on an unreadable downloaded NDK archive; only that
infrastructure-failed job was retried. It passed: one install, same UID10192 and
package path, seed PID5900 force-stopped/absent, recovery PID6038. Both drivers
passed three framework tests and five app captures were inspected. The existing
iOS and regression successes were carried into attempt 2, not re-executed. The
whole exact af8 run is successful. Initial Android story capture has caption
below its viewport; it is not caption access evidence.

Recovered videos retain their bytes and exact names, but in-memory story-video
playback has an explicit unavailable-preview fallback. This is an actual product
limitation, not proof that the video is lost. Reboot, reinstall/backup, cloud sync,
real account uploads, production durability and physical Samsung/iPhone acceptance
remain unproved. Production QA hold, disabled money paths and release restrictions
are unchanged. No production API deployment or new phone installation followed.


## Open conversation screen session ownership

Chat source `22ef8e4f31541d21c1670a9a0597e18a34b1b76b` binds the inbox,
conversation, new-chat/group draft and group-info pages to their original account,
Session object and login generation. Replacement login, including the same
member, hides private history and retry/composer data, cancels polling/debounce,
invalidates delayed responses and closes stale group dialogs/settings sheets.
Future actions cannot borrow the replacement account. This does not add durable
chat storage or automatic replay and does not prove production messaging.

Exact run: https://github.com/MaisySen/sanjaal/actions/runs/44603967341 . Analysis
passes, all 103 focused cases pass and whole-app 1028 pass with one intentional
live skip. Removing the chat ownership predicate fails the same-member delayed
private-content test as expected; restored source passes. Four 2x-text
English/Nepali light/dark retired-session captures were inspected. Prior failures
include a missing translation, image encoding inside the synthetic widget clock,
and a wrapped negative-control log check. They were corrected, not reclassified
as passing runs. Native compilation/device acceptance of this changed runtime
remains separate from af8 media persistence evidence.

The subsequent calls/rooms/gift-sheet session batch is not yet accepted. Its
source closes account-bound media ownership before replacement authentication
waits, guards delayed callbacks and forbids cleanup with replacement credentials.
Offline SDK object cleanup still retains a periodic timer in four fixtures;
resource-leak assertions remain enabled while the wait boundary is investigated.
No real calls, rooms, gifts or payments were started. Hardware capture teardown,
real push/two-device delivery and physical exact-candidate acceptance remain open.


Realtime source `666bf4d0e3a4b4eb136d1ba1b8a4f86452cf3547` completed analysis,
60 focused and 1047 whole-app tests with one intentional live skip:
https://github.com/MaisySen/sanjaal/actions/runs/44607169655 . The four retained
SDK timer failures above came from undrained native SDK stream continuations in
the offline widget clock. Finite clock advances plus bounded real async draining
let the actual setup/disconnect/dispose chain complete. Pending timer/resource
invariants remain enabled, and all four previously failing tests now pass.
This settles that fixture defect, not microphone/camera hardware behavior.
Temporary trace removal and a login-invalidation negative control are the next
exact-candidate check. Native compilation and physical acceptance remain separate.


## Combined checkpoint and registration continuation

The final realtime source f029147 removes temporary traces. Its login-invalidation
negative control now fails on the intended missing-close assertion and terminates
cleanly after releasing fixture futures. Restored source passes analysis, 60
focused tests and 1047 whole-app tests with one intentional live skip:
https://github.com/MaisySen/sanjaal/actions/runs/44610529190 . This supersedes the
unfinished negative-control status above, not hardware capture acceptance.

Combined45d6133 completed all seven required CI jobs, including local API and
PostgreSQL concurrency checks, Android APK/AAB, unsigned iOS compilation,
fail-closed money refusal and five Android driver journeys:
https://github.com/MaisySen/sanjaal/actions/runs/44610555992 . The separate exact
focused/negative-control run also passed:
https://github.com/MaisySen/sanjaal/actions/runs/44610556277 . Inspected 27 journey
images show feed/profile, local post/poll/chat, camera/gallery/story, wallet
unavailable controls and lost-reply/manual-retry recovery. This corrects the
pre-inspection expectation of 28 images. These are synthetic/local-service
journeys, not production performance or physical Samsung acceptance. The poll
native-input driver passed; its final capture has the keyboard dismissed and is
not itself a screenshot of the visible OS keyboard. No release or preview
publication ran.

Registration source0f6a2a5 binds the automatic signup-to-login continuation to its
starting session epoch and latest registration attempt. Late success or failure
cannot replace a newer same-member/other-member login or reopen logout. An older
concurrent signup cannot sign in while a newer signup is pending. This is local
continuation invalidation, not cancellation or rollback of remote account creation.
Exact analysis, 41 focused and 1054 whole-app tests with one intentional live skip
passed; removing the epoch check makes the delayed-success replacement test fail
immediately and restored source passes:
https://github.com/MaisySen/sanjaal/actions/runs/44612746932 . Provider responses
are synthetic and no live account was created. The registration change is now
being integrated; the earlier combined run does not prove this newer runtime.
Two-platform same-install media restart checks on the45 byte-identical runtime
remain separate and in progress in run44612540189.


## Story account lifetime checkpoint

Story source d885a02 completed analysis,89 focused and1076 full-app tests with
one intentional live skip. Disabling the account predicate makes the delayed
header test fail immediately; restored source passes:
https://github.com/MaisySen/sanjaal/actions/runs/44615633752 . The story bar and
viewer bind the exact Session object, original owner and generation. Retirement
hides private rings/captions, clears image/header state, cancels progress, pauses
and disposes video, closes viewer/delete overlays and blocks late actions. The
picker-to-review and foreground delayed-byte share continuations also check the
originating ownership. This does not retract a request already sent remotely.
Four2x English/Nepali light/dark retired-story renders were visually inspected.
The first run's two platform-dispose count failures were resolved by draining
fake stream cancellation on a bounded real async tick, as the existing player
fixtures do. Actual video-controller disposal remains asserted, not bypassed.
No native hardware, live story read/upload/delete or two-account-device proof.

Combined45 byte-identical runtime on workflow55f4f0d completed both platform
same-install media checks:
https://github.com/MaisySen/sanjaal/actions/runs/44612540189 . Android seed5726
was force-stopped and absent before recovery5874, sameUID10192 and package path.
iOS seed33391 was terminated/absent before recovery34448. Both platform drivers
pass, exact bytes/metadata recovered after picker originals were removed,
other-owner access refused and manual attempted-upload guards preserved.
Five Android app and five synchronized iOS OS images were inspected. Initial
Android story caption is below the scroll viewport. iOS caption is visible;
privacy text extends below the viewport. Full-paragraph reachability has the
separate scrolled-layout evidence above. This older runtime proof is not proof
of the registration/story changes now being integrated. No phone install,
production change, distribution or money activation followed.

Combined51 exact registration/realtime focused run passed101 cases and1054
full-app cases with one live skip and both negative controls:
https://github.com/MaisySen/sanjaal/actions/runs/44614683806 . Main CI emulator
is still pending at this writing. The next combined head adds story retirement
and must get its own exact-head checks. Earlier checkpoint wording is historical.

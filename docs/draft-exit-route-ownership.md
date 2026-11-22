# Shared draft-exit route ownership

This is a local source correction. Requests, account changes, drafts and messages in the tests are synthetic. No live data was deleted or published.

## Changes

DraftExitGuard now starts confirmation only for its current originating route. Keep/Discard callbacks own their exact current dialog and accept one choice. Retained, conflicting and duplicate callbacks cannot dismiss a cover or another route. Dismissing the dialog also retires its callbacks.

The confirmation lock lasts through the result frame. An accepted discard checks the originating route and current busy state before arming PopScope, and checks both again after PopScope publishes that state. A cover, a departing route or a new busy operation makes that result inert rather than replaying it later. The temporary discard disposition is reset on that refusal. Busy always prevents PopScope from advertising that it can leave, even during a previously accepted discard frame. An extra probe found this bypass in the first candidate; the corrected candidate passes it.

When the guard is disposed, its exact outstanding dialog is removed after build. A covering route is not popped. The same cleanup applies if the dialog first builds after its owner retired. The guard does not read or remove stored drafts, start requests, cancel already-issued work or certify the outcome of an operation. Existing busy copy, confirmation copy, button labels and normal clean/Keep/Discard behavior remain.

## Evidence

At the preceding 8d1c3f8 source, 18 of 21 expanded route/state cases failed their intended ownership, busy or cleanup assertions; the three unchanged-behavior controls passed. These follow the original three isolated cover failures. The initial isolated probe had a const-constructor fixture error before those three were reproduced; that compile error is not negative evidence. The expanded retirement checks verify automatic dialog cleanup before invoking old callbacks.

There are 31 new passing cases:
- 21 synthetic route/state cases in draft_exit_ownership_test.dart. These cover retained/duplicate/conflicting choices, barrier dismissal, a second blocked Back, busy changes around the result frame, an additional Back during that busy frame, cover/departure handling, owner retirement before/after the dialog frame, and clean/busy controls.
- 10 actual-route cases in draft_exit_connected_test.dart. New group, profile editor, text post creator and chat each retain the local draft after a covered choice and require a fresh explicit Keep or Discard after the cover closes. Separate current/covered account-replacement cases remove only that retired editor's prompt. Group title/member selection and text values survive Keep; leaving does not create/update/publish/send.

Current completed selections, concurrency 1, filenames under app/test with .dart suffixes:
- New: 31 passes in the two files above.
- B1: 66 passes in new_chat_journey_test, group_drafts_test and chat_exit_continuity_test.
- B2: 54 passes in profile_journey_test, profile_editor_session_test and creator_draft_route_ownership_test.
- B3: 41 passes in creator_drafts_test and creator_media_draft_widgets_test.
- B4: 88 passes and one existing environment-gated skip in member_controls_test, member_controls_session_test, discovery_consent_page_test, story_audience_test, story_audience_session_test and story_reply_test. The skipped case replays supplied Laravel consent HTTP bodies; DISCOVERY_CONSENT_CAPTURE was not provided. It was not replaced by fabricated data or counted as passed.
- B5: 43 passes in chats_handoff_journey_test, chats_handoff_recovery_test, connected_first_use_test and new_chat_return_ownership_test. This reruns the preceding connected chat handoff and actual-root first-use journeys against the changed guard.

These are separate local selections, not a whole-suite, native or provider result, and overlap earlier checkpoints. An earlier eight-file invocation was incomplete after a Dart compiler process exited unexpectedly: 57 cases passed, one compiler error was reported, then the command limit ended the invocation. Its cause is not established. No processes remained. The narrower completed selections do not retroactively complete it.

Focused guard/new-test analysis reports no issues. git diff --check passes. One new test lint was fixed before the final run.

Eight actual dialog/kept-draft captures were inspected at a 320x640 logical viewport with 1.8x text: group and post creator in EN/light, profile and chat in NE/dark. Dialog copy and both actions fit the captured views. Kept values remain present. Existing single-line profile-name horizontal scrolling and creator/chat title ellipsis are visible; these are not a claim of full-screen reference acceptance. No physical keyboard or device behavior was measured.

## Scope limits

This covers the shared guard and the named paths, not every caller, nested navigator shape, custom dialog, editor-save callback or async completion in the app. Caller session/draft ownership remains the caller's responsibility. Already-issued work, native persistence, interruption/cold start, provider behavior, full product/reference acceptance and private delivery remain open.

No source push, backend rollout, deployment, native build, stable-key signing, installation or distribution occurred. Default-off capabilities, native restrictions, existing Apple keys and Stampies were not changed. Apple identity setup remains separate.

Profile text-save return has a separate bounded follow-up in [Profile save-route ownership](profile-save-route-ownership.md). Other caller/receipt/native limits above remain open.

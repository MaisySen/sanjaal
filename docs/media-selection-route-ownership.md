# Media selection route ownership

Bounded local follow-up to 9a09dfc. Fake library/device futures, synthetic bytes and real widget routes are used. No phone media, permission prompt, native camera, account, live upload or publication was accessed.

## Changes

MediaLibraryPage now requires its current route for selection, resolution and camera/system-picker entry. Asset resolution captures that route and rechecks it after both file materialization and length reads. Camera and system-picker results can close only the original current library route. A covering route is never popped to deliver media to the wrong caller. A result completed while covered is dropped, the existing busy flag clears, and uncovering does not automatically resume navigation. No stored or device file is deleted.

The story photo/video choice completes once and owns its exact sheet. Retained or duplicate choices cannot dismiss a cover or the library. Library disposal removes only that owned sheet after build, including disposal before its first frame. It preserves other covering routes.

Shared guardPick now refuses a covered/disposed entry and drops late selection or permission/error outcomes if its original route is no longer current. Current selection, cancellation and permission explanations keep their behavior. Other current errors still reach the caller. Contexts without a ModalRoute retain mounted-only compatibility. Account checks remain the caller's responsibility. This helper is shared by the media library, profile picker and chat attachment picker.

## Verification

- media_selection_route_ownership_test.dart: 29 passes. Covers retained library entry after cover/disposal, picker/file/length/camera-return covers, no automatic navigation on uncover, owned story choices and sheet disposal, generic picker result/permission/error/start ownership, current permission controls, and actual profile/chat picker integration with no covered upload or toast.
- Exact unchanged 9a09dfc UI/library source with the final new tests: 25 intended failures, 4 controls passing. The controls are disposed permission completion, current shared-picker behavior and the two readable current permission routes. This is a local contract comparison, not 25 live incidents.
- A: 49 passes in capture_library_test.dart and camera_test.dart. These preserve fake gallery/camera/current story/reel fallback and review/publication behavior.
- B: 165 passes in creator_journey_test.dart, profile_journey_test.dart, profile_response_session_test.dart, profile_response_failure_ui_test.dart, chat_media_retry_test.dart and private_chat_media_test.dart.
- Connected final selection: 74 passes in the new 29-case file plus profile_editor_session_test.dart, profile_save_route_ownership_test.dart and chat_screen_session_test.dart.

Selections overlap earlier checkpoints and each other. They are not whole-suite, provider, native, codec, live-server or phone-speed results. Focused source/new-test analysis has no errors or warnings and the same 11 pre-existing source infos as the unchanged baseline. New-test analysis adds no infos. Whitespace validation passes.

The first negative invocation timed out because a retained-camera fixture awaited its own newly opened child. No compiler/test process remained; the fixture now closes that child before awaiting completion. Early story-choice checks did not wait for reverse transitions and were not settled controls. The final comparison waits for settled routes. The initial chat integration counter also counted its normal read acknowledgement; the final upload counter explicitly excludes that request. Those interim results are excluded.

## Pixels and limits

Inspected actual English and Nepali permission-recovery captures at 320x640 logical and 1.8x text. Current Camera/Device picker, title, Close/settings controls and existing permission message are readable. The lower library explanation is scrollable behind the temporary snackbar. An earlier report of missing Nepali header SVGs is withdrawn: direct comparison shows the Close and settings regions are pixel-identical to their English counterparts, and the delivered images match the archived bytes. No distinct failing capture was retained, so there is no evidence of the alleged intermittent render issue. That was an inspection error. These captures are not physical-device or full reference acceptance.

No copy, layout, input format, upload endpoint, draft store, file limit, native setting or feature flag changed. This does not cover every gallery/filter/settings callback, native permission/lifecycle behavior, codecs, account-bound media selection, or downstream file reads after guardPick has returned. In particular, complete profile/avatar and chat attachment read/upload/late-toast ownership remains open. Already-started reads and native work are not canceled or undone. See [profile response/session ownership](profile-response-session-ownership.md) for the separate account-map boundary.

No source push, backend rollout, deployment, native build, signing, installation or distribution occurred. Default-off restrictions, Apple identity/keys and Stampies are unchanged. Full product/native/provider/reference/release acceptance remains unfinished.

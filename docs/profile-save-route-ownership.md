# Profile editor save-return ownership

The corrected old-source run at 9db7a56 reproduces ten failures in retained Save/photo entry, covered or departing save completion, duplicate completion-frame actions, and queued/newer local edits. These are synthetic widget/picker/PATCH tests, not live profile changes.

## Changes

Save and photo-picker entry now require the current editor route and original active session. Save captures the original route and one raw name/username/bio snapshot. The request still trims and submits those same fields through the existing API method.

An accepted API response marks that submitted snapshot as the editor's clean baseline. The editor keeps a completion lock across its return frame, including fields, Save and photo entry. It leaves only if the original route is still current, the session is still active and the displayed values still match the submitted snapshot. A covering or replacement route is preserved. No automatic navigation resumes when a cover later closes, and no automatic request retry or extra profile GET was added.

The previous sticky saved boolean is replaced by the submitted-snapshot baseline. After a covered completion, unchanged Back can leave without a false discard question. A later edit, including a queued controller change in the completion frame, remains dirty and gets the existing leave confirmation. The completion does not silently discard that later change. Existing validation, error/retry copy and session retirement remain.

## Verification

Ten new cases in profile_save_route_ownership_test.dart pass. The corrected old-source run fails all ten at their intended request/picker, route or retained-value assertions. Two original photo probes tried to cast the tooltip wrapper to IconButton; their finder was corrected before the ten-case baseline was rerun. The original eight-case log is not the settled negative evidence.

Current completed selections, concurrency 1, filenames under app/test with .dart suffixes:
- New: 10 passes in profile_save_route_ownership_test.
- A: 85 passes in profile_journey_test, profile_editor_session_test, connected_first_use_test, draft_exit_ownership_test and draft_exit_connected_test. Includes the preceding 31 shared-guard cases and existing actual-root signup/find/follow/chat/profile-edit/Home flow.
- B: 120 passes in profile_message_route_ownership_test, profile_chat_receipt_test, profile_menu_ownership_test, profile_menu_recovery_test, profile_blocked_content_test, profile_identity_read_test and member_actions_session_test.
- C: 4 passes in ios_push_readiness_test and api_keepalive_test, preserving the bounded unsupported-iOS path and synthetic client/session isolation checks.

These selections overlap earlier checkpoints. They are not a whole-suite, provider, live-server or phone-speed result. Focused profile source/new-test analysis has no errors or warnings and one existing underscore info. git diff --check passes.

Three actual 320x640 logical, 1.8x text captures were inspected: EN/light and NE/dark editor return after a covered accepted response, and the NE/dark later bio edit preserved after Keep. The submitted name, later bio, existing labels and Save control fit those views. This is not physical keyboard, device, linguistic or full reference acceptance.

## Limits

The API's existing accepted-response/Session update behavior is unchanged. The baseline is not an independent server read, proof that returned fields are authentic, or a new receipt-validation contract. No new explicit saved-status claim was added. Already-issued work is not canceled or undone. Server username handling, malformed or inconsistent profile responses, global API ordering and persistence remain separate work.

Photo-picker start ownership is covered here, not the entire picker/file-read/upload/late-toast path. Other editor/custom-dialog callbacks and nested navigation shapes are not certified. Full profile editing, provider/native/background/cold-start, physical-device performance and product/reference/release acceptance remain open.

No live account/profile/data action, source push, backend rollout, deployment, native build, signing, installation or distribution occurred. Default-off/native restrictions, existing Apple keys and Stampies are unchanged. Apple identity setup remains separate.

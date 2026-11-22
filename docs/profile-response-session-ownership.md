# Profile response and session ownership

This is a bounded client-side correction after 913b813. All HTTP, credentials, picker bytes and account transitions in the evidence are synthetic. No live profile, upload, account, server or native action is demonstrated.

## Source contract and compatibility

The current backend AuthController.update and SocialController.avatar both return Present.user. That presenter exposes public_id, name, username, nullable bio and nullable avatar_url. The profile editor submits name/username/bio; the avatar method uploads its existing multipart file. This change adds no request, endpoint, retry, capability or server feature.

The client keeps existing sparse-response compatibility rather than imposing a new complete-resource receipt requirement. A response must have a nonempty user map with string keys and at least one supported field. If public_id is present it must equal the captured member ID. Present name/username must be strings; present bio/avatar_url must be strings or null. Unsupported response fields cannot overwrite existing session metadata. Supported fields are fully checked before one merge into the current session map and one notification.

This is a deliberate structural/ownership boundary, not a claim that a partial reply is the backend's complete contract. It does not validate the contents of strings or URLs, compare returned values to submitted edits, require all presenter fields, independently authenticate a reply, prove persistence, or add server readback. Backend validation remains responsible for accepted input; this guard does not replace it.

## Ownership and parse correction

Both mutations capture the original session generation and member ID, and refuse request start while signed out, missing a valid ID, authenticating a replacement, or waiting for a replacement account view. Avatar repeats the check after token acquisition. Both recheck before committing a response.

This prevents a profile response from repopulating Session.user when call's offline-state notification synchronously signs out. Generic call is unchanged: the profile method owns its post-await check. The synthetic sign-out probe injects a no-op push cleanup.

Malformed success bodies/maps/field types and foreign/null member IDs leave the local user map unchanged. Profile JSON parse failures and avatar parse failures use the existing localized uncertainty error. A received HTTP rejection preserves its existing API status and never merges an included user object. These outcomes do not mean that a server-side mutation was canceled or undone.

## Verification

New permanent selections, concurrency 1:

- profile_response_session_test.dart: 65 passes. Covers the synchronous offline/sign-out case, malformed bodies/envelopes/user maps, foreign/null/empty/numeric IDs, invalid field types and mixed fields, unknown-only fields, atomic supported-field updates with nullable fields and retained metadata, request-start account gates, existing sparse behavior, and HTTP 422/503 rejection controls.
- profile_response_failure_ui_test.dart: 8 passes. Real editor Save/avatar failure routes for foreign-member and broken-JSON replies in English/light and Nepali/dark. The original session and edited name remain, controls unlock, uncertainty copy is shown without a photo-saved message, no automatic retry occurs, and Back/Keep preserves the text draft.

The exact final 73-case selection against the unchanged 913b813 API source produces 65 intended failures and 8 controls passing. Other app source/dependencies are unchanged for that comparison. The eight controls are signed-out request rejection, existing sparse-response behavior and HTTP rejection cases. These counts describe test cases, not independent live security incidents.

The first expanded wrapper fixture could not compile because its JSON helper excluded null; that fixture type was corrected before the settled comparisons. The next expanded candidate run passed 60 and failed one profile broken-JSON error-class case. Its narrow parse normalization was fixed before the final runs. Neither incomplete attempt is counted as completed evidence.

Final existing selections on the corrected source:

- A: 90 passes in upload_session_test, account_view_payload_atomicity_test, account_view_recovery_test, auth_recovery_test, registration_session_test, session_restore_test and api_keepalive_test.
- B: 95 passes in profile_journey_test, profile_editor_session_test, profile_save_route_ownership_test, connected_first_use_test, draft_exit_ownership_test and draft_exit_connected_test.
- C: 126 passes in profile_message_route_ownership_test, profile_chat_receipt_test, profile_menu_ownership_test, profile_menu_recovery_test, profile_blocked_content_test, profile_identity_read_test, member_actions_session_test and failure_presentation_test.

These selections overlap prior checkpoints. They are not a whole-suite, CI-provider, live-server or device-performance result. Focused API and new-test analysis has no issues; diff whitespace validation passes.

Eight actual editor failure captures at 320x640 logical and 1.8x text were inspected, including two full-size examples and both four-panel contact sheets. The uncertainty message, retained values, header and Save control fit the tested views. The form remains scrollable behind its temporary snackbar. This is not physical keyboard, full linguistic, device or reference acceptance.

## Remaining boundaries

[Save-return ownership](profile-save-route-ownership.md) and [shared leave ownership](draft-exit-route-ownership.md) remain separate bounded checkpoints. Complete picker/file/upload/late-toast route ownership, simultaneous mutation ordering, all string semantics, account-read schema, independent readback, cold/native persistence and full profile editing remain open. A rejected reply preserves local state but cannot undo already-issued work.

Default-off privacy/native restrictions, Apple keys and Stampies are unchanged. No source push, backend rollout, deployment, native build, signing, installation, store upload or distribution occurred. Full product/native/provider/reference/release acceptance remains unfinished. Apple identity setup remains separate.

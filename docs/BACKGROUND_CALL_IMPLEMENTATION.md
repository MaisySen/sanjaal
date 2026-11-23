# Background incoming calls: active private implementation

Base complete candidate:0ee9af1. Shared wake contract checkpoint:1c3d2c0.

## Implemented source, not activated

- Minimal per-recipient wake metadata with fixed40second server deadline. Eligibility is rebuilt from current call/member/mute/block state. No API/media token or caller content in the envelope.
- Dart/Kotlin/Swift parsing of recipient, exact IDs, kind and bounded issue/expiry metadata. Presentation is never authority for authenticated call action or media join.
- Private native adapter scaffolds now provide Android31+ CallStyle notification/action buffering and native iOS PushKit/CallKit reporting, short expiry and audio-availability hooks.
- Android scaffold compiles against existing Android36 and Flutter engine jars with a stub MainActivity solely for symbol resolution. This is not a merged app/package/native runtime build.

Android process channel is attached by MainActivity but has no receiver/provider selection; the iOS adapter is attached lazily to the ordinary scene engine without PushKit registration. Swift files are now added to the target but have not been compiled. No manifest, background mode, entitlement, provider registration or live sender activation changed. Android registered status deliberately remains false until the missing receiver/Telecom lifecycle is integrated. No full-screen grant is assumed. No new call plugin/dependency was installed.

## Native event coordinator checkpoint

A private unselected Dart coordinator now binds native event identity to a supplied
restored-login lease plus the current Session generation. It reads the exact call,
requires a verified ringing state before one Answer action, never joins an answer
already made elsewhere, and does not repeat an unknown-result action. End/Decline
cancel in-flight local connection before authenticated state handling. Replacement
login retires pending/connected media without replacement-account cleanup requests.
The injected connection boundary explicitly requires cameraEnabled=false.

This is not actual native engine/root integration. Lease persistence/rotation,
process-death replay, native event acknowledgement, complete actual native active-call End signaling after
the initial ring expiry, remote cancellation transport and actual SDK audio/media
ownership still need implementation. No shortcut from this tested coordinator to
claims of native reliability is valid.

The coordinator now permits End after the original ring deadline only for a call
this coordinator actually connected or is connecting, never an expired arbitrary
call ID. Fourteen coordinator cases pass, including this connected-call End and
an expired unowned End. Actual platform active-call state remains unwired.

## Active engineering still required

1. Android bounded metadata journal now persists owner/UUID lease, current ring, up to8queued events and64seen call IDs. Drain is nondestructive; explicit claim-before-effect and acknowledgement prevent automatic action replay after engine death. A26-assertion in-memory SharedPreferences proxy check covers metadata reload, duplicate/expiry, lease change, claim persistence and write failure. This is not Android process-death execution. Actual restored-login lease persistence/rotation and one process owner are now implemented in source, while receiver activation and full runtime remain unintegrated; never store an access token in these preferences.
2. Android provider-authenticated C2DM receiver coexistence with installed FlutterFire15.2.10. Add Telecom and foreground phoneCall lifecycle, notification policy/permission state, answer/end/hold actions and API<31 policy, without competing generic messaging services.
3. iOS process-owned PushKit/CallKit and FlutterEngine availability in cold/background scene state. Wire native CallKit audio ownership into installed LiveKit2.13.2 externalCallSystem; defer answer fulfillment until authenticated exact-call state and connection, not merely the system tap. Background video camera remains off.
4. A native event coordinator tied to stable owner plus login lease, exact authenticated GET/action state, no route replacement or implicit acceptance from an unverified push, bounded end/expiry reconciliation, cleanup and duplicate handling. Handle queued native End/Decline without borrowing replacement credentials.
5. Separate default-off Android data-only FCM and direct APNsVoIP token/sender paths. Revalidate eligibility at actual dispatch. Do not reuse notification+data chat sends. APNsVoIP tokens/topics and expiry differ from ordinary FCM/APNs notifications. Do not send more VoIP pushes to carry cancellation.
6. Provider/credential/capability review and exact native/physical foreground/background/terminated/lockscreen/account-switch/denied/expiry/audio acceptance. Mock tests and envelopes are not reliability proof.

## Grounding

- https://developer.android.com/develop/connectivity/telecom/voip-app/telecom
- https://developer.android.com/develop/ui/compose/notifications/call-style
- https://firebase.google.com/docs/cloud-messaging/android/message-priority
- https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit.md
- https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns.md
- https://source.android.com/docs/core/permissions/fsi-limits
- https://docs.flutter.dev/release/breaking-changes/uiscenedelegate
- https://github.com/livekit-examples/flutter-callkit/blob/main/README.md

Installed package source, not generic current examples, owns native hook compatibility: firebase_messaging15.2.10, livekit_client2.13.2, flutter_webrtc1.6.3. No store compliance claim or guaranteed delivery claim follows from this work.

## Secure restored-login binding

Session now exposes an opaque native call login lease only after authenticated
identity verification and outside loading/authentication/account-recovery gates.
It is stored alongside refresh credentials in secure storage, not preferences.
Ordinary refresh-token rotation and a process restore retain it; a successful new
password/social grant clears it before token persistence, including a same-owner
replacement. Logout clears it, and non-UUID fixture identities cannot enable it.
Failed secure metadata persistence leaves native wake readiness disabled without
blocking ordinary sign-in. Existing session generation checks still reject late
work. This supplies a real credential-lifecycle binding, but no root/native bridge
uses it yet; secure-storage mocks are not Keychain/Keystore restart proof.

## Native event pump checkpoint

The unselected engine-side event pump now binds only a verified Session lease,
claims each native event before authenticated coordinator work, acknowledges only
under that same binding, and refuses to replay an already claimed unknown-result
action. A replacement account retires the coordinator synchronously even during a
platform wait. Concurrent queued End can cancel an Answer waiting on a server read.
Cold restoration with no ready lease does not erase retained native events.
Explicit logout/native clear and actual root ownership remain unwired.

Android and iOS claim/drain/acknowledge now also require matching owner/lease on
the native side. iOS no longer evicts its seen-call replay guard at capacity, and
a delayed CallKit report completion cannot accept an incoming call after a login
binding change. Swift remains uncompiled, with in-memory-only action claims.
The real channel contract was tested using Flutter's mocked platform messenger,
not an OS call callback or process restart. Android adapter sources compile with
the existing jars/stub activity, not a full packaged build. Seventy-five selected
session, native coordinator and bridge cases pass; no root selects this pump yet.

## Android process/Telecom source checkpoint

MainActivity now attaches the application-context process singleton and routes its
initial/new call intents to that owner, with identity-guarded engine detachment.
No receiver, phone account, Telecom service manifest, permission or foreground
service is activated. Native `registered` remains false. A private ConnectionService
implementation is present but unregistered: self-managed VoIP metadata, checked
incoming offer, failed incoming handling, Bluetooth/system answer/reject/end
callbacks and deferred active transition until explicit authenticated media
completion. Presentation callback fails closed until the whole notification and
foreground-media handoff is selected. No inactive scaffold is called delivery proof.

Thirty selected Dart/coordinator/pump/source-boundary cases pass; native adapter,
journal, envelope and Telecom sources compile against Android36/Flutter jars plus
an activity symbol stub. The edited real MainActivity and full dependency graph
have not been packaged/compiled by this check. No Android OS Telecom execution,
process termination, lockscreen or Samsung flow has run. iOS stays uncompiled.

## Shared media owner, still unselected

CallController can now connect a video call with startCamera=false while retaining
video identity and later explicit in-app camera control. Native media actions
reserve/release the same ActiveCallHost slot instead of creating a second hidden
Room owner. Busy/quarantined hosts refuse reservation; native completion failure
releases capture. Android deliberately returns false for connected completion
until its inactive Telecom/foreground-service handoff is finished, rather than
claiming success while clearing the system call. Native event pump/actions remain
unselected. iOS externalCallSystem audio gating and cold-engine ownership remain
unfinished. Fifty-one selected controller, host, coordinator, pump and media-boundary
checks pass. No new UI is selected, no native/device media capture was tested and
no full product build was made.

## Inactive Android receiver/foreground-service source

Added a separate unregistered C2DM call-only receiver, leaving FlutterFire chat
receiver/service untouched. A compile-time false gate rejects delivery; source
filters out notification+data and non-call payloads before parsing. Future manifest
registration must require Google's SEND permission. No receiver is currently in
the manifest. Added an unregistered phoneCall foreground service with same-current
call/lease verification, explicit type, no sticky restart/boot recovery and denial
cleanup. It is not started from the adapter and cannot claim background support.
Foreground readiness/error callbacks exist but full Telecom/presentation/media
selection remains unfinished. Twenty-eight selected bridge/media/coordinator/source
checks pass and these Android sources compile against existing jars/stub activity.

Sources checked for this boundary:
https://developer.android.com/develop/background-work/services/fgs/service-types
https://firebase.google.com/docs/cloud-messaging/android/message-priority
Installed FlutterFire15.2.10 receiver and manifest inspected directly. This is source
compatibility work, not delivery, current permission approval or OS execution.

## iOS scene/audio source integration, not cold wake proof

The process-owned lazy CallKit adapter and envelope are now linked into the Xcode
target and attached from the existing implicit scene-engine callback. A native
LiveKit2.13.2 audio gate is wired to CallKit activation/deactivation, and activation
must return a successful live-device-module acknowledgement or fail the call.
No PushKit activation, background mode, entitlement or token/send action changed.
Swift compilation is still unperformed; a source-linked file is not a native pass.
A headless killed-state Flutter engine and single-owner handoff to the foreground
scene are not implemented and must not be faked with a second independent engine.

The optional CallController preflight and unselected Dart audio policy support
externalCallSystem before connection. It is deliberately not selected globally:
it would otherwise change ordinary foreground audio ownership before every call
has a native system owner. Thirty-nine selected source/controller/media/pump/
coordinator cases pass, focused analysis clean, no actual native audio operation.

Installed LiveKit2.13.2 explicitly documents externalCallSystem as retaining
ordinary audio management on Android, not standing down audio focus/routing for
Telecom. Android handoff cannot be declared complete by choosing that mode. Actual
SDK native audio ownership compatibility remains engineering work before selection.

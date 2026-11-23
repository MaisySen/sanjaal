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

## Failure-path review

Review caught and fixed a live-media leak if the native `complete` channel throws:
media actions now release capture on an exception as well as a false acknowledgement.
The event pump also clears native metadata when an established engine binding
retires or the root settles signed out, while preserving an untouched cold journal
during pending/offline identity restoration. These are unselected source paths.
Thirty-three lease/pump/coordinator/media regressions pass, including throwing
completion, settled logout and offline cold restore. Analysis clean.

Pinned Android native SDK inspection confirms manageAudioFocus=false alone is not
a complete Telecom handoff: LKAudioSwitchManager still activates communication
mode and chooses routes. Do not select it as a workaround or claim compatibility.

## Separate server token/data-only transport, inactive

Added a distinct call_devices migration and authenticated default-off registration/
removal routes for FCM and APNsVoIP tokens, bound to user plus login lease. No
migration was applied outside the isolated test DB. Old-owner/old-lease removal
cannot delete replacement enrollment. Chat device_tokens remain separate.
Push::incomingCall is a separate default-off, uncalled data-only Android path:
no notification/title/body, high priority, remaining ring TTL, current eligibility
and token-owner/lease recheck before each dispatch. APNsVoIP transport sending and
client enrollment remain unfinished. No existing ring producer calls the sender.
No config/credential activation, deployment or live network send occurred.

Corrected test bootstrap resolves optimized application class maps AND Laravel
base-path inference to this checkout. Earlier reused bootstrap could mix old source;
its API claims are superseded by current15tests/66assertions for CallDevice,
CallWake and Push, all HTTP faked. Actual source/base paths were checked. Flutter
188case consolidation is independent and unaffected by the PHP bootstrap issue.

## Direct APNsVoIP transport source

Separate default-off uncalled CallVoipPush now builds direct HTTP/2 APNs requests,
ES256 provider tokens, explicit sandbox/production enrollment separation, fixed
.voip topic, voip push type, high priority and expiration0 (no stored stale ring).
Only minimal current eligible call metadata is sent; no chat alerts or cancellation
VoIP pushes. No redirects/retry loop. Exact owner/lease enrollment is checked again,
and old APNs unregistration timestamps cannot delete newer token enrollment.
Client enrollment/cold engine/provider capability remain unselected and unfinished.
No credential or env value was set, no live request or deployment occurred.
Eighteen current-source API tests pass with network interception, including both
APNs environments and stale unregistration. This is not APNs integration proof.

Grounding:
https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns.md
https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns.md

## Enrollment and delayed prior-login wake guard

Private unselected NativeCallRegistration now requires verified UUID owner/login
lease, platform-ready token and explicit APNs environment, deduplicates current
enrollment and rechecks login generation after a token wait. No platform token
adapter/root selects it yet and removal/logout network integration remains open.

Review found same-account prior-login delivery could otherwise be rebound by the
native process. Dispatch now includes the exact enrolled login_lease and both
native receive paths require it before accepting the call. Android receiver retains
that field and iOS still reports then ends invalid VoIP callbacks per CallKit rules.
Nineteen client/source/pump cases and18current-source API tests78assertions pass;
Android six call sources compile against jars/activity symbol stub. Swift remains
uncompiled and no platform registration or delivery occurred.

## Enrollment removal and readiness channel

ChannelNativeCallDevice now reads native readiness without requesting permissions,
starting Firebase/PushKit or treating possession of a token as readiness. Android
audio/Telecom and iOS cold-engine gaps keep native registration responses false.
Enrollment captures a fixed authenticated removal request before registration;
retirement during an in-flight enrollment removes its late receipt using that
old access/lease only, not replacement Session.call. Explicit unregister retires
future work and removes confirmed enrollment. Actual root/logout hooks remain
unselected, and unknown-result network enrollment still needs bounded reconciliation.
Forty-nine selected enrollment/lease/session/pump tests pass with clean analysis;
Android sources compile against jars/activity symbol stub. No OS native execution.

## Android lifecycle handoff implementation, still gated

Android receive source now offers to Telecom first and posts its ring only from
Telecom's incoming-UI callback. Native media preparation waits for the phoneCall
foreground service acknowledgement before reserving capture, bounded to4seconds;
connection completion requires service readiness and actual Telecom activation.
Call expiry/account cleanup retires Telecom/service; service stop is call/lease
bound so stale destruction cannot stop replacement work. All paths remain behind
compile-time false rollout, no manifest/service/permission registration and no
phone account activation. iOS prepare deliberately false until cold-engine/audio
integration is ready. No background delivery capability is claimed.

Also retained unknown-result enrollment attempts before POST, so unregister can
remove a lost-response attempt without repeating enrollment. Twenty-eight selected
source/pump/media/enrollment checks pass, focused analysis clean, six Android
sources compile using jars/activity symbol stub. No Android service/Telecom runtime,
Swift compilation or physical acceptance occurred. SDK Android audio ownership and
cold iOS scene-engine integration remain substantive gaps.

## Gated single iOS engine/scene path

Added a private compile-time false NativeCallEngine owner: one retained headless
engine, one-time plugin configuration, failure latch and reuse by a later scene.
When selected, AppDelegate's scene configuration omits the storyboard to avoid
creating a second implicit engine; SceneDelegate installs that same engine's
controller. The currently selected legacy implicit-scene path stays unchanged.
Native wakeEngine points to the shared owner, not a second fallback engine.
Twenty-five source/pump/media/enrollment tests pass. These source-contract checks
cannot validate Swift signatures, actual UIScene launch, plugin callbacks or cold
calls; Swift remains uncompiled and the gate remains false. Full native root,
audio and provider enrollment/physical review still precede selection.

References inspected:
https://api.flutter.dev/ios-embedder/interface_flutter_scene_delegate.html
https://api.flutter.dev/ios-embedder/interface_flutter_engine.html
https://docs.flutter.dev/add-to-app/ios/add-flutter-screen

## Root source gate and later-End race

Main root now contains a compile-time false NativeCallRoot wrapper, using the
existing ActiveCallHost key. With the gate false it makes no channel/enrollment/
permission call. Its private path binds the pump and shared media slot, rotates
registration by verified login lease and retires old enrollment. Native incoming/
open callbacks do not navigate in background. Token refresh and failed-cleanup
surfacing still need integration before selection. It is not enabled behavior.

Review also found that a later native End callback was blocked behind an Answer's
pending network read. Pump dispatch now lets later callbacks drain independently,
with per-lease in-flight event guards. Added a real incoming-channel callback test
which cancels Answer before the read completes. Twenty-six root/pump/media/
enrollment/cold-root cases pass and focused analysis clean. No pixels changed by
the false root gate; native proof remains outstanding.

## Token rotation cleanup review

Native tokenChanged events now route to the private enrollment owner. Before a
new token/lease replaces its cleanup handle, the previous enrollment is removed
using its captured request; cleanup failure blocks replacement rather than
orphaning old tokens. The root retains a generic lifecycle error for the later
settings/status surface instead of swallowing cleanup failure. Source gate stays
false; that status surface and native token/provider readiness remain unfinished.
Twenty selected registration/root/pump cases pass, focused analysis clean.

## Narrow pinned SDK audio ownership patch, inactive

To avoid treating a fire-and-forget audio stop as ownership proof, retained exact
LiveKit2.13.2 source/license locally with per-file upstream hashes and a path
override. No version/range update. The narrow Android patch serializes explicit
external-Telecom ownership with all mode/focus/routing operations, latches external
ownership before native stop, and acknowledges actual completion/error on the
main channel. Pending start/config/route operations stop applying while external.
Release confirms stop and does not restart SDK audio. Native source compilation
of this patched SDK/dependency graph has NOT run; it remains unvalidated native
source, not a resolved compatibility proof.

Dart prepares acknowledged ownership before manual SDK mode and uses the shared
controller's release callback after capture/peer cleanup; failed release returns
false into existing call quarantine. Root/native rollout stays false. Thirty-seven
selected audio/controller/host/media/SDK-pin tests pass and focused analysis clean.
iOS return from external audio ownership to ordinary foreground mode still needs
ordering integration with CallKit termination. Full native candidate review and
physical routing/audio acceptance remain mandatory before selecting either path.

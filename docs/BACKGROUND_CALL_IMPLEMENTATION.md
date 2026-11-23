# Background incoming calls: active private implementation

Base complete candidate:0ee9af1. Shared wake contract checkpoint:1c3d2c0.

## Implemented source, not activated

- Minimal per-recipient wake metadata with fixed40second server deadline. Eligibility is rebuilt from current call/member/mute/block state. No API/media token or caller content in the envelope.
- Dart/Kotlin/Swift parsing of recipient, exact IDs, kind and bounded issue/expiry metadata. Presentation is never authority for authenticated call action or media join.
- Private native adapter scaffolds now provide Android31+ CallStyle notification/action buffering and native iOS PushKit/CallKit reporting, short expiry and audio-availability hooks.
- Android scaffold compiles against existing Android36 and Flutter engine jars with a stub MainActivity solely for symbol resolution. This is not a merged app/package/native runtime build.

Neither adapter is selected or called from the app. Swift files are not added to the target or compiled. No manifest, background mode, entitlement, provider registration or live sender activation changed. Android registered status deliberately remains false until the missing receiver/Telecom lifecycle is integrated. No full-screen grant is assumed. No new call plugin/dependency was installed.

## Active engineering still required

1. Persist bounded account-bound action/replay metadata safely across Android process death, coordinate one application/process owner and bind/clear with the actual restored login lease. Never store an access token in wake preferences.
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

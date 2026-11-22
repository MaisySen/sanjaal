# iOS push client preparation

At the November 22 provider setup check, the existing Firebase project had the Apple app au.fintex.sanjaal, Firebase app ID1:746380796806:ios:f1cbfec107dd2a210c8207. Project remains Spark, no billing upgrade. HTTPv1was already enabled; its first loading-state text was not the final provider state.

Provider: https://console.firebase.google.com/project/sanjaal-app-3ede9/settings/general/ios:au.fintex.sanjaal
APNs configuration: https://console.firebase.google.com/project/sanjaal-app-3ede9/settings/cloudmessaging/ios:au.fintex.sanjaal

At that check, neither APNs authentication key nor certificate was installed for development or production. No Apple key was created and no notification sent.

The earlier missing-download statement is superseded: the actual provider-issued GoogleService-Info.plist was captured and delivered privately to main at 10:32 on November 22. Its exact bytes remain outside the repository and are not installed in the iOS target. SHA256: c0e22f07ca1e64455be4894c6fe0c684adb4c94346fd82a042eee43fd794b1e1. Parsed bundle au.fintex.sanjaal, app 1:746380796806:ios:f1cbfec107dd2a210c8207, project sanjaal-app-3ede9, sender 746380796806. Ads/analytics flags are false. This client configuration is not an APNs private key, provisioning entitlement or delivery proof.

ApplePushDevice and FirebaseApplePushBridge are source preparation only, not selected by Push. Existing iOS unavailable behavior stays intact. The bridge requires native iOS configuration and never reuses Android options. APNs readiness is bounded before FCM token creation. Invalidation cancels late APNs work and queues token deletion before a later owner can fetch a token. Tests use synthetic tokens only.

Integration still needs native installation of the captured provider-issued configuration, APNs key/certificate handling under the current grant, actual Xcode capabilities/profile review, consent/auto-init review, client wiring, and reviewed exact-source signed-device foreground/background and account-switch acceptance. No new app build, signing, installation or distribution was performed. Do not claim iOS push is enabled.

Official setup: https://firebase.google.com/docs/cloud-messaging/flutter/client


## Credential isolation and default initialization review, November 22

App Store Connect API keys and APNs authentication keys are different credentials, despite both being downloadable .p8 files. The selected developer account API-key issue must not be solved by reusing an unrelated APNs key, and conversely the API key cannot configure Firebase APNs.

Current official Apple documentation supports APNs topic-specific keys restricted to selected topics and one environment, in addition to broader team-scoped keys. For later authorized Sanjaal setup, evaluate a dedicated au.fintex.sanjaal topic/environment key rather than reusing an existing cross-app key. No key was created and this note is not an instruction to mutate account capabilities. Firebase docs expose development/production APNs key upload, but no current integration/device proof is claimed for a topic-specific key in this project.

Before bundling native config or wiring the adapter, explicitly review FCM auto-initialization and consent. Firebase documents default registration at startup when auto-init is enabled and identifier/config upload on generation. The current app has Firebase Messaging 15.x, while the current public Flutter guide may describe newer registration APIs. Follow the installed SDK contract when implementing; do not copy newer sample APIs blindly. An unselected Dart adapter alone is not proof that native SDK auto-initialization is disabled. No native config, entitlement, init behavior or provider setting changed in this documentation-only checkpoint.

Sources fetched November 22:
- https://developer.apple.com/help/account/keys/create-a-private-key/
- https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns.md
- https://firebase.google.com/docs/cloud-messaging/flutter/get-started

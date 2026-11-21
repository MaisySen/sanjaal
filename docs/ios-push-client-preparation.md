# iOS push client preparation

The existing Firebase project now has the Apple app au.fintex.sanjaal, Firebase app ID1:746380796806:ios:f1cbfec107dd2a210c8207. Project remains Spark, no billing upgrade. HTTPv1was already enabled; its first loading-state text was not the final provider state.

Provider: https://console.firebase.google.com/project/sanjaal-app-3ede9/settings/general/ios:au.fintex.sanjaal
APNs configuration: https://console.firebase.google.com/project/sanjaal-app-3ede9/settings/cloudmessaging/ios:au.fintex.sanjaal

Neither APNs authentication key nor certificate is installed for development or production. No Apple key was created and no notification sent. Native SDK configuration download was requested in the browser, but no file was captured in the working files, so native configuration installation is NOT completed.

ApplePushDevice and FirebaseApplePushBridge are source preparation only, not selected by Push. Existing iOS unavailable behavior stays intact. The bridge requires native iOS configuration and never reuses Android options. APNs readiness is bounded before FCM token creation. Invalidation cancels late APNs work and queues token deletion before a later owner can fetch a token. Tests use synthetic tokens only.

Integration still needs the actual provider-issued native configuration, APNs key/certificate handling under the current grant, actual Xcode capabilities/profile review, consent/auto-init review, client wiring, and reviewed exact-source signed-device foreground/background and account-switch acceptance. No new app build, signing, installation or distribution was performed. Do not claim iOS push is enabled.

Official setup: https://firebase.google.com/docs/cloud-messaging/flutter/client

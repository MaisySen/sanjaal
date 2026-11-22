# iOS/TestFlight and OTA current requirements check

Read-only source and public-document check, November 22, 2026. Not a completed release pipeline, provider selection, App Review determination or upload permission.

## Later compiler evidence and authority clarification

The November22 compiler-only run44998923978 built the current runtime as an iOS
simulator fixture and passed its source/payload collector. Actual toolchain was
Flutter3.50.0, Dart3.14.0, Xcode26.6 build17F113, simulator SDK26.5:
https://github.com/MaisySen/sanjaal/actions/runs/44998923978/job/137135908193
No app launched, no phone binary or stable signing occurred, and nothing was
uploaded. A simulator SDK does not establish the iphoneos archive SDK, export
compliance, signed TestFlight readiness, physical acceptance or an OTA baseline.
The original owner has scoped historical certificate/private-upload authority;
there is no general signing/build prohibition. Existing scopes and the separate
CI-identity, candidate-review, credential, legal and audience checks must still
match the next action. Do not turn this document into a blanket permission hold.

## Current Apple floor versus next announced floor

Apple's current upload requirement is Xcode 26 or later with the iOS 26 SDK or later. Its requirements page also lists iOS 13 as the current minimum deployment target. The submitting page announces iOS/iPadOS 27 SDK and deployment target iOS 15 or later from April 2027. These are different dates and must not be merged into a claim that the later floor applies now.

The project currently declares IPHONEOS_DEPLOYMENT_TARGET=15.0. That meets the stated deployment-target floors, but says nothing about the SDK actually used. Main CI pins Flutter 3.50.0 and builds an unsigned release on macos-latest, without an explicit Xcode selection or SDK assertion. Do not call that an upload-compliant, signed TestFlight pipeline. Before the next authorized release, select a supported stable Xcode/runner combination from actual available runner evidence, pin it and record actual Xcode, SDK and dependency-resolution versions. Recheck Apple's current upload floor at that point. Do not dispatch another native build merely to update this note.

## OTA is not configured

No Shorebird config, dependency or workflow was found in the inspected application/workflow source. Existing native artifacts were not built as Shorebird releases. They cannot be treated as patchable baselines. Expo OTA is not a Flutter integration.

Shorebird is an investigated option, not a chosen or activated provider. Its current documentation states:

- Old login:ci tokens stopped working October 1, 2026. CI now uses an API key; an organization service account with the least required role is the vendor recommendation. Any eventual key must use secure collection and storage, not repository content, logs or conversation.
- Pin the release Flutter version. Patch commands recover that release's Flutter version, but do not pin/install Xcode or CocoaPods for the builder. Match the exact release toolchain and build flags for patches, and pass the exact release version explicitly rather than guessing latest.
- The store upload must be the exact IPA produced by the chosen Shorebird release. Do not rebuild it with stock Flutter/Xcode or let Xcode rewrite the version/build number. The vendor documents manageAppVersionAndBuildNumber=false for export.
- Native code, native plugin, asset and Flutter-version changes need a new store release. Do not waive detected native/asset/build-flag differences to force a patch through.
- iOS patch acceptance needs a physical arm64 device. Simulator testing cannot establish successful patch installation.

Vendor claims of store-policy compatibility are not Apple approval of this app or any future patch. Apple's Review Guideline 2.5.2 restricts downloaded code that introduces or changes features/functionality. Keep an explicit patch-eligibility review and route new features, native/config changes and questionable cases through normal store review. Do not promise unrestricted OTA or use it to bypass review.

## Future promotion sequence, still held

1. Resolve the separate Sanjaal-only Apple identity and its actual app-scoped access without touching the broad existing key or Stampies. Preserve the formal encryption/export-classification hold.
2. Select one reviewed source and its API compatibility/capability evidence. Keep wallet/provider and privacy holds intact. Complete required exact-source CI, pixels and device acceptance under the existing candidate contract.
3. Choose any OTA provider and confirm current cost, account and credential authority before creating an account, obligation, secret or baseline. If selected, build the first exact baseline only after native signing/build permission is grounded.
4. Verify actual signed IPA identity, version, entitlements, privacy strings/manifests, export determination and toolchain. Record hash/provenance. Keep signing and upload as separately approved effects.
5. Upload only after that approval, then verify Apple processing and compliance state before any authorized tester assignment. Upload acceptance is not tester delivery or installation.
6. For an authorized patch, validate exact baseline/version/toolchain/flags, reviewed Dart-only eligibility and API compatibility. Verify on an authorized physical device and arrange rollback/track approval before wider delivery. Existing source-only widget checks establish none of this.

No account, key, secret, provider, native config, workflow, entitlement, dependency or release state changed in this check. No build, signing, upload, installation or distribution occurred.

## Fetched sources

- Apple, Upcoming Requirements: https://developer.apple.com/news/upcoming-requirements/
- Apple, Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- Apple, Submitting: https://developer.apple.com/app-store/submitting/
- Apple, App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Shorebird, CI integration: https://docs.shorebird.dev/code-push/ci/generic
- Shorebird, Releasing for iOS: https://docs.shorebird.dev/flutter-concepts/releasing-flutter-apps/ios/
- Shorebird, Create a Patch: https://docs.shorebird.dev/code-push/patch/
- Shorebird, FAQ: https://docs.shorebird.dev/code-push/faq

Primary regulator/platform and vendor implementation sources were used. No independent legal or compliance verdict is asserted. Local provenance: .github/workflows/ci.yml; app/ios/Runner.xcodeproj/project.pbxproj; app/pubspec.yaml and pubspec.lock; app/ios directory; source/workflow scan for Shorebird. Existing companion holds: IOS_EXPORT_DECLARATION_HOLD.md, PRIVATE_CANDIDATE_PIPELINE.md and ios-push-client-preparation.md.

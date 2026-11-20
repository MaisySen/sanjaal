# iOS encryption implementation inventory

20 November 2026. Implementation evidence for export review, not an exemption, ECCN, legal opinion, or approval to submit. Reviewed app source at42109dcd and the unchanged locked dependencies. The separate declaration-hold change removes an unsupported Info.plist assertion; it does not remove or weaken encryption.

## Verified source paths

| Purpose | Implementation evidence | What is not established |
| --- | --- | --- |
| Saved creator photo/video drafts | `app/lib/creator_media_draft_store.dart` uses AES-GCM with a256-bit key through `cryptography2.9.0`. Encryption/decryption run in a Dart isolate. The native-platform default factory resolves to `DartAesGcm`. | This is not Apple-only or HTTPS-only encryption. No formal export classification is established. |
| Draft keys, tokens and other secure values | `flutter_secure_storage11.2.0`, iOS implementation `flutter_secure_storage_darwin0.4.3`, uses Apple Security Keychain APIs. Default Apple options do not request the optional Secure Enclave path. | Keychain storage of a key does not change the separate draft cipher's implementation or settle exemption. |
| SHA-256 | `crypto3.0.8` is used for owner-scoped draft identifiers and OAuth PKCE challenges. | Hashing is not evidence that the app lacks encryption elsewhere. |
| Calls and community rooms | `livekit_client2.13.2` and `flutter_webrtc1.6.3` are locked. Both app pages create `Room()` without explicit E2EE options. The SDK only sets up its E2EE manager when encryption/E2EE options are supplied. | Do not describe app calls as application-level end-to-end encrypted. Absence of that option is not absence of transport encryption. Negotiated runtime ciphers were not measured. |
| Bundled WebRTC | The exact flutter_webrtc iOS podspec requires `WebRTC-SDK150.7871.04`. Its Swift package declaration names the same precompiled framework and SHA-256 checksum. CocoaPods' spec independently returns that version and archive. The release's iOS arm64 binary includes BoringSSL identity/certificate names, DTLS strings and SRTP AES-GCM/TLS cipher names. | Strings and exposed options are evidence of included crypto-related code, not proof of a negotiated cipher, complete algorithm inventory, or vendor export classification. The final signed release candidate has not been audited. |
| Browser authentication | `flutter_web_auth_2 5.1.0` uses Apple's `ASWebAuthenticationSession` on iOS. | This does not make every other app function Apple-only encryption. |

## Locked archive verification

Downloaded the following package archives on20November2026 and checked each SHA-256 against `app/pubspec.lock`. All matched. These are dependency-source checks, not final-distribution binary checks.

| Archive | SHA-256 |
| --- | --- |
| https://pub.dev/api/archives/crypto-3.0.8.tar.gz | e3626ae6270383c9e3a549f34c9e4cd26c09ae6a9adaab2bf4737a00340efdc4 |
| https://pub.dev/api/archives/cryptography-2.9.0.tar.gz | 3eda3029d34ec9095a27a198ac9785630fe525c0eb6a49f3d575272f8e792ef0 |
| https://pub.dev/api/archives/flutter_secure_storage-11.2.0.tar.gz | d4e1fb6b2cb524868929e78dc0282fa000554b22060fb53789dc481c9fc95bb8 |
| https://pub.dev/api/archives/flutter_secure_storage_darwin-0.4.3.tar.gz | a031ceac9b070e62ef183cd7f7d1a8798ebde402d5049f0fe6eb3a51bd797a21 |
| https://pub.dev/api/archives/flutter_webrtc-1.6.3.tar.gz | b98ef03376401e54ff87fc78907b38e562b15ca8424aba589c263eddc3c1ecf9 |
| https://pub.dev/api/archives/livekit_client-2.13.2.tar.gz | c63211bd5073b308417de2b048809c156f50cb5bda02713150478742be2a1bc1 |
| https://pub.dev/api/archives/flutter_web_auth_2-5.1.0.tar.gz | a7655829251ee63aae64a748f8512f36670d8eba4657b0055cdf5ef304a9d164 |
| https://pub.dev/api/archives/url_launcher_ios-6.4.2.tar.gz | 8faa1aab294f1ab4040b43660c887b0418d5fa4f0cffef76a484e6aa1092eb4a |

WebRTC-SDK source metadata read:
https://trunk.cocoapods.org/api/v1/pods/WebRTC-SDK/specs/150.7871.04

The package declares this framework URL and checksum. Selected metadata, iOS header and iOS arm64 binary entries were read from that release archive using bounded HTTP ranges and ZIP CRC checks, without downloading the686MB multi-platform/dSYM archive in full:
https://github.com/webrtc-sdk/Specs/releases/download/150.7871.04/WebRTC.xcframework.zip

Declared whole-archive checksum:9532fe3ce47507c304f37a4355b907be1e89967971d614a04603005a546249be. GitHub release metadata independently reports that digest; it was not recomputed over the complete archive:
https://github.com/webrtc-sdk/Specs/releases/tag/150.7871.04

The inspected iOS arm64 framework executable is12,346,864bytes, SHA-256096f3b3b907f76feb8c09ccbf48050323ec234d2449840d3026bf58e8c5fcbb8. Its metadata targets iPhoneOS, minimum iOS13.0. The included RTCCryptoOptions header exposes GCM SRTP controls. Binary strings include BoringSSL certificate/identity names, DTLS, SRTP_AEAD_AES_128_GCM, SRTP_AEAD_AES_256_GCM, TLS_AES_128_GCM_SHA256 and TLS_AES_256_GCM_SHA384. This supports treating third-party bundled crypto as part of the review. It does not establish which algorithms execute or the result of formal export review.

## Remaining review before formal declaration

- Confirm intended distribution countries, including France. No answer has been assumed.
- Inspect the final candidate's resolved native dependencies and bundled framework metadata, then reconcile the full crypto inventory with vendor documentation and the applicable official export rules.
- Obtain the source-grounded formal determination and any required documents before adding exemption/classification or approval-code fields.
- Resolve content rights and age/content-policy declarations separately. This inventory answers neither.
- Keep money, production QA and exact-device acceptance/distribution gates intact.

Official Apple guidance already read for this review:
https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations.md
https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/
https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/

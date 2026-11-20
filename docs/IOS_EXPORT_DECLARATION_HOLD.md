# iOS export declaration hold

20 November 2026. App Store registration is not export classification or release
permission. Current saved creator-media drafts use AES-GCM256 in package
cryptography2.9.0, whose native-platform default is DartAesGcm in Dart. Key storage
in the iOS Keychain does not turn that encryption into Apple-only/HTTPS-only use.

The previous Info.plist ITSAppUsesNonExemptEncryption=false was not supported by
a reviewed exemption determination. Removed it rather than guessing true or
false. No approved ITSEncryptionExportComplianceCode exists in this source.
Without a final declaration Apple can ask compliance questions at build upload.
This is intentional, not missing work to bypass automatically. Formal export
determination, linked-library crypto inventory, region scope (including France),
any required documents and approval must be resolved before submission.

A Python plist regression requires the unresolved declarations to remain absent
and preserves identity/permission strings. Exact42109dc historical plist must
fail the no-unverified-declaration assertion. This test is not legal advice,
classification, App Review acceptance, or a substitute for needed documents.
The hold can be changed only with source-grounded verified determination and
corresponding tests/documentation. No declaration made in the developer account.

Official sources read20November2026:
https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations.md
https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/
https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/
Package source:
https://pub.dev/api/archives/cryptography-2.9.0.tar.gz

See IOS_ENCRYPTION_IMPLEMENTATION_INVENTORY.md for the locked package archive and selected iOS framework evidence. This narrows the inventory gap; formal determination and final-candidate review remain unresolved. Isolated8c6213a passed2protected/restored checks and its exact421unsupported-exemption negative before integration.

# Phone preview finalization

Automatic tag publication remains disabled. A compiled CI artifact is not a delivered phone preview. This finalizer does not publish, change repository secrets, deploy API code or activate a provider.

## Required evidence

Select one immutable source commit and its GitHub Actions run. Download the actual run JSON, jobs JSON and `sanjaal-apk` artifact from that run. Require completed success for API, app, unsigned iOS and emulator, not merely the app job. Record the artifact ID, run ID, head SHA and SHA256 of the exact extracted ARM64 input APK in a private artifact-evidence JSON:

```
{"run_id": 123, "head_sha": "the-real-full-source-commit", "artifact_id": 456, "apk_sha256": "the-real-downloaded-input-digest"}
```

Do not substitute a previous green run for a newer source commit. Do not substitute synthetic/tunnel/local-API builds. The fixture native keyboard evidence is the actual adb `poll_native_display.png` plus unmocked native geometry, not Flutter's converted screenshot that omits OS pixels.

## Finalize

Run `.github/ci/finalize_phone_preview.py` with these required flags:

- `--input`: exact downloaded CI ARM64 APK
- `--output`: new versioned APK path that does not already exist
- `--ci-run`, `--ci-jobs`, `--artifact-evidence`: corresponding downloaded evidence files
- `--keystore-base64-file`, `--password-file`: private files containing the existing upload identity and its password, never committed or printed
- `--build-tools`: installed Android SDK build-tools directory
- `--version`, `--version-code`: intended versionName and ARM64 versionCode

The script refuses an incomplete/non-green run, missing mandatory jobs, source/digest mismatch, wrong package/version/ABI, debuggable or backup-enabled app, missing production API or fixture/tunnel markers. It signs only after those checks, using the existing upload identity, then verifies v2/v3 signatures, the expected certificate, 16KB zip alignment and payload again. Private decoded key material lives in an automatically removed temporary directory. The script creates the signed APK, adjacent `.verification.json`, and `SHA256SUMS.txt`. Keep that evidence with the selected source and run. Failure is not a completed preview.

The stable certificate SHA256 is `e6d401f11358c43e232921a088401b9c2aa25eabe4ecd972e17954220d9783a7`, independently confirmed from the existing0.5.1 artifact. The older0.2/0.3/0.4 certificates differ. Do not suggest uninstalling or wiping app data to bypass an update error. Confirm the installed identity and preserve data before choosing an update/migration path.

## Before publication and delivery

Review the selected client against the actual deployed API and capability flags. New member-transfer source requires replay support and disables Send on the older API, while old client previews would fail422 if the new transfer-key requirement is deployed. Do not deploy the new API merely to hide this limitation. Funding/payouts remain off; live secure-store/refresh, camera/microphone, calls/push and two-device behavior need their own proof. Say what is actually usable versus unavailable.

Publish only as a preview with accurate caveats and source/CI/checksum evidence. Then anonymously download the actual published asset and compare every byte's digest/length to the verified local APK. Inspect the user-visible release page and actual download URL. A draft release, successful upload, internal path or CI artifact is not delivered. No signed iOS distribution is implied by an unsigned build.

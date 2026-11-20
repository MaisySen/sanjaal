# Google Play full-build updates

Implemented as a candidate from0.5.4+2009. The delivered0.5.3+2008 has no
in-app update entry and cannot gain one without a new full app installation.
This is not an OTA patch engine. It uses Google's app-update2.1.0 library
through a small Android bridge and a Flutter state controller.

## Behavior

About Sanjaal -> App updates -> Check for updates is manual. Nothing checks
at startup, downloads automatically or launches a forced immediate flow.
Only a newer build available to the current Play account is offered. Google
Play asks for download consent. Sanjaal can stay open during the flexible
download. The separate Restart and install button is enabled only after
Play reports DOWNLOADED, and says to save work first. Each start fetches a
fresh AppUpdateInfo. Native listener registration is scoped and removed.
Returning to the About screen after backgrounding rechecks the download
state. A fresh manual check also recovers a completed download after app
process death. No server-provided arbitrary APK URL or outside-store
installer exists. No storage deletion option is enabled.

Offline, unavailable Play service, lack of Play ownership and disallowed
flexible updates are not mislabeled as 'latest'. The message points to the
connection and the Play account that installed Sanjaal. A successful check
with no newer build says only what Play reports for that account. Cancel,
failed download and failed install stay separate. A successful install
request is not recorded as proof of installation or of preserved user data.
iOS/web do not invoke the Android bridge and show store update guidance.

## Verification levels

- Fake-gateway state tests cover consent, no silent update, restart gate,
  duplicate taps, current/offline/unsupported, cancellation, failure, resumed
  downloads and late-result races. Render tests use labeled simulated state
  at320px width and140% text in light/dark. Not physical-device evidence.
- CI native startup invokes the actual Android check channel. It accepts a
  real result or the bridge's explicit PLAY_UNAVAILABLE error on an unowned
  emulator. Missing registration and timeout fail. It never requests an
  update and is not a Play download/install test.
- Android release APK/AAB and iOS compilation remain required CI gates.
- Still required: install a signed baseline from the approved internal Play
  track, publish a higher-code candidate to the same approved audience,
  verify eligibility/Play account/cert, decline once, download/resume, defer
  restart, explicitly restart, then verify installed code and existing
  account/private drafts/media remain. Also test offline/retry and storage
  failure. This needs a real Play-owned device; fixture success cannot replace
  it. Do not uninstall or wipe to work around a failed upgrade.

## Sources

- https://developer.android.com/guide/playcore/in-app-updates/kotlin-java
- https://developer.android.com/guide/playcore/in-app-updates/test
- https://developer.android.com/guide/playcore/in-app-updates

OTA patches remain a separate unfinished decision: signed patch baseline,
SDK compatibility, quota, code scope, policy and rollback require review.
No OTA provider account, key upload or modified engine was added.

## Unknown-state correction, November21candidate

The bridge now returns raw Play availability alongside its boolean. A successful
transport with UNKNOWN availability is not evidence that no newer build exists.
Only explicit UPDATE_NOT_AVAILABLE can produce the no-newer-build message.
Missing, inconsistent or malformed enum/boolean values show unavailable instead.
Resume preserves CANCELED rather than replacing it with current or a new offer.
A valid downloaded/downloading status still takes precedence over UNKNOWN
availability, without automatically installing or restarting anything.

Focused fake-gateway tests and a historical false-current negative control
exercise this correction. CI Android compilation and image inspection remain
required; none of this proves a Play-owned device download or installation.

Enum sources checked November21:
- https://developer.android.com/reference/com/google/android/play/core/install/model/UpdateAvailability
- https://developer.android.com/reference/com/google/android/play/core/install/model/InstallStatus

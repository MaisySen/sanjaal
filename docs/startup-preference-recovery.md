# Recoverable preference startup

Local source follow-through to original coverage ledger SJ-002 and section 5. No app build, API/provider/data change or deployment.

## Confirmed defect

The real app root awaited AppPrefs.ready but launched preference loads without catching failures. A malformed saved theme reproduced an uncaught TypeError and no recovery page. The negative actual-root log is preserved separately. Failed later fields could also partially update an earlier preference before the full snapshot was valid.

## Correction

Startup waits for both visual-preference reads. A failure presents a controlled English/Nepali error and explicit Retry, instead of an endless logo/unhandled exception. Neither path clears, resets or overwrites storage. An explicit retry reloads the platform preferences rather than merely rereading a stale cached map; concurrent taps share the in-flight guard. App and glass preferences publish each snapshot only after all their own fields were read successfully.

The session restore path remains independent. If the platform read failure also interrupted session migration/restore, a recovered preference read leads to the existing session restore error and its explicit retry. It never silently turns a restore error into onboarding, clears credentials or logs out. No timeout for a platform call that never returns is added; such a native hang remains unverified.

## Evidence

Seven dedicated tests: actual-root platform read failure and explicit reload/duplicate-tap guard; atomic AppPrefs/GlassSettings snapshots; malformed theme, language, onboarding flag, glass amount and reduced-glass flag. Retry recovery uses repaired synthetic preference storage, not a claim that a restart repairs corrupted real storage. No mutation method is allowed in the platform read-failure fixture.

Actual English/dark and Nepali/light error pixels at 320x640 and 1.8 text inspected. Retry is visible and reachable. These are host fixtures, not physical-device/OS storage-failure or native-language approval. Existing connected first-use/auth/restore/Settings tests are rerun separately; counts do not measure startup speed.

# Consolidated next-candidate gate

Prepared November 17, 2026. This is a plan, not deployment approval or a completion claim.

## Scope

The next immutable candidate combines startup restore-error preservation, bounded native video posters and live-query-roundtrip reductions. Keep the current five tabs, non-blocking upload behavior, protected story audience checks, private media boundaries, stable update identity and disabled money paths.

The existing phone build is 0.5.5 (2010), source 68aec83024c80f8d0951a03b79cd6112c4f40074. New source has not been installed on the Samsung. Its remote connection is unavailable; do not poll or use stale frames as evidence.

## Auth prerequisite, prepared but unchanged

A fresh synthetic QA password login requested offline_access but returned no refresh token. Live dashboard inspection on November 17 confirmed that Sanjaal API Allow Offline Access is off. Sanjaal Mobile already enables the Refresh Token grant. Merely preserving an absent refresh token cannot make that login persistent.

Keep the API setting unchanged until the owner-authorized rollout step. Before changing it, re-read the actual deployed and installed secure-store implementation and current client settings, including token expiry/rotation policy. Do not weaken expiry, turn on an unrelated grant, reset accounts or change credentials. After an approved correction, verify with a fresh QA login that a refresh token is issued, perform a refresh without exposing either token, and test secure cold-start restore on the exact candidate. Do not describe historic sign-outs as explained by this one observation.

## Runtime preparation and rollback

- Re-read current service image/configuration and additive migration state through their owning services. Do not use historical documentation as current state.
- Require all exact-source CI jobs: API, Flutter app, unsigned Android bundle, unsigned iOS, actual emulator. Inspect actual native poster and story pixels, not only decoder assertions.
- Use an immutable runtime image identifier. No silent deployment, extra paid service or stack switch.
- Confirm a restorable private backup before additive schema changes. Preserve the money hold in both forward and rollback targets. Roll back code only to a reviewed compatible image; never destructively roll back user data to hide a compatibility problem.
- New poster capability must be absent on an old runtime and true only on the compatible runtime. Legacy videos retain their visible fallback. Verify old and new clients against the selected API before rollout.
- After an authorized deployment, verify health/version, unauthorized denials, protected/public media denials, current feature flags and a bounded synthetic QA post/story/reel upload/read/delete with replay checks. Compare read latency before claiming improvement.

## Candidate finalization and physical acceptance

Only after the exact CI result is green, finalize with the existing stable key and the checked finalizer described in PHONE_PREVIEW_RELEASE.md. Select a new version code after checking current Play state. Do not overwrite a prior artifact or reuse an earlier build's evidence.

No public release, Play upload or phone install is authorized by this preparation document. Before a permitted update, verify the currently installed package/signature and preserve its data. Never uninstall or wipe to work around an update failure.

Required Samsung evidence from that exact candidate: five tabs and Settings; complete post, Only me story and reel journey; upload progress and retry; immediate profile/feed visibility; preserved positions; motion/audio playback; background/process-death restore. Room/call audio, push and the actual Play flexible-update flow remain independent open checks. Deliver short real recordings and an explicit unfinished list. A green emulator is not Samsung acceptance. Keep deposits, transfers and cash-out unavailable until their live paths are independently verified.

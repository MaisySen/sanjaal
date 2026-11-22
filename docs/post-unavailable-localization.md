# Post-unavailable localization

The 404/410 post-detail state used hard-coded English title and explanation even with Nepali selected. Four negative cases demonstrated English copy in Nepali portrait/landscape fixtures. The unavailable state now uses the existing translation path, with Nepali title and explanation added. No availability, retry, permission or visibility behavior changed. Nepali wording remains subject to native-language acceptance.

Twelve new status/language/orientation cases cover 404, 410 and transient 503 at 1.8 text, including Back and retry reachability. The selected post-state/detail/discovery-route/Activity group passed 56 tests sequentially. Focused analyzer is clean. Current Nepali portrait unavailable, landscape unavailable and landscape retry pixels were inspected, with readable complete copy and controls. Earlier English landscape pixels were also inspected. No overflow was demonstrated in these tested shapes, so no layout or scrolling change is claimed.

Separately, the integrated source at prior commit 7d22f4b passed a 14-file connected local batch with 164 tests. That batch combined the recent Home, own-profile, Activity, saved-draft, setup, settings and search corrections with connected creator/tab/profile journeys. It does not include this later translation change and is not native, provider, speed, deployment or complete-product acceptance. Individual group counts overlap with earlier evidence.

All data and HTTP/storage responses were synthetic. No real post was read or deleted; no account/provider mutation, source push, build, signing, installation or distribution was performed.

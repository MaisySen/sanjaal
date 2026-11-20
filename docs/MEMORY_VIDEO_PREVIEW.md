# Recovered encrypted-video preview, candidate only

The accepted96ca910 product preserved encrypted photo/video/story bytes across
native process death but deliberately did not play recovered in-memory videos.
This branch adds a separate native memory-only preview, without a plaintext
playback file or loopback server. It is under test, not production or hardware
acceptance. Failure retains the existing preview-unavailable message.

Android MediaPlayer reads a bounded MediaDataSource byte array. iOS AVPlayer
reads a fixed private scheme through an in-process AVAssetResourceLoader. Both
accept only bytes, not caller-selected paths, origins or external URLs. The
buffer bound is25MiB, matching draft storage. Each platform retains at most one
of these native previews. Opening another retires the old one. The native
surfaces have no persistence or network implementation. Codec/OS internal copies
and decoded memory are not claimed to be securely erased by an application.

There is no autoplay. Explicit Play/Pause is below the native surface. A covered
route or inactive app pauses rather than auto-resuming. Native background hooks
also pause independently of a delayed Dart callback. Retirement, disposal,
failed decoding or a bounded readiness deadline releases the player and source.
The Dart boundary captures exact Session, member and login generation, checks
again after asynchronous byte reads and prevents a late creation from surviving
retirement. Its own transport copy is cleared after native creation. Original
XFile memory remains scoped to the existing review, not a new stored copy.

Story review and recovered video-post review use this path only for the internal
draft-memory URI. Existing local-file story preview is unchanged. Upload policy,
manual-send behavior and attempted-send locks are unchanged. Playing a retained
video is never authority to send it again. No persistent permission, provider or
production configuration is changed.

Planned evidence is separated: fake platform channels for lifecycle ordering,
full app regressions and deliberate guard removal; then one native install,
seeded encrypted drafts, picker-source deletion, process termination and
recovery, exact byte hashes and native decoder playback clocks for post/story.
Synchronized OS captures, not Flutter-only raster screenshots, must show actual
native frames. Native/physical acceptance remains pending until that evidence
has been inspected. No current source is being distributed to a phone or store.

First9365415 evidence:57 focused/1124 full app passes, one live skip,
retirement-removal negative fails and restored6 pass. First iOS run44644882967
has actual colored post/story native frames across same-install process death.
Its Android decoder clock passed but OS captures were black, so Android playback
was rejected. The next candidate uses TextureView rather than a nested
SurfaceView and validates the synthetic pattern's saturated pixels inside the
Flutter-reported preview rectangle on both OS screenshots. This gate supplements,
not replaces, inspection of actual frames and the lifecycle assertions.

Candidatec1db3a1 kept iOS colored frame/process proof with the strict pixel gate;
Android failed that gate at ready, and remains unaccepted. The capture handshake
now keeps Flutter test frames pumping before and while OS screenshots are
requested, instead of blocking inside runAsync. This corrects a possible stale
texture capture in Android's test binding. It is not evidence of playback until
the strict gate and actual image inspection pass on the resulting candidate.

5476a4a disproved the frame-pumping hypothesis as a sufficient Android fix:
its ready native region remained black and was rejected. The following candidate
uses Android hierarchy-level hybrid composition (initExpensiveAndroidView),
keeping the bounded TextureView memory source. The fake platform fixture now
matches that controller's void creation result. The synthetic pattern clip is
20 seconds instead of4, so actual screenshot time cannot consume the entire
clip before Pause is tested; production playback logic is not changed by this.
The pixel gate, explicit manual-play checks and retirement tests remain required.

Evidencee62c825/run44656533328: app57 focused,1124 full passes with one live
skip, retirement-removal failure and restored6 pass. Both native process-restart
jobs pass; all16 OS images inspected. Android's directly composed surface now
shows actual colored post/story frames, with38-45% saturated pixels in its strict
preview-area gate. Android7647 was absent before7850, same UID/package path;
iOS28648 was absent before29974, same containers, one install each. Exact saved
bytes, deleted picker originals, other-owner isolation, manual Play/Pause,
unchanged uncertain-send locks, removal on retirement and zero API calls pass.
This is simulator evidence, not physical Samsung/iPhone acceptance.

A remaining visual defect was caught: the nonexistent pause-circle SVG kept the
old play graphic while playing. The next source uses the existing
pause-circle-fill asset and checks that actual asset in the widget fixture. It
also adds native route-cover/return-paused and same-owner/new-generation
retirement checks. Real OS-background interruption is not claimed from these.

Final scoped native proofa5cd088/run44660377017: both platforms pass the strict
color-pixel gate and9 OS images each were inspected. Pause uses the correct
existing asset, covered route returns paused until explicit Play, and retirement
with the same owner but a new generation removes the native view. Android7534
was absent before7746 with the same package/UID; iOS39053 was absent before40921
with unchanged app/data containers. One install each; no uninstall or data clear.
App57 focused/1124 full passes with one live-only skip, retirement-removal fails
and restored6 pass. This is simulator proof, not physical Samsung/iPhone or real
OS-background interruption proof. Combined current-source CI is still required.

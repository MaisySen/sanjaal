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

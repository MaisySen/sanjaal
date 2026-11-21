# Refractive navigation source preparation

Status: local, default OFF. Based on reviewed reel recovery 7707175. Does not change the frozen Android/iOS artifacts, API baseline, deployment, signing or installation approval.

## Scope

Only the bottom GlassNavBar opts in to a real backdrop sample-displacement shader. `SANJAAL_REFRACTIVE_GLASS` remains false unless explicitly defined. The existing tint, border, blur and selection treatment remain. The shader is composed after the existing blur; it does not render a fake scene behind the bar.

ImageFilter shader support is checked at runtime. Unsupported renderers and failed/loading assets use the existing blur. High contrast and disabled animations bypass refraction. Reduced transparency follows GlassSurface's existing opaque path. Each mounted surface owns its shader; the compiled program is shared. Async completion after disposal cannot attach a filter.

The layer derives geometry at composition, including retained ancestor transforms. A repaint-only implementation was rejected in the isolated prototype because retained movement left stale bounds. This app adapter uses the corrected composition path. Positive uniform scale/translation is supported; rotation, shear, nonuniform or perspective transforms use blur rather than guessed geometry.

## Verification

- App-adapter headless Impeller suite, preparation flag ON: 14 pass. Includes retained and nonretained translations at 1x/2x/3x, changed pixels at moved top/bottom edges, ownership, disable/accessibility/dispose and rotation fallback, actual HomeShell navigation at 390 light/1.0 and 320 dark/1.8 text.
- Ordinary software/default-OFF reviewed product + glass + ownership suite: 132 pass, 1 explicit skip for renderer-dependent rotation. This retains the previous 113-test product scope and adds existing glass and adapter ownership coverage. Counts do not measure performance.
- Separate actual HomeShell ON/OFF Impeller scenes pass at both viewport/text settings. Software with flag ON falls back without a lens and passes both scenes.
- Changed-file analyzer clean.
- Actual rendered HomeShell captures inspected. A first intermediate-frame selection concern was resolved with matching settled ON/OFF captures; selected Reels background is present. Static media is a licensed image fixture, not native video.

The actual HomeShell capture test reuses existing local PR fixture helpers and local font/image resources. It is an evidence harness, not a portable CI claim. Geometry and ownership tests use procedural pixels and packaged shader assets.

## Open acceptance

This is source preparation, not activation or exact-reference acceptance. No native product build was made. Headless Impeller is not a phone GPU. Physical-device moving-video texture composition, GPU frame times, battery, visual strength, route transitions and native accessibility remain unaccepted. Existing blur adds cost; no performance improvement is claimed. Do not enable by default or present as included in frozen builds without the separate device/release gate.

The older isolated prototype v2 archive predates its retained-transform correction. This app packet contains the later corrected composition adapter and its app-level tests; it does not rewrite the older archive's provenance.

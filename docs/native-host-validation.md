# Pinned native host validation

Run45073584076 failed on macOS26-arm64 image20261117.0516.1 when two45second
simctl screenshot attempts stalled at Reels. No native UI assertion failure or
crash is established. Do not extend the timeout again as a claimed fix.
https://github.com/MaisySen/sanjaal/actions/runs/45073584076

The next isolated simulator experiment uses standard macos-15 arm64,
Xcode26.3 build17C529, simulator SDK26.2 and an available iPhone17Pro/iOS26.2.
Before compilation it asserts the actual host/architecture/Xcode/SDK; mismatch
fails instead of falling back. All other steps, runtime, dependencies, frame
requirements and finite capture/driver/job limits remain unchanged. The runner
image itself can update; these assertions do not pin a VM image digest.

This choice is supported by current official inventory and a separate open
screenshot issue in the newer runner family. That report corroborates a possible
host issue but does not prove our cause or guarantee the alternate host works.
https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-15-arm64-Readme.md
https://docs.github.com/en/actions/reference/runners/github-hosted-runners
https://github.com/actions/runner-images/issues/13830

Five local preflight positive/negative cases pass.13export/22monitor checks pass.
Actual native success and pixel review remain required. This is not a signed
archive, latest-device acceptance, store compliance or private phone delivery.

# Recovered-video channel failure containment

A failed play/pause command was previously ignored. A state response could wait
forever after readiness canceled the initial deadline. This follow-up bounds
control/state waits to three seconds and retires the preview on an error or
timeout. Disposal remains best-effort, never proof of physical native shutdown
or secure erasure. The selected encrypted draft is retained with the honest
unavailable-preview fallback. No automatic retry, autoplay, filesystem decode,
network media, production or distribution change.

Tests cover play/pause/state errors and unresponsive responses, late completions
after terminal retirement, and covered-route pause failure. A historical-source
negative requires the old swallowed-pause behavior to fail the new contract.
Native implementation unchanged. Existing actual Android/iOS recovery evidence
belongs to its source; whole combined/native verification remains separate.

Isolated2c0a2ae passed64focused,1182full/one live-only skip and13restored.
Historical663 pause-error negative failed on missing disposal as intended.
https://github.com/MaisySen/sanjaal/actions/runs/44712533401

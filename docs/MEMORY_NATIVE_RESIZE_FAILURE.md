# Android memory video resize failure containment

20November2026. Source audit found that the TextureView size-change callback called fitVideo outside a try/catch. Setup and prepared callbacks were contained, but a later native transform failure could escape this callback.

The size-change callback now returns when retired or failed and catches transform errors through the existing terminal fail/cleanup path. Private bytes are not written anywhere new. Playback does not restart automatically. Native disposal is best-effort, not hardware-off or secure-erasure proof.

The harness executes the actual production Kotlin adapter with deterministic Android/Flutter fakes. A transform fault after explicit play must latch failure, remove readiness, attempt player/display release, clear the source and hide the surface. A second size callback cannot revive the retired player. Local17protected/restored cases pass; all6negative controls fail for their intended reason, including exact5280d57historical resize with an uncaught transform error. This is not evidence that an error occurred on a physical device.

Isolated CI and exact Android restart acceptance still need review before integration. Preserve Samsung/real-device, production, money and distribution gates.

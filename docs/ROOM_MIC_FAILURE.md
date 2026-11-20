# Uncertain native microphone changes

Audit found that RoomMicrophone.toggle propagated an adapter failure without
reconciling the physical capture state. An enable can take effect before its
acknowledgement fails. The old path retained muted=true and allowed another
enable without any explicit stop. A failed manual mute also skipped the
uncertain-stop guard already used by host revocation.

This candidate attempts native disable in the same serial queue slot after any
failed toggle, before permitting another enable. A successful cleanup records
muted; failed cleanup latches stopUnconfirmed and blocks enables. RoomPage uses
its existing uncertain-stop notice and disconnect attempt for this failure too.
Busy stays true through cleanup. Revoke/close remain ordered after the slot.

Five new fake-adapter cases cover enable/mute errors, confirmed versus failed
cleanup, blocked regrant/retry and revocation during cleanup. A negative control
restores the old toggle and must fail the enable-cleanup regression. These are
source ordering contracts only, not proof of real microphone-off, LiveKit or
physical-device behavior. No real room, call or recording occurs.

8f239ab passes75focused/1137full(one live skip),22restored policy cases;
old-source negative confirms missing disable after failed enable. Next candidate
also bounds/scrolls the room error text and fixes Back below it. Four actual
RoomView smallportrait/landscape light/dark1.8x tests require visible actionable
exit, hidden media controls, final warning line readable and real route pop.
An old-layout negative must reproduce overflow. No actual microphone state is
claimed from these offline contracts.

6e0e76f verified79focused/1141full(one live-only skip),26restored. Both
negative controls distinguish old behavior: missing native disable and84pixel
room error overflow. All four error renders and both consent renders inspected.
Back remains fixed/actionable and returns to room list, complete final warning
readable after scroll. No actual microphone/device-off proof.
https://github.com/MaisySen/sanjaal/actions/runs/44696631140


## Conservative SDK acknowledgment boundary

A later audit of the exact locked LiveKit 2.13.2 archive matched SHA-256
c63211bd5073b308417de2b048809c156f50cb5bda02713150478742be2a1bc1.
Source: https://pub.dev/api/archives/livekit_client-2.13.2.tar.gz
`LocalTrack.mute` can return early when its own muted flag is already true;
`LocalTrack.stop` can log native stop errors rather than propagate them.
Accordingly, an off callback returning is not sufficient to reconcile a prior
failed toggle. Every toggle failure now permanently blocks re-enable in this
RoomMicrophone instance, preserves the uncertain-stop latch after later revoke,
and causes the existing page failure/disconnect path. A verified host grant or
explicit startHost cannot clear this terminal condition. Cleanup is still
attempted in order, but never reported as physical-off proof.

The previous ordered-retry policy is superseded. An exact afd source negative
control reproduces a second enable after successful high-level cleanup; the new
regression requires no second enable. The existing native-off and layout
negative controls remain. This is source/adapter containment, not a measured
hardware leak or verified shutdown.

The terminal callback notifies the page before a potentially slow off attempt;
its existing failure handler requests disconnect without waiting for that off.
A regression holds cleanup open and checks this notification ordering and busy
lock. Historical-source negative controls omit only that callback-specific test
while compiling against the historical constructor, restoring the full test
file before restored/full checks.

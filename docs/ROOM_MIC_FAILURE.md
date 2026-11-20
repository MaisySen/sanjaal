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

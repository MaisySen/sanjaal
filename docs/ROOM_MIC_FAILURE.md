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

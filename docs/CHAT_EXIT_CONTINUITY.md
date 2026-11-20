# Chat route-back continuity candidate

This corrects an observed source gap: the old route-back guard covered attached
retry copies only. Typed text, reply selection and failed text copies could be
lost by back navigation. Text still sending was outside its busy condition.

The guard now tracks text changes and protects unsent text, reply selection and
local unconfirmed copies. Stay leaves the composer and retry identity unchanged;
Leave explicitly abandons only on-screen copies, never a possibly delivered
server message. Pending sends block back navigation. An active recording must
be finished or canceled using its existing controls; this is not a background
recording or automatic send feature. The picker must close before leaving.

No persistence, automatic retry, cloud draft, server mutation or production
change is added. Process death still loses this in-memory chat work. Existing
account/session retirement continues clearing the old screen. English/Nepali
copy is provisional pending native editorial review.

The isolated workflow tests actual ChatPage route navigation with synthetic
responses, the existing retry and session tests, a historical unguarded-exit
negative control, full Flutter regressions and four320px/180%text prompt images.
Passing tests alone does not settle pixels or physical-device behavior.

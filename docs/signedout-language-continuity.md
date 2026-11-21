# Signed-out language continuity

Separate local follow-through to SJ-003, SJ-006/008 and SJ-104. Based on welcome-existing-options 566246e. No new product build, provider/data change or credential persistence.

Actual-root regressions confirmed that changing locale erased entered sign-in and registration values because the root keyed the whole form subtree by language. The corrected root keeps a stable signed-out subtree while preserving the existing signed-in locale rebuild and account-generation ownership behavior. Sign-in and registration now open the same language destination while idle. Opening it masks a visible password and clears stale translated errors; returning retains identifier, username, password and form mode in the original controllers. No values are copied into a preference or new persistent store. Controls remain unavailable while auth is pending.

Two actual route/change/back cases first failed on the prior root with erased fields, then passed after the correction. Both also verify password visibility is masked on return. Combined startup/entry/auth/restore/settings/glass suite: 117 pass. Changed-file analyzer clean. Actual English/light and Nepali/dark large-text auth pixels inspected; language action is readable and forms remain scrollable with the simulated inset. These do not prove native keyboard, autofill/provider behavior, translation approval or physical-device performance.

The earlier welcome document's statement that auth language remained absent is superseded only by this separate patch. Frozen builds and all release gates remain unchanged.

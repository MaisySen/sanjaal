# Atomic account-view payload validation

Eight synthetic old-source negatives reproduced a client account-state error. With a malformed optional `features` container (list, boolean, string or number), `_loadMe` threw a type error only after assigning the new identity and current account-view generation. Fresh login looked current despite the failed read. Replacement login looked current with the second identity and first-account follower/discovery flags. No live cross-account data disclosure or backend enforcement bypass was demonstrated.

The optional feature container is now validated before committing identity or generation. Invalid payloads raise the existing typed recovery error, retain the blocked account-view state and allow the existing retry to read a valid current payload. Successful recovery with absent features clears prior optional capabilities. Default-off flags and provider selection are unchanged.

Eight dedicated payload cases plus existing account-recovery, refresh/session restore, registration and follower groups passed 83 tests after adding an actual-root malformed-feature replacement case. The root case confirms the previous HomeShell is not reopened, the recovery screen appears and retry uses the current grant without another password exchange. Focused analysis is clean. Current English/light and Nepali/dark recovery captures at 320x640/1.8 text were inspected; message and retry control are readable. This is local synthetic evidence, not native secure-storage, provider or physical-device acceptance.

No backend rollout was reopened. No source push, real login/account operation, native build, sign/install/distribution or provider change occurred.

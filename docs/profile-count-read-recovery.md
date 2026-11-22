# Profile count read recovery

Two old-source synthetic refresh cases showed own and other profiles assigning a string count into the displayed snapshot, then throwing a numeric-cast error in the UI. After count-read validation was introduced, a separate pre-placeholder negative showed the own-profile failed first read still displaying three zeroes despite having no confirmed count snapshot.

Own/other profile count reads now reject nonnumeric, negative or nonfinite present values before replacing the existing snapshot. A malformed refresh keeps the last readable counts and offers the existing retry. Missing/null fields keep the existing partial-response behavior; this is not a full profile-schema or server identity validation change.

Own-profile counts use '-' until a count snapshot has loaded, with an accessible 'Unavailable' label, instead of treating an unconfirmed first read as three successful zeroes. Current identity and independent Edit/Saved routes remain available. A later successful retry displays returned counts normally. Loaded zeroes remain legitimate zeroes.

Eight new cases cover EN/NE unknown-count recovery plus own/other string, negative and boolean count refreshes, retained snapshots and successful retry. Selected count/profile-journey/own-profile-route/other-profile-entry groups passed 64 tests. Analyzer has no errors/warnings and one unchanged informational underscore lint in the editor. Actual narrow 1.8x EN/light and NE/dark first-read recovery captures were inspected: error, retry, unknown counts, identity and profile controls remain readable and scrollable. This is not final reference/native acceptance.

No live profile change, account operation, relationship read/write, native build, source push, signing/install/distribution, backend rollout or provider action occurred.

Follow-up: [profile identity read recovery](profile-identity-read-recovery.md) adds identity binding and action gating. Older own-profile fixtures were corrected to the signed-in identity and count/recovery checks rerun. The earlier count tests were not owner-identity evidence.

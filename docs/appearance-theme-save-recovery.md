# Theme preference save recovery

Separate local SJ-103 follow-through, based on signedout-language-continuity 5875ad80. No build, signing, upload, deployment, account mutation or artifact change.

A real method-channel rejection reproduced that AppPrefs.setMode completed successfully despite a false platform write result. It now rejects that result. Appearance uses a stateful extracted destination to catch thrown or rejected theme writes, preserve the temporary visual choice, explain that it was not saved and allow explicit selection/retry. Duplicate theme taps while saving do not write twice. No setting is cleared or reset.

Three dedicated checks cover the preference contract, false writes and thrown platform errors, duplicate taps and successful explicit retry. Combined startup/entry/auth/restore/settings/glass regression run: 91 passed. Changed-file analysis has only the pre-existing unnecessary_import info in ui.dart. Initial negative harness lacked binding initialization; that harness error is not the reproduced product defect. The subsequent negative shows the expected rejection missing from the old source.

Actual English light/dark failure pixels at 320x640 and 180% text were inspected. Failure text and selected theme actions remain readable, lower content scrolls. A first capture included the test debug banner; final captures omit it. Nepali error copy is supplied but has not had native-language review or a new Nepali pixel check. Host static layout is not native storage persistence, platform theme behavior or performance acceptance.

Scope refinement: only theme persistence is corrected. Existing glass transparency/reduced-glass setters are unchanged and their write-error recovery remains open. Slider interaction needs separate treatment rather than freezing it during every write. Existing language handling is unchanged.

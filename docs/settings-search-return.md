# Settings search and subpage return

Local synthetic correction for SJ-102. No live account settings, notifications, email requests or data deletion were performed.

Negative widget fixtures demonstrated that invoking the same settings destination or nested notification Activity callback twice pushed two routes. The route now holds an opening lock until that destination returns. A current callback can open again after Back, but a retired same-member login callback cannot open a new destination. Existing session-bound checks remain in place.

Settings search now has an accessible, localized Clear search action, including for whitespace-only input. It clears both the visible field and filter. Localized option labels still match, and returning from an option retains the entered query. The empty state remains distinct from normal grouped settings. This does not add new account privacy controls or change their capability gates.

Five new widget cases cover route duplication, reopening after Back, retained callback ownership and English/Nepali search recovery. Settings-search, settings-session boundary, push-status render, blocked recovery and glass-save recovery suites passed 45 tests sequentially. Focused analyzer is clean. An earlier command included two nonexistent test paths; its partial pass is not used as green evidence.

Inspected actual English/light and Nepali/dark empty and restored-group captures at 320x640 logical size and 1.8 text. Search, clear action, empty message and restored rows are readable; long query text scrolls horizontally within the field. This is not native keyboard, live notification or full settings acceptance.

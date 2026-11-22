# Search-result callback ownership

Local synthetic correction only. No live search, account change, report, backend deployment, native build or distribution.

The search page already cleared results when its session retired, but retained person/tag callbacks could still push destinations using a replacement login. Negative widget fixtures observed a UserProfilePage or HashtagPage after same-member replacement. Another negative case observed an old person destination after editing the query, before the next debounce.

Callbacks now capture the rendered result revision and require the opening session to remain active, no in-progress query and the same revision. A route-opening guard rejects a duplicate callback while that destination is open; returning releases it. Existing layout and read sequence logic are unchanged.

Five dedicated cases cover retained person/tag callbacks, edit-time invalidation, current destinations, duplicate opening and reopening after Back. Search callback, discovery-session and localized-search suites: 21 passed in one sequential run. Focused analyzer clean. Re-inspected generated English/light and Nepali/dark search-result pixels at 320x640/1.8 text: query, clear, tags, identity and following label readable. This is not native or full search acceptance and establishes no live exposure.

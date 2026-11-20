# Discovery routes belong to their opening session

Notifications and Search now bind to the Session object, member ID and login generation that opened them. A changed session permanently retires the route, using the existing reviewed account-retirement screen. Notifications clear loaded activity; Search clears private queries/results, invalidates request ordering and cancels queued debounce work. Late read responses cannot repopulate either page. Opening a new route in the current account is required.

Twelve synthetic regressions cover loaded and pending content, same/other-member login, returning to the original account, queued search before a request exists, and replacement Session objects with matching member and generation. Existing discovery journey coverage verifies ordinary search and notification behavior. The historical search negative requires the old screen to retire at the queued-query boundary. No production reads or mutations occur in these tests.

The retirement screen is shared with the previously inspected profile/chat/story boundary, with no new wording or layout. Source checks and emulator tests are not physical acceptance or distribution authority.

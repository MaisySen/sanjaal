# Member actions keep their opening login

A routed member profile now retires permanently on Session object, member, generation, or target-username change. It clears loaded profile data and read errors, removes profile feed descendants, and rejects follow, message, moderation-menu, and refresh actions. Late requests cannot change a replacement route or show an old success/error. Returning to the same member requires a new route.

Shared report and block flows capture their opening member/generation and listen throughout the dialog and request. A changed login removes only their exact dialog route, suppresses stale result/error notices, and returns false for an old block. The member route supplies its own ownership check to handle a replacement Session object too. Backend effects already sent before retirement are not undone or replayed.

Tests use only synthetic sessions and HTTP replies. Historical loaded-profile and missing-dialog-listener negative controls must fail through real assertions, then restored focused tests and the full suite must pass. Emulator/hardware, production delivery, real moderation and two-device acceptance remain separate gates.

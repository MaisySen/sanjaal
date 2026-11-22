# Activity destination ownership

Local source correction. No live notification, push token, account change, profile read or post read was performed.

Retained notification-row callbacks previously looked up navigation through disposed row contexts after a replacement login or screen disposal. Negative fixtures raised a deactivated-widget exception for both profile and post callbacks. A repeated current-row callback also pushed duplicate destinations, and a retained row could navigate after a successful refresh replaced the row list.

Navigation now runs through the owning page state. It requires a mounted active opening session, the exact row still present in the current list, and no destination already open. The lock releases on Back. A failed refresh leaves the previous valid list and its destinations available; a successful replacement invalidates old row callbacks. This does not change notification contents, fetching, pagination, privacy or push capabilities.

Eight dedicated cases cover same-member and other-account transitions for profile/post rows, duplicate opening and reopening, a current follow destination, list replacement and disposal. The selected Activity/discovery/session/localized-render/settings-return group passed 45 tests sequentially. Focused analyzer is clean.

Inspected current English/light recovery-list and Nepali/dark scrolled recovery-list captures at 320x640 logical size and 1.8 text. Retry, actors, action text and content remain readable; the scrolled top row is clipped at the viewport as expected. This is mocked widget evidence, not actual notification delivery, native/device, live-account or full-product acceptance.

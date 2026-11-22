# Home entry ownership

Local synthetic correction. No real compose, live account/provider work, push wiring or deployment.

Home's post lists were session-bound, but its parent header and empty-Following actions were stateless navigation callbacks. Seven verified negative widgets showed Search/Notifications callbacks opening after other-account or same-member login, duplicate destination routes and duplicate compose callbacks.

FeedPage now binds its state to the opening session using the existing session-bound lifecycle. Search, Notifications, empty-Following discovery and compose reject retired or disposed ownership and share an opening lock. Returning releases the lock so current callbacks can open again. Tab layout, feed lazy state, discovery selection and privacy/capability settings are unchanged.

Eleven dedicated cases cover current and retired entry points, duplicate opening/reopening, compose single-flight and localized retirement rendering. The selected Home/first-use/tab/connected-first-use/connected-media/post-card group passed 47 tests sequentially. Focused analyzer has no errors or warnings and two pre-existing informational lints outside the changed Home entry section.

Inspected actual current EN/light and NE/dark retirement captures at 320x640 and 1.8 text, plus the connected first-post/Home capture. Recovery copy and action are readable; current Home header, tabs, post and glass navigation remain visible. This is mocked widget evidence, not physical-device performance, native media, production or complete-product acceptance. No native build, signing, installation, source push or distribution occurred.

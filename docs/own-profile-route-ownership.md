# Own-profile route ownership

Local synthetic source correction, not live account/provider or device evidence.

The Me tab's page state was not session-bound even though its child post lists were. Verified negative widgets showed Settings, Edit profile and Saved callbacks opening destinations after other-account or same-member replacement sign-in. Repeated callbacks pushed duplicate destinations. A pending own-profile count read could leave the same page presenting a replacement username with the old page's count state. The fixture demonstrated mixed page ownership, not a confirmed production incident.

Me now uses the existing permanent session-bound lifecycle. Retirement clears count/error state and invalidates outstanding reads. Read results, publish callbacks, Settings/Edit/Saved/member-list routes and compose callbacks require the active opening session. Navigation is single-flight until Back. Edit-return count refresh is separate from the navigation lock, so a slow read does not block Settings after Back. Existing capability gates and current profile layout remain unchanged.

Fourteen dedicated cases cover retained callbacks, duplicate routes and reopening, pending reads, single-flight compose, edit-return slow refresh and English/Nepali retirement rendering. The selected own-profile/profile-editor/profile-journey/follower-list/connected-first-use group passed 95 tests sequentially. Focused analyzer has no errors or warnings and one existing informational underscore lint in the unchanged editor avatar builder. A first negative run had an invalid Settings tooltip finder; the corrected fixtures were rerun against the old source and all ten behavioral negatives failed for the expected route/state reasons before final validation.

Inspected actual current English/light and Nepali/dark retired own-profile captures and the current English/light normal profile at 320x640 with 1.8 text. Recovery copy/action and profile controls remain readable. Full-product, native account-switching, signed device and live provider acceptance remain open. No source push, build, signing, installation, distribution, account mutation or data deletion occurred.

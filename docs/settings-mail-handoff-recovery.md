# Settings mail handoff recovery

Local client correction, following the current settings flow. No email app, email message, account deletion, live support request, API change or native build was performed.

## Demonstrated defects

Five initial synthetic platform-channel fixtures were run against the unchanged 8661 source. Four failed: both contact and deletion entry points let a native launcher exception escape without recovery; repeated contact/deletion callbacks opened three composers while the first was pending; and a retained covered-route callback could open a composer outside its owning screen. The existing same-member session retirement case already passed. Two early fixture-finder failures were corrected before this negative-source run and are not product evidence.

## Correction

Contact and deletion share one pending-launch lock. They preserve the existing recipient, subject and deletion-request body, including the original username snapshot. A current screen can retry after completion. Retained callbacks cannot launch while the screen is covered or retired. False returns and native launcher errors show the same fallback only while the initiating screen and session still own the result. Disposed, covered and replacement-login completions do not show feedback on another screen.

Fallback instructions now use the existing translation path, with English and Nepali messages. This does not make deletion self-service or confirm that an email was sent. The deletion subtitle now says it opens a draft in the member's email app, with matching Nepali copy. Both languages avoid implying that the request has already been sent. The visual fixtures assert the new handoff wording and reject the earlier send-claim wording.

## Verification

Eleven new widget fixtures cover launcher exceptions, false results and retry, repeated contact/deletion actions, correct mailto parameters, covered callback rejection and return, disposal, replacement same-member login, and English/light and Nepali/dark fallback rendering. The settings-mail, settings-search, settings-session and blocked-recovery suites passed all 45 tests sequentially. Focused analysis of settings_page.dart and the new test file reported no issues. Including ui.dart also reports its pre-existing unnecessary foundation import, not a new warning introduced here.

Inspected all four actual 320x640 logical captures at 1.8 text scaling. The contact and deletion fallback messages fit and the email address remains complete in each fallback. The existing contact-row subtitle wraps across lines at this scale. These are offline widget frames, not native keyboard, installed-device, email delivery or deletion-service proof.

The delivered identity review remains separate and unchanged. No proposed logo or launcher asset was applied. Native distribution and API/backend rollout gates remain unchanged.

# Existing language and legal access before signup

Local source follow-through to SJ-003 and plan sections 5/6. No new brand direction, policy wording, consent checkbox or provider configuration. No product build, deployment or data mutation.

Fresh welcome now exposes the existing language destination and the existing About/privacy/terms destination before a person creates an account. It retains the same welcome content, Create account and Sign in. Back from either option returns to welcome without marking onboarding complete. Only the explicit existing account action continues to auth.

The language page is shared with Settings, rather than a second language implementation. A failed or rejected preference write shows that language changed only for the current session and offers choosing it again to retry. Duplicate taps while saving cannot start competing writes. The underlying setter now checks a false storage result rather than treating it as success. This does not promise that local device preferences sync between devices.

The existing About content is unchanged. Exposing it does not certify current policy accuracy, legal adequacy or native translation. Those broader reviews remain open. Existing-member auth has no new language control: its current language-keyed root would discard entered form state, so that journey requires a separate preservation design and verification before exposing one.

Three dedicated fixtures cover rejected language writes/explicit retry, actual-root language/legal/back/signup at 390 English/light and 320 Nepali/dark/1.8 text. The legal list is scrolled to Terms, not assumed mounted. Early test captures/taps during route transitions were rejected and replaced with settled route checks. Host pixels were inspected, not physical-device or native-language acceptance.

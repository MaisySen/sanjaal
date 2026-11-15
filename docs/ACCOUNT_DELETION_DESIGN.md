# Account deletion: internal design (not implemented, nothing promised to users yet)

Publisher: Fintex Australia Pty Ltd. Status: design with open decisions. No release text may promise full erasure until the open items below are settled.

## Store requirements (official sources, read Nov 16 2026)

- Apple, App Review Guideline 5.1.1(v): apps that support account creation must let people start deletion inside the app. Deleting removes the account record and associated data the developer is not legally required to keep. Deactivation alone is not enough. Reauthentication and confirmation steps are allowed. If deletion takes time or some data is kept, tell people what is kept. https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion/
- Google Play, User Data policy: an app that lets people create an account must give an in-app path to delete the account and associated data, plus a web link where deletion can be requested, and the Data safety form deletion questions must be answered. https://support.google.com/googleplay/android-developer/answer/13327111

## What an account touches

users row (name, username, email, phone, bio, avatar), auth0_sub (Auth0 user), posts, reels, comments, reactions, follows, blocks, stories, conversations and messages, media in B2, coin ledger entries, gifts sent and received, topups (eSewa references), push tokens, call history, room participation.

## Proposed flow

1. Settings > Account > Delete account. Plain explanation of what is removed, what is kept and why, and how long it takes.
2. Reauthenticate (password sign in again, or the social provider for social accounts).
3. Type the username to confirm. Then call DELETE /v1/auth/me.
4. Server marks the account pending, signs the user out everywhere (revoke refresh tokens), hides the profile and content at once, and queues the removal job.
5. Removal job: delete media files in B2 and their rows, delete content, messages the user sent, follows, blocks, tokens, history. Anonymise the users row (no name, email, phone, username replaced by a random handle).
6. Web page on the project site with the same request path for people who cannot open the app (Google requirement).

## Open decisions (need grounding before any code ships)

1. Coin ledger, gifts and topup records: the other party's balance and payment records may need to stay, with the deleted user shown as "deleted member". Whether any of it is legally required to keep, and for how long, is not established. Needs the owner and, for tax or payment rules, professional advice. No retention period is stated anywhere until this is settled.
2. Remaining coins: no cash out exists. Decide what happens to a positive balance (warn and confirm forfeiture, or block deletion until spent) and have the owner approve the wording.
3. Auth0 user removal needs a Management API token with delete:users scope. Not available. Until it exists, deletion cannot honestly claim the sign in identity is gone.
4. Backups and logs: Aiven backups and Render logs age out on their own schedules. State that plainly, with figures taken from each provider's current documentation.
5. Messages the user sent to others: delete for everyone, or keep as "deleted member"? Pick one and say so in the in-app text.
6. Group rooms and shared content (comments on other people's posts): delete or anonymise.

## Testing plan

Run only on synthetic fixture accounts in the local isolated API (api/tests/E2E) and PHP feature tests. No deletion is run against live users. Deletion on the live service ships only after the open decisions are settled and Main and the owner approve the final wording.

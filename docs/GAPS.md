# Functional gaps and reconciliation

Status of features from the design review against what is built. Updated with each batch. A missing backend endpoint is a gap to build, not a sign the feature is unwanted. Renders from fixtures are structural evidence only. No item here has been run on a device.

| Area | Built in the app | Gap |
| --- | --- | --- |
| Home feed | Photo cards with rail (react, comment, gift), plain cards for text and video | Save (post menu), Saved list (Me) | Full-bleed pager and Share to chat not built. Save is in the post menu, not a rail button |
| Create | Create sheet, composer, video picker, story picker | In-app camera recording for Reel and Story: not built |
| Group chat | Group info with member list, Add people (by username), Leave group, owner handoff on leave | Rename and member roles not built. API and app are tested locally (PHP feature tests and a mock-client widget test); not deployed or run against live. Earlier messages, reply quotes and live payloads are filtered by join time (tested). Chat media URLs are unguessable but unauthenticated capability links, so someone who already holds one keeps access after leaving; a new member cannot learn earlier ones, and revoking old links is not possible without moving chat media behind authenticated fetches |
| Calls | Voice and video over LiveKit, history with missed state, glass control tray | Live call not exercised on a device, no minimise to a floating tile |
| Wallet | Balance, history, Send, Add coins and Cash out shown as not available | Top up and cash out providers not integrated |
| Live rooms | Host, speaker, raise hand, gifts | Host raise-hand sheet restyle not reviewed |
| Offline states | Error and retry on lists | Unsent message and offline banner states not restyled |
| Language | English and Nepali strings | Nepali strings need native review |


# Functional gaps and reconciliation

Status of features from the design review against what is built. Updated with each batch. A missing backend endpoint is a gap to build, not a sign the feature is unwanted. Renders from fixtures are structural evidence only. No item here has been run on a device.

| Area | Built in the app | Gap |
| --- | --- | --- |
| Home feed | Photo cards with rail (react, comment, gift), plain cards for text and video | Save, Saved list (Me), Share to chat (post menu) | Full-bleed pager not built. Save and Share are in the post menu, not rail buttons. Shared card render-checked in the chat screen at standard and 1.8x text (fixture, not device) render |
| Create | Create sheet, composer, video picker, story picker | In-app camera recording for Reel and Story: not built |
| Group chat | Group info with member list, Add people (by username), Leave group, owner handoff on leave | Rename and member roles not built. API and app are tested locally (PHP feature tests and a mock-client widget test); not deployed or run against live. Earlier messages, reply quotes and live payloads are filtered by join time (tested). Chat media is now served only through a signed-in, membership-checked route and never through the public media address. Untested: the Backblaze path (chat files in B2 are fetched by the server so the bucket token never reaches a client) |
| Calls | Voice and video over LiveKit, history with missed state, glass control tray | Live call not exercised on a device, no minimise to a floating tile |
| Wallet | Balance, history, Send, Add coins and Cash out shown as not available | Top up and cash out providers not integrated |
| Live rooms | Host, speaker, raise hand, gifts | Host raise-hand sheet restyle not reviewed |
| Offline states | Error and retry on lists | Unsent message and offline banner states not restyled |
| Language | English and Nepali strings | Nepali strings need native review |


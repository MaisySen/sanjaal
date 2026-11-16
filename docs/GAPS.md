# Functional gaps and reconciliation

Status of features from the design review against what is built. Updated with each batch. A missing backend endpoint is a gap to build, not a sign the feature is unwanted. Renders from fixtures are structural evidence only. No item here has been run on a device.

| Area | Built in the app | Gap |
| --- | --- | --- |
| Home feed | Photo cards with rail (react, comment, gift), plain cards for text and video | Full-bleed pager, Save, Share to chat: not built, no backend for save |
| Create | Create sheet, composer, video picker, story picker | In-app camera recording for Reel and Story: not built |
| Group chat | Group info with member list, Add people (by username), Leave group, owner handoff on leave | Rename and member roles not built. New API routes and PHP tests were written without a PHP runtime here, so they have not been run; the app side is tested against a mock client only |
| Calls | Voice and video over LiveKit, history with missed state, glass control tray | Live call not exercised on a device, no minimise to a floating tile |
| Wallet | Balance, history, Send, Add coins and Cash out shown as not available | Top up and cash out providers not integrated |
| Live rooms | Host, speaker, raise hand, gifts | Host raise-hand sheet restyle not reviewed |
| Offline states | Error and retry on lists | Unsent message and offline banner states not restyled |
| Language | English and Nepali strings | Nepali strings need native review |


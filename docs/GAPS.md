# Functional gaps and reconciliation

Updated November 17, 2026. Source, deployed API, published APK, fixture tests and genuine device tests are different states. See [VERIFICATION_STATUS.md](VERIFICATION_STATUS.md) for current evidence. The full app is not complete.

| Area | Built | Remaining gap |
| --- | --- | --- |
| Home feed | Photo/text/video posts, reactions, comments, gifts; Save, Saved list and Share to chat; vertical one-post pager | Fixture emulator checks cover selected paths, not physical-device scroll feel, production media or performance. Stories stay fixed above the pager rather than overlaying edge-to-edge content. |
| Create | Create sheet and composer; system-camera/gallery image and video picking for stories and reels; camera choice/cancel/permission handling tested with fake pickers | No custom filters/timer/multi-clip camera UI. No real camera/permission capture evidence. Small-phone Continue clipping fixed in 0.5.1. |
| Group chat | Group name/member list, Add people, Leave, owner handoff, owner-only Rename in source and widget/API tests; join-time history filtering; membership-checked chat media | Member-role management not built. Rename/member endpoints exist in the deployed source but their authenticated mutation paths are not proven live. Real B2 latency/large-file/error behavior is unverified. PostgreSQL 18 local throwaway concurrency checks pass, not a live-database load test. Other cross-request membership/send races remain to be tested. |
| Sign-in | Real Auth0 password grant and actual Session client work against the live API with an existing synthetic QA identity | Native social callback and physical-device login unverified. Auth0 offline access is off, preventing persistent sessions. Secure token persistence is candidate source only, not in published 0.5.1. |
| Calls | Voice/video LiveKit client, history/missed state and control tray | Actual app call on two real devices, audio routing, backgrounding, reconnection and floating minimised tile unverified or not built. |
| Wallet | Balance/history/send UI; withdrawal groundwork; top-up and cash-out unavailable | Providers not integrated or approved. DisabledPayout remains deployed; no payout execution claim. |
| Live rooms | Host/speaker/raise hand/gift UI and server code | Real app audio, room lifecycle and host interactions need device verification. |
| Media lifecycle | Route/tab/background visibility gating for feed/reels/stories, story hold and async-exit guards; real controllers tested with fake video platform | Physical codec/audio, real file loading, interruptions and native teardown still unverified. |
| Prior roadmap additions | Earlier roadmap messages named polls, Roman Nepali typing, Global Nepali Hour, Blood Connect and festival greetings | Not implemented in the current source. Prior roadmap wording is not proof that any competitor currently supports them. Requirements, safe data/consent and current content provenance still need design and implementation. |
| Offline states | Error/retry lists and offline banner; unsent-message handling | Physical network transitions/recovery and polish need review. |
| Push | Client registration and server sender code | Real push delivery and production configuration readiness unverified. |
| Language | English and Nepali strings | Native Nepali review needed. |
| iOS | CI unsigned build | Signing/distribution and real-device verification. |

Synthetic fixture renders are layout evidence only. Genuine Auth0/live API reads do not prove posting, messaging, payments, media, calls or push. No physical Samsung/TeamViewer result is recorded by this engineering check.

# Product reference notes

Reviewed November 17, 2026. These are source-backed lessons for implementation, not a claim that a full hands-on competitor teardown is complete. Product decisions remain Sanjaal's own, and source assets/code are not copied.

| Reference | What the source establishes | Sanjaal decision / limit |
| --- | --- | --- |
| [NNGroup: Onboarding Tutorials vs. Contextual Help](https://www.nngroup.com/articles/onboarding-tutorials/), February 12, 2023 | Out-of-context walkthroughs interrupt tasks, are often skipped and can be hard to remember; help should be dismissible, revisitable and provided where useful. | Replace four introductory feature slides with one optional welcome and direct account/sign-in paths. Keep creation, permission and recovery guidance beside the relevant task. This is a design judgment, not a Sanjaal usability-study result. |
| [NNGroup: Designing Empty States in Complex Applications](https://www.nngroup.com/articles/empty-state-interface-design/), September 19, 2021 | Empty states should communicate status, provide learning cues and direct pathways to key tasks. Loading must not be mislabeled as empty. | Home, Following and own Profile offer direct creation/search actions after a successful empty response. Errors keep Retry instead. Do not populate them with invented community activity. |
| [Android Accessibility: Touch target size](https://support.google.com/accessibility/android/answer/7101858?hl=en), inspected November 17, 2026 | Recommends at least 48x48dp interactive targets; a smaller visible icon can sit within a larger target. | Use 48dp minimum button targets, inspect small-phone/text-scaled pixels and test reachability. Attractive compact icons do not justify tiny tap regions. Automated layout tests alone are not an accessibility audit. |
| [Discord: Voice Channels FAQs](https://support.discord.com/hc/en-us/articles/19583625604887-Voice-Channels-FAQs), official help inspected November 17, 2026 | Documents a speaker icon identifying voice channels, direct channel selection to join, lock indicators for missing permission and channel status. | Make Calls/Live rooms discoverable in the communication journey and clearly identify availability/permissions. Do not infer successful Sanjaal audio from a visible control. This source describes behavior, not a current visual teardown. |
| [Discord: Community Onboarding FAQ](https://support.discord.com/hc/en-us/articles/11074987197975-Community-Onboarding-FAQ), official help inspected November 17, 2026 | Answers can choose roles/channels, can be changed afterward, and default channels establish a useful starting set. | Any future personalization must change a real useful destination and remain editable. Do not add mandatory interest questions before a relevant backend exists. |
| [The Verge: Instagram Blend lets you share a Reels feed with friends](https://www.theverge.com/news/650333/instagram-blend-reels-feed-friends-dm-group-chat), April 17, 2025 | Reported invited shared Reels recommendations within one-to-one/group DMs with a daily refresh. | Content-to-conversation continuity is worth prioritizing using Sanjaal's existing Share to chat. This dated report does not establish current availability, justify a recommendation-engine claim or prescribe copying Blend. |

## Evidence boundary

The pass includes official product documentation, a platform accessibility standard and independent usability/product analysis. TikTok's [Making a post index](https://support.tiktok.com/en/using-tiktok/creating-videos) was fetched but supplied only an index/navigation list, so it was not used to claim a detailed creation flow. A hands-on competitor teardown, X inspiration review and user testing remain open. The sources above support design reasoning; they do not authorize account changes, purchases or disclosures.

## Current source batch

- Welcome -> existing-member sign-in or registration, with matching wordmark and heading hierarchy.
- Home/Following/Profile -> direct create/search actions rather than instructions pointing elsewhere.
- Publish -> return to refreshed Home at the new first item, without requiring a pull gesture; refresh requests during an existing fetch are queued.
- Profile -> compact identity and secondary edit/saved actions; creation is the primary empty-state action.
- Photo feed -> fewer independent action capsules, with a right-side contrast scrim and retained controls. The explicitly requested floating glass navigation remains.

This is one connected source batch, not the whole-product redesign, a new approved logo or a released APK. Communication/live, remaining feature depth, performance and genuine device verification remain separate work.

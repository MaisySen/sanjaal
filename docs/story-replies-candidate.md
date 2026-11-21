# Text-only story replies, candidate

Local source only. No native app build, API deployment, live-member send or distribution was performed.

The unfinished story-reply journey named in the owner's PR review now has a separate composer. A fresh explicit `story_replies` server capability exposes it in another member's loaded story viewer. Older servers do not show the button. The viewer pauses while composing, resumes on return and retains its existing session/media retirement behavior.

Sending is deliberate. The text-only message goes to the stable owner resolved from the current story row, not to whichever account later owns an old username. The server applies existing mutual blocks, current audience/expiry, own-story rejection, direct-chat membership and a per-story replay key. It creates or reuses the real direct conversation and delivers the ordinary generic chat notification on a successful new message. Replay does not repeat notification/broadcast. There is no new database migration or external service.

The recipient sees a generic Story reply label and the sender's words. This version intentionally does not copy the story photograph, video, caption, identifier or a durable media link into chat. It does not offer a clickable attachment preview, story reaction, reply-to-a-specific-story card, group forwarding or extended viewing after expiry. Existing legacy-public story bytes do not become revocable through this feature.

An unconfirmed send retains an immutable in-memory retry copy and the same key. Text is locked after the first attempt. Leaving warns that the message may already be in chat and asks the member to check before composing another copy. A retired session clears local text and ignores late results. The in-memory copy is not a durable offline outbox, and deletion or later unavailability can prevent confirmation even when an earlier attempt was accepted. The app does not call that failure proof of nondelivery.

Validation is local fixture validation. It covers successful send/replay, renamed owner, current audience/expiry/deletion, both block directions, close-friend removal, own-story/unauthenticated/invalid input rejection, old-history replay refusal, no copied media/caption, locked same-key retry, older-server affordance, late result/session retirement, paused viewer return and large-text English/Nepali composer layouts. It is not a simultaneous multi-process race proof, native keyboard/device proof, push-delivery proof or production rollout approval.

Before deployment: review the coordinated API/client batch, rerun the release gates, exercise actual supported database concurrency, and verify both members' real-device chat/viewer behavior. Keep the frozen a4b99e2 binary provenance separate from this later source. No test count establishes responsiveness or real-device acceptance.

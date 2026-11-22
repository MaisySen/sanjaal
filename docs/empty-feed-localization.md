# Empty-feed localization

Local correction for Home, Following, Saved, hashtag and default feed empty states. No live post, follow, collection or search request was made.

Five negative Nepali fixtures showed English titles, including the default feed title whose translation already existed but was never applied. FeedList now uses the existing translation path for its supplied empty title/hint. Added missing Home/Following/Saved copy and a hashtag template that preserves the exact original tag. Existing callers that already supply translated copy remain unchanged because unknown strings pass through the translator.

Ten language/surface cases at 320x640 and 1.8 text plus the selected first-use/discovery/connected/Home/own-profile group passed 64 tests sequentially. The new test file's analyzer is clean; this is not a clean whole-feed-file analyzer claim. Inspected actual current Nepali Following, Saved and hashtag captures: complete copy, original tag and Following discovery action are readable. No feed data, capability, privacy or navigation behavior changed. Native-language, reference and physical-device acceptance remain open.

No source push, build, signing, installation, distribution, account/provider mutation or data deletion occurred.

# Glass preference save recovery

Local SJ-103 follow-through based on theme recovery 7dd34d4. No lens activation, build, signing, account mutation, deployment or artifact change.

Both original glass setters silently completed on a rejected platform write. Dedicated negative cases reproduced this for transparency and reduced glass. The corrected store preserves the temporary live visual value, rejects false or throwing writes, and retains save-failed status across leaving/reopening Appearance. Explicit Retry saves the current intended snapshot. A snapshot can partially persist before a failure; the UI does not claim atomic storage or rollback.

Slider movement now previews without writing. Gesture end saves the final value. Captured snapshots are serialized, with latest-request-owned error status, so a late earlier gesture cannot overwrite a newer completed save or leave a stale failure after the newest save succeeded. The slider stays responsive during saves. Reduced-glass changes remain explicit and immediately update rendering. The queue catches failures internally to avoid poisoning subsequent saves, while returning the failure to the caller, which handles it.

Seven dedicated tests cover false writes, delayed earlier-failure/newest-success ordering, preview with no writes until gesture end, failure and explicit retry across reopening, a pending thrown error after leaving the page, and English/Nepali narrow large-text action reachability. Selected appearance/startup/entry/settings/glass/render suite: 59 pass. Final formatting-only changes rechecked all seven dedicated cases. Changed-file analyzer clean; ui.dart retains its already-recorded pre-existing unnecessary import info outside this focused analysis.

An initial serialization implementation retained a completed future across fake test zones and hung a second widget fixture. That implementation was corrected to clear the drained queue. The timed-out run is not counted as passing. Final combined and dedicated runs pass without that hang.

Actual failure pixels inspected at 320x640, 180% text, English/light and Nepali/dark. Error, Retry and slider readable; reduce-glass control reachable by scrolling. The top theme rows are partially offscreen in these intentionally scrolled captures, not clipped in the layout. Translation quality, actual platform persistence, native slider/assistive input and physical-device performance remain unaccepted. Default-off refractive lens and frozen builds are unchanged.

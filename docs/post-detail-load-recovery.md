# Post detail read recovery

Local SJ-029 follow-through based on glass preference recovery 5c51b4a. No native build, live post/account/data change, provider activation or release action.

Two negative fixtures reproduced an uncaught TypeError for successful HTTP responses containing null or list post payloads. The detail loader previously only caught ApiError. It now parses before publishing, checks the requested public ID and the basic author/media/count/reaction types consumed by the card, and exposes a generic localized read failure with explicit Retry for malformed responses. It does not turn malformed data into a deleted/private post or render a different returned post as the requested target. Existing404/410 handling and known API error messages stay unchanged.

Nine dedicated tests cover null/list payloads, wrong post identity, absent author, non-map media, invalid comment count, recovery to the correct real card on retry, a late malformed response after session replacement, and readable English/Nepali narrow large-text errors. Selected detail/card/private-photo/reviewed-content suite:58pass. Changed-file analyzer clean. Actual320x640/1.8 English/light and Nepali/dark error pixels inspected; Retry visible/reachable, no obvious clipping. These are synthetic HTTP/layout checks, not real provider failure, translation-quality or physical performance acceptance.

This is bounded payload validation, not a complete schema validator for every nested poll/media field. It does not add external shared links or auth-return routing. SJ-005 remains open. The original ledger is still being reconciled; this correction does not certify all SJ-029 states or the130-row product.

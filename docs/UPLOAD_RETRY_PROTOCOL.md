# Replay-safe creator uploads

Implemented candidate source, November 17, 2026. Not deployed or enabled in production. This is not durable local draft storage or an unlimited-storage promise.

## Rollout boundary

`UPLOAD_INTENTS_ENABLED` defaults to false. `/auth/me` advertises `features.upload_intents` only when enabled. A keyed request while disabled returns 503 without creating content or media; it does not silently fall back to an unsafe legacy send. Ordinary unkeyed clients remain compatible.

Do not enable this before the receipt migration and DB-media capacity, migration cadence and retention review. The isolated live v35 security deployment is separate and unchanged. The source below is not grounds to deploy the rest of the recovered product.

## Server contract

`upload_intent` is optional, 16-80 ASCII letters/digits/underscore/hyphen, scoped to authenticated member + operation (post or story). A receipt stores the fingerprint and resource public ID. Receipts are not automatically expired. Content deletion or story expiry leaves a tombstone so an old retry cannot recreate it. Account deletion removes that account's receipts with its other data.

The fingerprint includes normalized body/caption, post kind, ordered poll options, and ordered file SHA-256 digests, sizes and detected MIME types. Multipart boundaries, temporary paths and filenames are excluded. Size/type validation precedes hashing.

For keyed creation, the authenticated member row is locked before any blob is written. Resource, receipt and media bytes commit in one DB transaction. Keyed bytes use DB storage even when B2 is configured, avoiding remote orphan writes if the transaction fails. The existing public-media migration is a separate operation, not an automatic upload stage or evidence of current capacity. Legacy unkeyed B2 write behavior is unchanged; this change does not claim to solve every legacy remote-write rollback case.

- New intent: create once and return 201.
- Same intent/fingerprint: return the current original with `replayed: true`, without rewriting media, hashtags or poll votes.
- Same intent, changed payload: return 409 `upload_intent_conflict` with the original resource ID. No new content.
- Original deleted/expired: return 410 `upload_intent_gone`. No resurrection.
- Failure before commit: resource, DB bytes and receipt roll back together.

The unique index is a final invariant in addition to the row lock. The migration can roll back before use. Once receipts exist, its down method refuses to erase them. A production rollback must preserve the ledger and its semantics rather than dropping it and reopening delayed intents.

## Client behavior

One unpredictable intent is created per in-memory composer session. It is sent only when the capability is advertised, and reused on retry. Active uploads disable editing and duplicate sends. Success returns through the existing creator navigation, refreshing Home/story rings.

A lost response or malformed success does not prove failure. With the protocol, retry checks the original intent. On an older API, transport/5xx/malformed-success ambiguity disables ordinary retry and asks the member to check current content first. Explicit HTTP rejections can retain their normal retry path when their outcome is known.

Changed-content conflict keeps the edited draft, disables a resend and offers to open the current original. Preparing a separate upload requires confirmation that the earlier one may already exist; preparation does not send. The member must then explicitly Share/Post. Gone results also require a new explicit intent rather than resurrecting the old one.

Recovery notices are bounded with visible actions and scrollable text. English/Nepali, light/dark and 320x640 at 1.8x text were inspected. Keyboard-inset fixtures are simulated layout evidence, not the unresolved native IME gate.

## Evidence

- API: 107 tests / 855 assertions on SQLite and PostgreSQL 18, normal and route/event-cached runs.
- Nine focused upload tests cover scope, media order/content changes, story caption/expiry/deletion, poll vote preservation, validation/authentication, legacy compatibility, failure after blob write, migration rollback protection and disabled rollout.
- Real PostgreSQL concurrency suite: 10 tests / 66 assertions. New four-process post/story replay tests create one resource/blob per intent. A changed-payload race returns one 201 and one 409, without extra media.
- Flutter: 138 non-render + 177 screen-render + 4 base-render = 319 passed, one intentional live-test skip. Analyzer: 20 information notices, no errors/warnings.
- Creator tests simulate server commit followed by a lost response, stable retry keys, retained caption, changed-content conflict, cancelled new-intent preparation, opening the original story, malformed success and older-API ambiguity. They are not real network loss or live writes.

Native keyboard visibility, Samsung, physical codec/audio behavior, real production uploads, free-tier capacity and persistent local draft storage remain unverified or unfinished. No new APK was released by this batch.

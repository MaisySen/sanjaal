# Feed latency notes

Status: investigation notes. Nothing here has been changed in the API or deployed.

## Measured (Server-Timing, deployed API, earlier in this build)

- GET /posts: app time 2.6 to 2.7 s, of which database 1.6 s over 7 queries (about 230 ms per query).
- GET /rooms: app time 1.24 to 1.39 s, database 0.23 s over 1 query.

## What the code does for GET /posts (read from the source)

Seven queries per page of 15, with no per-post query (no N+1):
blocks, posts, authors, media, hashtags, reaction counts (one grouped query), and which authors the viewer follows.

## What is not established

- The cause of about 230 ms per query. One hypothesis is network distance between the API host and the database host. Another is query shape or missing indexes. A third is connection setup per request. None was tested, so none is claimed.
- /rooms spends 0.23 s on one query but 1.0 s or more outside the database, so app time is not only database time. Cause unknown.

## Options, with their risk

1. Cut round trips (for example fold blocks and follows into the main query). Safe for privacy and preserves blocking and following rules if covered by the existing tests. Gain is at most a few queries of seven.
2. Cache by viewer. Responses depend on the viewer (blocks, follows, own reaction), so a shared cache would leak personalised data. Any cache must be keyed per viewer, or cache only viewer-independent parts (post, media, hashtags, counts) and add the viewer parts on top.
3. Persistent database connections. Not tested.

## Next test (not done)

Time one trivial query (SELECT 1) from the API container to the database. If that alone is near 230 ms, distance is the cause and query changes will not help much. Changing database or API placement is out of scope for now.

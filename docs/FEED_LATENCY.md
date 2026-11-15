# Feed latency notes

Status: investigation notes. Nothing here has been changed in the API or deployed.

## Measured (Server-Timing, deployed API, earlier in this build)

- GET /posts: app time 2.6 to 2.7 s, of which database 1.6 s over 7 queries (about 230 ms per query).
- GET /rooms: app time 1.24 to 1.39 s, database 0.23 s over 1 query.

## What the code does for GET /posts (read from the source)

Seven queries per page of 15, with no per-post query (no N+1):
blocks, posts, authors, media, hashtags, reaction counts (one grouped query), and which authors the viewer follows.

## Earlier probe (Nov 15, v19, since removed)

A temporary probe timed five bare `select 1` calls inside the app. Each trivial query cost 227 to 233 ms, so the per-query cost is network round trip to the database (API on Render Ohio, database on Aiven sfo), not query shape. Back then the first query of every request cost about 930 ms (new connection and TLS handshake each request). The current image runs php-fpm, and a one-query route now shows about 230 ms of database time in total, so connection reuse appears to work now. That is an inference from Server-Timing, not a direct test.

## New observation (Nov 16, 09:41, live, three requests)

GET /api/v1/ping runs zero queries and still reports app time of 695, 695 and 905 ms. So roughly 0.7 to 0.9 s of every request is framework and CPU time before any database work, on the free instance's small CPU share. For /posts (2.6 to 2.7 s), about 1.6 s is database round trips and the rest is that floor plus rendering.

## What is still not established

- Why a round trip costs 230 ms. Ohio to San Francisco is normally much less, so distance alone may not explain it. Aiven-side proxying or connection handling are possible. Untested.
- How the 0.7 to 0.9 s floor splits between autoload, framework boot, route loading and CPU throttling. Untested.

## Options, with their risk

1. Cut the floor: cache routes and events at start (`route:cache`, `event:cache`; `config:cache` already runs) and use an authoritative classmap autoloader. Low risk, no privacy impact. Needs a new image (v30), so it needs the usual deploy checks and the rollback target kept. Gain unknown until measured with the ping route before and after.
2. Cut round trips (fold blocks and follows into fewer queries). Must keep blocking and following rules under the existing tests. At most a few of seven queries.
3. Cache by viewer. Responses depend on the viewer (blocks, follows, own reaction), so a shared cache would leak personalised data. A cache must be keyed per viewer, or cache only viewer-independent parts (post, media, hashtags, counts) and add the viewer parts on top, with invalidation on post, like, block and follow changes.
4. Same-region database test. Out of scope: no second service and no change to database or API placement.

## Next step (not done)

Option 1 in a v30 image, measured with GET /ping (app time, 10 requests before and after). Nothing is deployed for this yet.

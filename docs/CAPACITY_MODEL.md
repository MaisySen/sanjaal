# Capacity model (synthetic, not measured production capacity)

Publisher: Fintex Australia Pty Ltd, ABN 60 688 406 108, contact@fintex.au.

Tool: Breakscale (https://github.com/workersio/breakscale, MIT licence, checked 16 Nov 2026), a discrete-event system design simulator. We ran only its engine (`src/sim`, no network or file access, no dependencies) locally with Node 22 and no package install. The hosted site and its hosted MCP server were not used, and no Sanjaal data was sent anywhere. Run: `node --experimental-strip-types --import ./loader.mjs breakscale_model.ts` from a checkout, with the paths in the script adjusted.

## What was measured, what was assumed

Measured (16 Nov 2026, 5 single requests each from one test box to the live API, total time including network): ping 0.57 to 0.81 s, rooms list 1.37 to 1.50 s, feed 2.76 to 3.11 s. The php-fpm worker cap of 12 comes from `api/docker/www.conf`.

Measured (Server-Timing header, 5 live requests each, Nov 16 00:03): feed app time 2.61 to 2.73 s with 1.59 to 1.64 s in the database over 7 queries (about 230 ms per query round trip); rooms list app time 1.24 to 1.39 s with 0.23 s in the database over 1 query, so about 1 s of non-database app time per request (cause not verified, possibly the free instance CPU). An earlier version of this model assumed server time as client total minus ping; that was not measured service time and the model's knee figures below were computed from it, so treat them as illustrative only. Not measured: the request mix, behaviour under concurrent load, cold starts and free instance sleep. The simulator does not model them.

## Result of the sweep (workers hold a slot for the whole request)

| Request | Knee | Behaviour past the knee |
|---|---|---|
| Feed at 2.2 s | about 5 per second (12 workers / 2.2 s) | at 6 per second 48% fail, above 8 per second 80% to 98% fail, because slow requests time out while workers keep working |
| Rooms list at 0.75 s | about 15 per second | 3% errors at 16 per second, 19% at 20 |

This is queueing arithmetic (workers divided by time per request) plus a retry and timeout collapse the sketch makes visible. It does not tell us the real capacity.

## What it says about 2,000 members (planning only)

With the SCALING.md assumptions (600 daily active, about 20 feed loads each, 30% of a day's loads in the busiest hour), peak feed load is about 1 request per second, and about 3 per second with a 3x burst. That is under the modelled 5 per second knee, with a thin margin that depends on the unmeasured server time. Feed latency is the lever: fewer queries per request, or the API closer to the database, raises the knee directly.

It does not change the known binding limit: Backblaze B2 free downloads (2,500 a day, see SCALING.md) against about 18,000 media loads a day at 600 daily active members. The 2,000-user gap is not solved by this model.

## Next measurement that would make this real

Measure server time per endpoint inside the API (not client total time), and run a short, capped load test against a local copy of the API and a throwaway database, not the live free services.

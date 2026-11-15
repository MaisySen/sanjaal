# Scaling path and cost estimates

Publisher: Fintex Australia Pty Ltd, ABN 60 688 406 108, contact@fintex.au.

Target set by the owner: 2,000 free users, smooth. These are planning estimates, not quotes. Prices change, so check each vendor page before any spend. No paid plan is bought without the owner's approval.

## What went wrong on 2026-11-15

Photos and videos were stored as base64 text inside Postgres. Every media request read the whole row through the database host, so 98 MB of stored data produced 6.3 GB of database transfer in one day and hit the free cap of the database host, which suspends the database at its limit. The fix has three parts:

1. Media route reads only the requested byte range and answers 304 from the ETag without touching the file (done, API image v9, tests in MediaTest).
2. Media moves out of the database into object storage, served with long cache headers (next).
3. Uploads are compressed on the phone before sending (next).

## Design rules for 2,000 users

- API is stateless: no local files, sessions in tokens (Auth0), so Render can run more than one instance.
- Lists are cursor paginated and return counts from indexed columns, no per-row queries.
- Media never goes through the database. Clients cache images and preload the next video.
- Database holds text and counts only. At 2,000 users that is well under 1 GB.

## Assumptions for the curve

30 percent of members open the app daily. Each active member views about 20 short videos at 1.5 MB (720p, compressed) and 10 images at 150 KB per day, so about 30 MB per active member per day. About 0.2 uploads per member per day at 1.5 MB.

| Members | Daily active | Media traffic per month | Media stored after a month |
|---|---|---|---|
| 100 | 30 | about 27 GB | about 1 GB |
| 1,000 | 300 | about 270 GB | about 9 GB |
| 2,000 | 600 | about 540 GB | about 18 GB |

## Cost curve

| Members | API host | Database | Media storage and traffic | Rough total per month |
|---|---|---|---|---|
| 100 | Render free (sleeps after 15 minutes idle, slow first request) | free Postgres, 1 GB | free object storage tier | 0 USD |
| 1,000 | Render Starter, always on, about 7 USD | free Postgres still fits | object storage about 1 to 3 USD | about 8 to 10 USD |
| 2,000 | Two Render Starter instances, about 14 USD | paid small Postgres, about 5 to 15 USD | object storage about 3 to 8 USD, or free egress behind a CDN once we own a domain | about 25 to 40 USD |

Notes:

- Live video rooms (LiveKit) have their own free tier. At 2,000 members with regular rooms we expect to need its paid plan. We will measure minutes first and bring the number before spending.
- Coin and gift income should cover this range long before 2,000 members if even a few percent of members buy coins.
- The first free-tier limit we expect to meet is the Render free instance sleeping, not the database.

## Database host (updated 2026-11-15)

The free database moved from Neon to Aiven for PostgreSQL (free plan, no card): 1 CPU, 1 GB RAM, 1 GB disk, 20 connections, hosted in California. Reasons: Neon's free plan stops the database at 5 GB of transfer or 100 compute hours a month, and our chat long poll keeps compute awake all day. Aiven has no such caps.

Things to know:

- Aiven powers the free service off after a period of no activity and emails first. To restart it, open the service in the Aiven console and press Power on. Real traffic keeps it awake.
- The API host is in Ohio, so each query crosses the country. The API keeps database connections open per worker and we cut queries per request. Moving the API to the Render Oregon region would remove most of the delay.
- Free plan has no connection pooling. Keep the API at 12 workers or fewer so we stay under 20 connections.

## Media storage (Backblaze B2)

New uploads go to a private B2 bucket (free tier: 10 GB stored, downloads free up to 3 times the stored size per day, no card on file). Postgres keeps a small row per file (id, type, size, storage). A read request returns a 302 to B2 with a download token the API caches for six days, so the API never streams media bytes and Render's 0.1 CPU is not on the media path. Old files stay in Postgres until moved.

Limits to watch: 10 GB of storage is roughly 3,000 to 5,000 compressed videos at 2 to 3 MB each, or far more photos. Without a card, B2 stops accepting uploads at the cap rather than billing.

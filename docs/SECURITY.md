# Security review (15 Nov 2026)

## What was found on the live API (image v26)
- PHP 8.4.23 (static-php-cli build), Alpine 3.20.10 base (end of life 2026-04-01), PHP built-in server (php -S) as the web server.
- PHP 8.4.23 is affected by CVE-2026-109618 and CVE-2026-109619 ("PHP2Shell", unauthenticated remote code execution,
  CVSS 4.0 9.2, fixed in 8.4.27 on 21 Oct 2026, reported exploited in the wild). Sources:
  https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w ,
  https://thephp.foundation/blog/2026/10/21/todays-php-security-release-and-how-were-strengthening-php-security/
- The live API was first deployed on 15 Nov 2026 (about 01:36 AEDT) on PHP 8.4.23 and ran an affected PHP until the v28 deploy at about 22:55 AEDT the same day, roughly 21 hours. Whether it was attacked
  is unknown. Compromise is not ruled out. Secrets held by the process are treated as possibly exposed (see RELEASES.md).

## Fixed (image v28, deployed 15 Nov 2026)
- PHP 8.4.27 from Alpine 3.24.4 packages (package checksums verified), Caddy in front of php-fpm, no built-in server.
- No X-Powered-By or Server header, nosniff/HSTS/no-referrer/frame-deny headers, no CORS origins, hidden paths return 404.
- composer audit --locked: no advisories for the 92 locked packages (15 Nov 2026).

## Credential rotation (15 Nov 2026, owner approved)
Each rotation was verified against live behaviour and the old credential was revoked.
- APP_KEY: replaced. Nothing in the app depends on it (no encrypted columns, signed URLs or app-issued tokens; auth is Auth0 JWT), so no user-visible effect.
- Database password (Aiven avnadmin): reset, Render updated, API verified. Aiven has no overlap, so about a minute of database errors during the swap.
- LiveKit API key: new key proven against LiveKit first, Render updated, live tokens carry the new key id, old keys deleted.
- Backblaze B2 application key: new bucket-scoped key proven first, Render updated, old key deleted (B2 now answers 401 for it), upload verified live.
- eSewa: environment is test with eSewa's published sandbox secret. Nothing to rotate. A live merchant secret will be issued by eSewa at onboarding.
- Old Neon databases: db2 role password reset (it was live 17:56 to about 18:14). The first Neon project is quota restricted: its data is unrecovered and its role password could not be reset (Neon returns quota exceeded). Both projects are kept until content is compared.
- Render logs only go back about an hour, so activity during the 21 hour window cannot be reviewed. No sign of compromise was found in what exists.

## Open
- Neon project "sanjaal": data unrecovered and credential not rotated until its free quota resets.
- Bundled library advisories for the new image's packages were not separately reviewed beyond Alpine 3.24 being supported.
- Reachability of each remaining PHP fix is not individually proven.

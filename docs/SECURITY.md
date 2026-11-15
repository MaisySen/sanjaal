# Security review (15 Nov 2026)

## What was found on the live API (image v26)
- PHP 8.4.23 (static-php-cli build), Alpine 3.20.10 base (end of life 2026-04-01), PHP built-in server (php -S) as the web server.
- PHP 8.4.23 is affected by CVE-2026-109618 and CVE-2026-109619 ("PHP2Shell", unauthenticated remote code execution,
  CVSS 4.0 9.2, fixed in 8.4.27 on 21 Oct 2026, reported exploited in the wild). Sources:
  https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w ,
  https://thephp.foundation/blog/2026/10/21/todays-php-security-release-and-how-were-strengthening-php-security/
- The live API therefore ran an affected PHP from 21 Oct 2026 until the v28 deploy on 15 Nov 2026. Whether it was attacked
  is unknown. Compromise is not ruled out. Secrets held by the process are treated as possibly exposed (see RELEASES.md).

## Fixed (image v28, deployed 15 Nov 2026)
- PHP 8.4.27 from Alpine 3.24.4 packages (package checksums verified), Caddy in front of php-fpm, no built-in server.
- No X-Powered-By or Server header, nosniff/HSTS/no-referrer/frame-deny headers, no CORS origins, hidden paths return 404.
- composer audit --locked: no advisories for the 92 locked packages (15 Nov 2026).

## Open
- Secret rotation after the exposure window (needs owner approval where it touches accounts).
- Bundled library advisories for the new image's packages were not separately reviewed beyond Alpine 3.24 being supported.
- Reachability of each remaining PHP fix is not individually proven.

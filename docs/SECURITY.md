# Security review (15 Nov 2026)

Deployed (read from image v26 and live headers): PHP 8.4.23 static-php-cli build (OpenSSL 3.6.2, libpq 18.3),
Alpine 3.20.10 base (end of life 2026-04-01), PHP built-in server in production, Laravel 13.42.0.
composer audit --locked: no advisories for the 92 locked packages (run 15 Nov 2026).
PHP 8.4.24 to 8.4.27 fix security issues present in 8.4.23 (php-src NEWS). Reachability per issue is not proven.
Status: runtime and base upgrade and production server swap are OPEN.
Done: version header removed, security headers added, CORS wildcard closed.

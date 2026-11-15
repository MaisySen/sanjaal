# Isolated end to end fixture (CI only)

Used by the emulator job. It runs this API on the CI runner with an empty sqlite database and its own
throwaway signing key, so the app can be driven signed in without Auth0, live data or any secret.
It shows the app talking to this API code locally. It is not evidence about Auth0, the live service or
production data.

- `server.php` is a router script for `php -S`. It boots the app like public/index.php, then points the
  Auth0 guard at a local key set read from E2E_JWKS_FILE. The guard still verifies signature, issuer,
  audience and expiry. Nothing in `app/` knows about this fixture, and `tests/` is not part of the
  shipped image.
- `prepare.php` creates the key, the key set, a synthetic member and sample posts, and writes a token.
- `AuthRejectsTest` (in tests/Feature) checks the normal guard rejects unsigned and wrongly signed tokens.

Image recipe (no Docker daemon needed): resolve.py picks Alpine 3.24 packages (php84, extensions, php84-fpm, caddy),
fetch.py downloads them from dl-cdn.alpinelinux.org and checks each package checksum against APKINDEX, build.py layers
them with the app and pushes to the registry. Runtime: Caddy on $PORT in front of php-fpm (workers run as nobody).
Verify the PHP version after each build: php84 -v inside the image, and check Alpine and PHP release pages.

API image publication now runs security_floor.py against the prepared filesystem before reading credentials or making network requests. It checks the actual serialized app layer again before uploading any blob. A changed guard needs deliberate source review and a pin update. Do not skip the check. The exact-current-source image job in CI also checks the source before image creation.

The reviewed runtime template is pinned by digest. These checks grant no deployment or app-release permission. Historical branches and direct registry/Render operations can bypass repository scripts, so this is not a registry or hosting-side access control. Future API releases must start from api-security-baseline or include its guard and enforced publisher checks. Frozen app binaries are unchanged.

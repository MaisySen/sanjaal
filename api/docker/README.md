Image recipe (no Docker daemon needed): resolve.py picks Alpine 3.24 packages (php84, extensions, php84-fpm, caddy),
fetch.py downloads them from dl-cdn.alpinelinux.org and checks each package checksum against APKINDEX, build.py layers
them with the app and pushes to the registry. Runtime: Caddy on $PORT in front of php-fpm (workers run as nobody).
Verify the PHP version after each build: php84 -v inside the image, and check Alpine and PHP release pages.

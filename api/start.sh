#!/bin/sh
cd /app
export PHP_CLI_SERVER_WORKERS=4
PHP="php -d curl.cainfo=/etc/ssl/certs/ca-certificates.crt -d openssl.cafile=/etc/ssl/certs/ca-certificates.crt -d memory_limit=256M -d upload_max_filesize=60M -d post_max_size=64M"
$PHP artisan migrate --force || exit 1
$PHP artisan config:cache
exec $PHP -S 0.0.0.0:${PORT:-10000} -t public

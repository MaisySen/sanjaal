#!/bin/sh
cd /app
export XDG_DATA_HOME=/tmp XDG_CONFIG_HOME=/tmp HOME=/tmp
PORT=${PORT:-10000}; export PORT
php artisan migrate --force || exit 1
php artisan config:cache
chown -R nobody:nobody /app/storage /app/bootstrap/cache 2>/dev/null
php-fpm84 --nodaemonize &
FPM=$!
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY=$!
while kill -0 $FPM 2>/dev/null && kill -0 $CADDY 2>/dev/null; do sleep 5; done
kill $FPM $CADDY 2>/dev/null
exit 1

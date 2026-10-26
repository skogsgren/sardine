#!/bin/sh
set -eu

: "${GATEWAY_URL:?GATEWAY_URL is not set}"
: "${GATEWAY_KEY:?GATEWAY_KEY is not set}"

upstream="${GATEWAY_URL%/}"
host="${upstream#*://}"
host="${host%%/*}"

sed -e "s|__UPSTREAM__|${upstream}|g" -e "s|__HOST__|${host}|g" \
	/etc/caddy/Caddyfile.tmpl > /tmp/Caddyfile

exec caddy run --config /tmp/Caddyfile --adapter caddyfile

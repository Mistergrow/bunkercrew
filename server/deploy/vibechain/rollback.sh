#!/bin/sh
# Explicit operator action: withdraw only Bunkercrew; retain all account data.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
site=/etc/nginx/sites-available/bunkercrew.vibechain.rocks
link=/etc/nginx/sites-enabled/bunkercrew.vibechain.rocks
test -f "$site"
grep -q '^# Owned exclusively by Bunkercrew' "$site"
if [ -L "$link" ]; then
  test "$(readlink "$link")" = "$site"
  rm "$link"
  if ! nginx -t; then
    ln -s "$site" "$link"
    exit 1
  fi
  read -r master < /run/nginx.pid
  case "$master" in ''|*[!0-9]*) exit 1 ;; esac
  test "$(cat /proc/$master/comm)" = nginx
  kill -HUP "$master"
fi
docker compose -f /opt/bunkercrew/current/compose.yaml stop relay
if [ -f /etc/cron.d/bunkercrew ]; then
  grep -q '^# Bunkercrew-owned jobs' /etc/cron.d/bunkercrew
  mv /etc/cron.d/bunkercrew /opt/bunkercrew/nginx/cron.disabled
fi
printf '%s\n' 'Bunkercrew withdrawn; durable account volume, backups and certificates retained.'

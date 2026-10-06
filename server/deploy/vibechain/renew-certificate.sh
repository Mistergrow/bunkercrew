#!/bin/sh
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
cert=/opt/bunkercrew/tls/live/bunkercrew.vibechain.rocks/fullchain.pem
before=$(sha256sum "$cert" | cut -d ' ' -f 1)
docker run --rm --user 0 --cap-drop ALL --security-opt no-new-privileges:true --pids-limit 64 --memory 256m \
  -v /opt/bunkercrew/acme:/var/www/certbot \
  -v /opt/bunkercrew/tls:/etc/letsencrypt \
  -v /opt/bunkercrew/tls-work:/var/lib/letsencrypt \
  -v /opt/bunkercrew/tls-logs:/var/log/letsencrypt \
  certbot/certbot@sha256:f70ad0adbb7e117f0fe42a63c553f28ea451edabc0148757b6efcd9735acaa20 \
  renew --cert-name bunkercrew.vibechain.rocks --quiet
after=$(sha256sum "$cert" | cut -d ' ' -f 1)
if [ "$before" != "$after" ]; then
  nginx -t
  read -r master < /run/nginx.pid
  case "$master" in ''|*[!0-9]*) exit 1 ;; esac
  test "$(cat /proc/$master/comm)" = nginx
  kill -HUP "$master"
fi

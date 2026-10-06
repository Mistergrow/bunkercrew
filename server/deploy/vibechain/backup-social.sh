#!/bin/sh
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
docker run --rm -i --user 10001 --network none --read-only --cap-drop ALL --security-opt no-new-privileges:true --pids-limit 32 --memory 128m \
  -v bunkercrew_social_data:/data:ro -v /opt/bunkercrew/backups:/backup \
  bunkercrew-relay:net20 python - <<'PY'
import datetime,sqlite3
from pathlib import Path
root=Path('/backup')
name='social-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.sqlite3'
with sqlite3.connect('file:/data/social.sqlite3?mode=ro',uri=True) as source:
    with sqlite3.connect(root/name) as target:
        source.backup(target)
        assert target.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
for old in sorted(root.glob('social-*.sqlite3'),reverse=True)[7:]:
    old.unlink()
print('Bunkercrew SQLite backup complete; seven snapshots retained')
PY

#!/usr/bin/env bash
# Ship freshly-imported albums from the PC staging folder to the tablet, then
# flush the PC cache (rsync --remove-source-files = copy, then delete on success).
# Safe: if the tablet is unreachable, nothing is deleted — it retries next run.
#
# Run manually, or on a timer/cron (e.g. every 10 min):
#   */10 * * * * /path/to/sync-to-tablet.sh >> ~/sync-tablet.log 2>&1
set -euo pipefail

TABLET="${TABLET:-minideck@192.168.0.43}"
STAGING="${STAGING:-$(cd "$(dirname "$0")" && pwd)/library}"
DEST="${DEST:-Music/}"            # relative to the tablet user's home

# bail quietly if the tablet isn't reachable (don't flush into the void)
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$TABLET" true 2>/dev/null; then
  echo "$(date '+%F %T') tablet unreachable — skipping"; exit 0
fi

# copy complete albums over, deleting each source file once it's safely transferred
rsync -a --remove-source-files --info=stats1 "$STAGING"/ "$TABLET:$DEST"

# prune the now-empty directories rsync leaves behind
find "$STAGING" -mindepth 1 -type d -empty -delete 2>/dev/null || true

# refresh the tablet's mpd library so new tracks appear immediately
ssh "$TABLET" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); mpc update' >/dev/null 2>&1 || true

echo "$(date '+%F %T') shipped + flushed"

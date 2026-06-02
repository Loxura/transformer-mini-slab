#!/usr/bin/env bash
# Ship freshly-imported albums from the PC staging folder to the tablet, then
# flush the PC cache (rsync --remove-source-files = copy, then delete on success).
# Safe: if the tablet is unreachable, nothing is deleted — it retries next run.
#
# Run manually, or on a timer/cron (e.g. every 10 min):
#   */10 * * * * /path/to/sync-to-tablet.sh >> ~/sync-tablet.log 2>&1
set -euo pipefail

TABLET="${TABLET:-minideck@192.168.0.44}"   # set a DHCP reservation so this stops drifting
STAGING="${STAGING:-$(cd "$(dirname "$0")" && pwd)/library}"
DEST="${DEST:-Music/}"            # relative to the tablet user's home

# bail quietly if the tablet isn't reachable (don't flush into the void)
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$TABLET" true 2>/dev/null; then
  echo "$(date '+%F %T') tablet unreachable — skipping"; exit 0
fi

# Break the re-download loop: before we flush, tell Lidarr to unmonitor every album
# it has fully downloaded. Once flushed, an unmonitored album won't reappear in
# soularr's wanted list, so it isn't fetched again. Best-effort (never blocks the ship).
LIDARR_URL="${LIDARR_URL:-http://localhost:8686}"
LIDARR_CONFIG="${LIDARR_CONFIG:-$(cd "$(dirname "$0")" && pwd)/config/lidarr/config.xml}"
APIKEY=$(grep -oPm1 '(?<=<ApiKey>)[^<]+' "$LIDARR_CONFIG" 2>/dev/null || true)
if [ -n "${APIKEY:-}" ]; then
  python3 - "$LIDARR_URL" "$APIKEY" <<'PY' || true
import sys, json, urllib.request
base, key = sys.argv[1], sys.argv[2]
def api(method, path, data=None):
    req = urllib.request.Request(base + path, method=method,
        headers={"X-Api-Key": key, "Content-Type": "application/json"},
        data=(json.dumps(data).encode() if data is not None else None))
    return json.load(urllib.request.urlopen(req, timeout=20))
done = []
for a in api("GET", "/api/v1/album"):
    st = a.get("statistics", {})
    total = st.get("totalTrackCount", 0)
    if a.get("monitored") and total > 0 and st.get("trackFileCount", 0) >= total:
        done.append(a["id"])
if done:
    api("PUT", "/api/v1/album/monitor", {"albumIds": done, "monitored": False})
    print(f"unmonitored {len(done)} completed album(s) in Lidarr")
PY
fi

# copy complete albums over, deleting each source file once it's safely transferred
rsync -a --remove-source-files --info=stats1 "$STAGING"/ "$TABLET:$DEST"

# prune the now-empty directories rsync leaves behind
find "$STAGING" -mindepth 1 -type d -empty -delete 2>/dev/null || true

# refresh the tablet's mpd library so new tracks appear immediately
ssh "$TABLET" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); mpc update' >/dev/null 2>&1 || true

echo "$(date '+%F %T') shipped + flushed"

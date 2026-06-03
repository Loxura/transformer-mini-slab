#!/usr/bin/env bash
# Backfill recipe photos: for every Tandoor recipe that has no image, scrape its source page's
# og:image and upload it (PUT /api/recipe/<id>/image/). Re-runnable (skips recipes that already
# have an image), polite (1s/host). The ingest watcher captures images for NEW recipes itself;
# this fills in the ones imported before that. Run: cooking/ingest/backfill-images.sh
set -uo pipefail
CFG="$HOME/.config/eww"
URL=$(cat "$CFG/tandoor-url" 2>/dev/null || echo http://localhost:8090)
TOK=$(cat "$CFG/tandoor-token")
UA="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
auth=(-H "Authorization: Bearer $TOK")
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok=0; miss=0

# IDs of image-less recipes (walk every page). source_url is only on the DETAIL endpoint, so
# we fetch it per-id below.
python3 -c '
import sys,json,urllib.request
BASE=sys.argv[1]; TOK=sys.argv[2]
def page(u):
    req=urllib.request.Request(u,headers={"Authorization":f"Bearer {TOK}"})
    return json.load(urllib.request.urlopen(req))
u=BASE+"/api/recipe/?page_size=100"
while u:
    d=page(u)
    for r in d.get("results",[]):
        if not r.get("image"): print(r["id"])
    u=d.get("next")
' "$URL" "$TOK" | while read -r id; do
  src=$(curl -s "${auth[@]}" "$URL/api/recipe/$id/" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("source_url") or "")')
  [ -z "$src" ] && { echo "- $id no source_url"; continue; }
  og=$(curl -s -A "$UA" -L --max-time 15 "$src" 2>/dev/null \
       | grep -ioE '<meta[^>]+property="og:image"[^>]*content="[^"]+"' | head -1 \
       | sed -E 's/.*content="([^"]+)".*/\1/')
  if [ -z "$og" ]; then echo "- $id no og:image ($src)"; miss=$((miss+1)); sleep 1; continue; fi
  if curl -s -A "$UA" -L --max-time 25 "$og" -o "$TMP/$id.jpg" 2>/dev/null && [ -s "$TMP/$id.jpg" ]; then
    code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "${auth[@]}" -F "image=@$TMP/$id.jpg" "$URL/api/recipe/$id/image/")
    echo "+ $id img -> $code"; rm -f "$TMP/$id.jpg"
  else echo "- $id download failed"; fi
  sleep 1
done
echo "BACKFILL DONE"

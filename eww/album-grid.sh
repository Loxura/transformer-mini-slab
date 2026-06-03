#!/usr/bin/env bash
# Album-cover grid browser for the deck. The on-disk layout is inconsistent
# (some albums in Artist/Album/ dirs, some flat with odd filenames), so albums
# are enumerated from mpd tags, never the filesystem. Each album's cover is
# resolved once (local image -> embedded art -> iTunes) and cached with the
# SAME key scheme as cover-palette, so a played album reuses the grid thumbnail.
#
# PAGINATED, not scrolled: touch-scrolling a GtkScrolledWindow on this rotated
# layer-shell surface was unreliable (see eww/README.md), so each view shows one
# screenful and a prev/next pager flips pages. The full album/track lists are
# cached to disk; page state lives in small files so the (separate-process)
# onclick handlers and the background cover-resolver all agree on the page.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
EWW="$HOME/.local/bin/eww"
CACHE="$HOME/.cache/music-card"; mkdir -p "$CACHE"
MUSIC="$HOME/Music"
COLS=4
GRID_PSIZE=8          # albums per page (2 rows of 4)
TRACK_PSIZE=7         # tracks per page (+ the always-visible Play album row)
ALBUMS_TSV="$CACHE/albums.tsv"      # full album list, cached at open
TRACKS_JSON="$CACHE/tracks-all.json" # full track list for the open album
GP="$CACHE/grid_page"; TP="$CACHE/track_page"
fetch(){ curl -fsSL --max-time 8 "$1" 2>/dev/null || wget -qO- --timeout=8 "$1" 2>/dev/null; }
ckey(){ printf '%s' "$1|$2" | md5sum | cut -c1-16; }   # aa|album (matches cover-palette)

# All (albumartist, album) pairs with one representative file, deduped, tab-sep.
albums_raw(){
  mpc -f '%albumartist%\t%artist%\t%album%\t%file%' find '(Album != "")' 2>/dev/null \
    | awk -F'\t' '{aa=($1!=""?$1:$2); if(!seen[aa,$3]++) printf "%s\t%s\t%s\n", aa, $3, $4}'
}

# Slice the cached album list to the current page; emit "PAGES\tPAGE\tROWSJSON".
grid_slice(){
  local page; page=$(cat "$GP" 2>/dev/null || echo 0)
  CACHE="$CACHE" COLS="$COLS" PSIZE="$GRID_PSIZE" PAGE="$page" python3 -c '
import sys, os, json, hashlib, math
cache=os.environ["CACHE"]; cols=int(os.environ["COLS"]); psize=int(os.environ["PSIZE"]); page=int(os.environ["PAGE"])
items=[]
for ln in sys.stdin.read().splitlines():
    p=ln.split("\t")
    if len(p)<3: continue
    aa,al,f=p[0],p[1],p[2]
    key=hashlib.md5(("%s|%s"%(aa,al)).encode()).hexdigest()[:16]
    art=os.path.join(cache, key+".jpg")
    ok=os.path.exists(art) and os.path.getsize(art)>0
    items.append({"aa":aa,"album":al,"key":key,"art":art if ok else ""})
pages=max(1, math.ceil(len(items)/psize))
page=max(0, min(page, pages-1))
sl=items[page*psize:(page+1)*psize]
rows=[sl[i:i+cols] for i in range(0,len(sl),cols)]
print("%d\t%d\t%s"%(pages, page, json.dumps(rows)))' < "$ALBUMS_TSV" 2>/dev/null
}

push_grid(){
  local out pages page json
  out=$(grid_slice); [ -z "$out" ] && return 0
  pages=${out%%$'\t'*}; out=${out#*$'\t'}; page=${out%%$'\t'*}; json=${out#*$'\t'}
  echo "$page" > "$GP"
  "$EWW" update grid="$json" grid_page="$page" grid_pages="$pages" >/dev/null 2>&1
}

# Build the full track list for one album into TRACKS_JSON.
tracks_all(){
  local aa="$1" al="$2" out
  out=$(mpc -f '%title%\t%file%' find albumartist "$aa" album "$al" 2>/dev/null)
  [ -z "$out" ] && out=$(mpc -f '%title%\t%file%' find album "$al" 2>/dev/null)
  printf '%s' "$out" | python3 -c '
import sys, json
o=[]
for ln in sys.stdin.read().splitlines():
    p=ln.split("\t")
    if len(p)<2: continue
    ti,f=p[0],p[1]
    o.append({"label": ti or f.rsplit("/",1)[-1], "file": f})
print(json.dumps(o))' > "$TRACKS_JSON"
}

push_tracks(){
  local page out pages json
  page=$(cat "$TP" 2>/dev/null || echo 0)
  out=$(F="$TRACKS_JSON" PSIZE="$TRACK_PSIZE" PAGE="$page" python3 -c '
import os, json, math
data=json.load(open(os.environ["F"]))
psize=int(os.environ["PSIZE"]); page=int(os.environ["PAGE"])
pages=max(1, math.ceil(len(data)/psize)) if data else 1
page=max(0, min(page, pages-1))
print("%d\t%d\t%s"%(pages, page, json.dumps(data[page*psize:(page+1)*psize])))' 2>/dev/null)
  [ -z "$out" ] && return 0
  pages=${out%%$'\t'*}; out=${out#*$'\t'}; page=${out%%$'\t'*}; json=${out#*$'\t'}
  echo "$page" > "$TP"
  "$EWW" update gridtracks="$json" track_page="$page" track_pages="$pages" >/dev/null 2>&1
}

# prev|next|<n> -> new page index (clamped >= 0; upper clamp happens in push_*).
step(){ local cur="$1" arg="$2"; case "$arg" in prev) cur=$((cur-1));; next) cur=$((cur+1));; *) cur=${arg:-0};; esac; [ "$cur" -lt 0 ] && cur=0; echo "$cur"; }

# Resolve a single album's cover into the cache (no-op if already present).
resolve_one(){
  local aa="$1" al="$2" file="$3" key art dir img enc url
  key=$(ckey "$aa" "$al"); art="$CACHE/$key.jpg"
  [ -s "$art" ] && return 0
  dir="$MUSIC/$(dirname "$file")"
  img=$(find "$dir" -maxdepth 1 \( -iname 'cover.*' -o -iname 'folder.*' -o -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -1)
  if [ -n "$img" ]; then cp "$img" "$art" 2>/dev/null
  elif ffmpeg -v error -i "$MUSIC/$file" -an -vcodec copy "$art.tmp.jpg" 2>/dev/null && [ -s "$art.tmp.jpg" ]; then
    mv "$art.tmp.jpg" "$art"
  else
    rm -f "$art.tmp.jpg"
    enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$aa $al")
    url=$(fetch "https://itunes.apple.com/search?term=${enc}&entity=album&limit=1" | python3 -c '
import sys, json
try:
    r=json.load(sys.stdin).get("results",[])
    print(r[0]["artworkUrl100"].replace("100x100bb","600x600bb") if r else "")
except Exception: print("")')
    [ -n "$url" ] && fetch "$url" > "$art.tmp" 2>/dev/null && [ -s "$art.tmp" ] && mv "$art.tmp" "$art" || rm -f "$art.tmp"
  fi
}

# Fill every missing cover, re-pushing the current grid page as each lands.
resolve_all(){
  albums_raw | while IFS=$'\t' read -r aa al f; do
    [ -s "$CACHE/$(ckey "$aa" "$al").jpg" ] && continue
    resolve_one "$aa" "$al" "$f" && push_grid
  done
}

case "${1:-}" in
  open)   albums_raw > "$ALBUMS_TSV"; echo 0 > "$GP"
          "$EWW" update gridding=true gridview=albums gridtitle=Albums gridaa="" >/dev/null 2>&1
          push_grid; ( "$0" _resolve >/dev/null 2>&1 & ) ;;
  close)  "$EWW" update gridding=false >/dev/null 2>&1 ;;
  album)  echo 0 > "$TP"; tracks_all "${2:-}" "${3:-}"
          "$EWW" update gridview=album gridaa="${2:-}" gridtitle="${3:-}" >/dev/null 2>&1
          push_tracks ;;
  back)   "$EWW" update gridview=albums >/dev/null 2>&1 ;;
  gridpage)  step "$(cat "$GP" 2>/dev/null || echo 0)" "${2:-}" > "$GP"; push_grid ;;
  trackpage) step "$(cat "$TP" 2>/dev/null || echo 0)" "${2:-}" > "$TP"; push_tracks ;;
  playalbum) mpc -q clear; mpc -q findadd albumartist "${2:-}" album "${3:-}" 2>/dev/null \
                || mpc -q findadd album "${3:-}"; mpc -q play
             "$EWW" update gridding=false >/dev/null 2>&1 ;;
  playtrack) mpc -q clear; mpc -q add "${2:-}"; mpc -q play
             "$EWW" update gridding=false >/dev/null 2>&1 ;;
  _resolve) resolve_all ;;
esac

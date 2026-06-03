#!/usr/bin/env bash
# Album-cover grid browser for the deck. The on-disk layout is inconsistent
# (some albums in Artist/Album/ dirs, some flat with odd filenames), so albums
# are enumerated from mpd tags, never the filesystem. Each album's cover is
# resolved once (local image -> embedded art -> iTunes) and cached with the
# SAME key scheme as cover-palette, so a played album reuses the grid thumbnail
# and vice-versa. Two levels: album grid -> per-album track list -> play.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
EWW="$HOME/.local/bin/eww"
CACHE="$HOME/.cache/music-card"; mkdir -p "$CACHE"
MUSIC="$HOME/Music"
COLS=4
fetch(){ curl -fsSL "$1" 2>/dev/null || wget -qO- "$1" 2>/dev/null; }
ckey(){ printf '%s' "$1|$2" | md5sum | cut -c1-16; }   # aa|album (matches cover-palette)

# All (albumartist, album) pairs with one representative file, deduped, tab-sep.
albums_raw(){
  mpc -f '%albumartist%\t%artist%\t%album%\t%file%' find '(Album != "")' 2>/dev/null \
    | awk -F'\t' '{aa=($1!=""?$1:$2); if(!seen[aa,$3]++) printf "%s\t%s\t%s\n", aa, $3, $4}'
}

# Grid JSON: rows (arrays) of COLS album objects {aa,album,art,key}.
grid_json(){
  albums_raw | CACHE="$CACHE" COLS="$COLS" python3 -c '
import sys, os, json, hashlib
cache=os.environ["CACHE"]; cols=int(os.environ["COLS"]); items=[]
for ln in sys.stdin.read().splitlines():
    p=ln.split("\t")
    if len(p)<3: continue
    aa,al,f=p[0],p[1],p[2]
    key=hashlib.md5(("%s|%s"%(aa,al)).encode()).hexdigest()[:16]
    art=os.path.join(cache, key+".jpg")
    ok=os.path.exists(art) and os.path.getsize(art)>0
    items.append({"aa":aa,"album":al,"key":key,"art":art if ok else ""})
rows=[items[i:i+cols] for i in range(0,len(items),cols)]
print(json.dumps(rows))'
}

# Track list JSON for one album: [{label,file}] in track order.
tracks_json(){
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
print(json.dumps(o))'
}

push_grid(){ "$EWW" update grid="$(grid_json)" >/dev/null 2>&1; }

# Resolve a single album's cover into the cache (no-op if already present).
resolve_one(){
  local aa="$1" al="$2" file="$3" key art dir img term enc url
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

# Fill every missing cover, re-pushing the grid as each lands so tiles pop in.
resolve_all(){
  albums_raw | while IFS=$'\t' read -r aa al f; do
    [ -s "$CACHE/$(ckey "$aa" "$al").jpg" ] && continue
    resolve_one "$aa" "$al" "$f" && push_grid
  done
}

case "${1:-}" in
  open)   "$EWW" update gridding=true gridview=albums gridtitle=Albums gridaa="" >/dev/null 2>&1
          push_grid; ( "$0" _resolve >/dev/null 2>&1 & ) ;;
  close)  "$EWW" update gridding=false >/dev/null 2>&1 ;;
  album)  "$EWW" update gridview=album gridaa="${2:-}" gridtitle="${3:-}" \
                  gridtracks="$(tracks_json "${2:-}" "${3:-}")" >/dev/null 2>&1 ;;
  back)   "$EWW" update gridview=albums >/dev/null 2>&1 ;;
  playalbum) mpc -q clear; mpc -q findadd albumartist "${2:-}" album "${3:-}" 2>/dev/null \
                || mpc -q findadd album "${3:-}"; mpc -q play
             "$EWW" update gridding=false >/dev/null 2>&1 ;;
  playtrack) mpc -q clear; mpc -q add "${2:-}"; mpc -q play
             "$EWW" update gridding=false >/dev/null 2>&1 ;;
  _resolve) resolve_all ;;
esac

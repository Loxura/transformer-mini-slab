#!/usr/bin/env bash
# Resolve the current track's album art and derive a palette for the card.
# Emits one JSON line for eww: {"art","bg","accent","text"}.
# Art: local cover.*/folder.* next to the tracks → embedded (ffmpeg) → iTunes Search API.
# Cached per album in ~/.cache/music-card/. Palette derived from the cover via ffmpeg.
set -uo pipefail
CACHE="$HOME/.cache/music-card"; mkdir -p "$CACHE"
DEFAULT='{"art":"","bg":"#16161e","accent":"#7aa2f7","text":"#e6e6ee","glow":"#7aa2f7"}'
emit(){ printf '%s\n' "$1"; }
fetch(){ curl -fsSL "$1" 2>/dev/null || wget -qO- "$1" 2>/dev/null; }

file=$(mpc -f %file% current 2>/dev/null)
[ -z "$file" ] && { emit "$DEFAULT"; exit; }
album=$(mpc -f %album% current 2>/dev/null)
aartist=$(mpc -f %albumartist% current 2>/dev/null); [ -z "$aartist" ] && aartist=$(mpc -f %artist% current 2>/dev/null)
title=$(mpc -f %title% current 2>/dev/null)

key=$(printf '%s' "${aartist}|${album:-$title}" | md5sum | cut -c1-16)
art="$CACHE/$key.jpg"
dir="$HOME/Music/$(dirname "$file")"

if [ ! -s "$art" ]; then
  # 1) local folder image
  local_img=$(find "$dir" -maxdepth 1 \( -iname 'cover.*' -o -iname 'folder.*' -o -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -1)
  if [ -n "$local_img" ]; then cp "$local_img" "$art"
  # 2) embedded art
  elif ffmpeg -v error -i "$HOME/Music/$file" -an -vcodec copy "$art.tmp.jpg" 2>/dev/null && [ -s "$art.tmp.jpg" ]; then
    mv "$art.tmp.jpg" "$art"
  else
  # 3) iTunes Search API
    rm -f "$art.tmp.jpg"
    if [ -n "$album" ]; then term="$aartist $album"; ent=album; else term="$aartist $title"; ent=song; fi
    enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$term")
    url=$(fetch "https://itunes.apple.com/search?term=${enc}&entity=${ent}&limit=1" | python3 -c '
import sys,json
try:
    r=json.load(sys.stdin).get("results",[])
    print(r[0]["artworkUrl100"].replace("100x100bb","600x600bb") if r else "")
except Exception: print("")')
    [ -n "$url" ] && fetch "$url" > "$art.tmp" 2>/dev/null && [ -s "$art.tmp" ] && mv "$art.tmp" "$art" || rm -f "$art.tmp"
  fi
fi

[ ! -s "$art" ] && { emit "$DEFAULT"; exit; }

pal=$(ffmpeg -v error -i "$art" -vf scale=4:4 -f rawvideo -pix_fmt rgb24 - 2>/dev/null | python3 -c '
import sys
d=sys.stdin.buffer.read()
px=[(d[i],d[i+1],d[i+2]) for i in range(0,len(d)-2,3)]
if not px: print(""); sys.exit()
n=len(px)
a=(sum(p[0] for p in px)//n, sum(p[1] for p in px)//n, sum(p[2] for p in px)//n)
bg=tuple(int(c*0.32) for c in a)                       # dark, cover-tinted
acc=max(px,key=lambda p:max(p)-min(p))                 # most saturated pixel
mx=max(acc) or 1
glow=tuple(min(255,int(c*235/mx)) for c in acc)        # accent brightened so the glow reads on a dark bg
hx=lambda c:"#%02x%02x%02x"%tuple(c)
print(hx(bg)+" "+hx(acc)+" "+hx(glow))')
read -r bg accent glow <<<"$pal"
[ -z "$bg" ] && bg="#16161e"; [ -z "$accent" ] && accent="#7aa2f7"; [ -z "$glow" ] && glow="#7aa2f7"
emit "{\"art\":\"$art\",\"bg\":\"$bg\",\"accent\":\"$accent\",\"text\":\"#e6e6ee\",\"glow\":\"$glow\"}"

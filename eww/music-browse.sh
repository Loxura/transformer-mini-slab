#!/usr/bin/env bash
# Tap-focused library browser for the deck card. Navigates mpd's directory tree
# (cd / cd ..) and plays a tapped song now (replacing the queue). State (the current
# path) is kept in a cache file; each action recomputes the listing and pushes it
# straight into eww vars so taps feel instant.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
EWW="$HOME/.local/bin/eww"
STATE="$HOME/.cache/music-card/browse-path"
mkdir -p "$(dirname "$STATE")"

audio_re='\.(flac|mp3|m4a|opus|ogg|wav|aac|wma)$'

# Build the JSON listing for a directory path (relative to the mpd music root).
# Dirs first, then songs (with nice titles). Each entry: {type,path,label}.
listing() {
  local path="$1"
  local titles=""
  # song titles in one batched call (skip at root - that level is all dirs)
  [ -n "$path" ] && titles=$(mpc -f '%file%\t%title%' search base "$path" 2>/dev/null)
  mpc ls "$path" 2>/dev/null | TITLES="$titles" RE="$audio_re" python3 -c '
import sys, os, json, re
rx = re.compile(os.environ["RE"], re.I)
titles = {}
for ln in os.environ.get("TITLES","").splitlines():
    if "\t" in ln:
        f,t = ln.split("\t",1); titles[f]=t
dirs, songs = [], []
for e in sys.stdin.read().splitlines():
    if not e: continue
    base = e.rsplit("/",1)[-1]
    if rx.search(e):
        songs.append({"type":"song","path":e,"label":titles.get(e,base)})
    else:
        dirs.append({"type":"dir","path":e,"label":base})
print(json.dumps(dirs+songs))'
}

push() {                          # path -> update eww (browse list + breadcrumb)
  local path="$1"
  printf '%s' "$path" > "$STATE"
  local crumb="Library"; [ -n "$path" ] && crumb="$path"
  "$EWW" update browse="$(listing "$path")" browsepath="$crumb" >/dev/null 2>&1
}

case "${1:-}" in
  open)  push ""; "$EWW" update browsing=true  >/dev/null 2>&1 ;;
  close) "$EWW" update browsing=false >/dev/null 2>&1 ;;
  cd)    push "${2:-}" ;;
  up)    cur=$(cat "$STATE" 2>/dev/null || echo ""); parent="${cur%/*}"; [ "$parent" = "$cur" ] && parent=""; push "$parent" ;;
  play)  mpc -q clear; mpc -q add "${2:-}"; mpc -q play; "$EWW" update browsing=false >/dev/null 2>&1 ;;
esac

#!/usr/bin/env bash
# Recently-added playable folders for the card's "New arrivals" row, as JSON for eww `for`.
# Works for any layout (flat ~/Music/<Artist>/tracks, or ~/Music/<Artist>/<Album>/tracks):
# it finds the folders that directly contain audio, newest first. Paths are relative to the
# mpd music_directory so `mpc add "<path>"` plays that folder.
LIB="$HOME/Music"
find "$LIB" -type f \
     \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.opus' -o -iname '*.ogg' -o -iname '*.wav' \) \
     -printf '%T@\t%h\n' 2>/dev/null \
  | sort -rn \
  | awk -F'\t' '!seen[$2]++ {print $2}' \
  | head -8 \
  | python3 -c '
import sys, os, json
lib = os.path.expanduser("~/Music")
out = []
for line in sys.stdin:
    d = line.rstrip("\n")
    if not d: continue
    rel = os.path.relpath(d, lib)
    name = rel.replace("/", " — ")
    out.append({"path": rel, "name": name})
print(json.dumps(out))'

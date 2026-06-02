#!/usr/bin/env bash
# deflisten source for eww: run cava in raw-ASCII mode and turn each frame
# ("v;v;...;v;") into a JSON array ("[v,v,...,v]") for the card's visualizer.
# A bash read-loop is used instead of awk because mawk block-buffers its input and
# would stall on cava's slow (20fps) stream.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
CFG="$HOME/.config/cava/eww.conf"

stdbuf -oL cava -p "$CFG" 2>/dev/null | while IFS= read -r line; do
  line="${line%;}"             # drop the trailing bar delimiter
  printf '[%s]\n' "${line//;/,}"
done

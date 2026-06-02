#!/bin/sh
# Deck swipe navigation: cycle workspaces 1<->2<->3 by direction, with wraparound.
# Uses `workspace number N` (which re-creates a workspace) instead of prev/next,
# because the Dash workspace holds only an eww *layer-shell* surface (not a window),
# so sway destroys it when empty — and plain `workspace prev` then can't return to it.
cur=$(swaymsg -t get_workspaces \
  | python3 -c 'import sys,json; print(next((w["num"] for w in json.load(sys.stdin) if w.get("focused")),1))' 2>/dev/null)
[ -z "$cur" ] && cur=1
case "$1" in
  next) n=$((cur+1)); [ "$n" -gt 3 ] && n=1 ;;
  prev) n=$((cur-1)); [ "$n" -lt 1 ] && n=3 ;;
  *)    exit 1 ;;
esac
exec swaymsg workspace number "$n"

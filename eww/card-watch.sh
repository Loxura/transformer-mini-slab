#!/usr/bin/env bash
# Show the music card ONLY while the "2:Music" workspace is focused. Same default eww
# daemon as the Dash; just a different window. Mirrors dash-watch.sh — bg layer, gated,
# launched from sway exec only (no systemd service), so it can't stick or respawn.
set -uo pipefail

EWW="$HOME/.local/bin/eww"
WS_MUSIC="2:Music"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  for s in "$XDG_RUNTIME_DIR"/wayland-*; do
    [ -S "$s" ] && [ "${s##*.}" != "lock" ] && { WAYLAND_DISPLAY="${s##*/}"; break; }
  done; export WAYLAND_DISPLAY
fi
if [ -z "${SWAYSOCK:-}" ]; then
  for s in "$XDG_RUNTIME_DIR"/sway-ipc.*.sock; do [ -S "$s" ] && { SWAYSOCK="$s"; break; }; done
  export SWAYSOCK
fi

open()  { "$EWW" open  musiccard >/dev/null 2>&1 || true; }
close() { "$EWW" close musiccard >/dev/null 2>&1 || true; }

focused_ws() {
  swaymsg -t get_workspaces 2>/dev/null | python3 -c \
    'import sys,json; print(next((w["name"] for w in json.load(sys.stdin) if w.get("focused")),""))' 2>/dev/null
}

"$EWW" daemon >/dev/null 2>&1 || true
[ "$(focused_ws)" = "$WS_MUSIC" ] && open || close

swaymsg -m -r -t subscribe '["workspace"]' 2>/dev/null | while read -r line; do
  name=$(printf '%s' "$line" | python3 -c \
    'import sys,json
try:
    e=json.load(sys.stdin); print((e.get("current") or {}).get("name",""))
except Exception:
    print("")' 2>/dev/null)
  [ -z "$name" ] && continue
  if [ "$name" = "$WS_MUSIC" ]; then open; else close; fi
done

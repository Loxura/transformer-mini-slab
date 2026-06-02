#!/usr/bin/env bash
# Show the Dash ONLY while the "1:Dash" workspace is focused. Without this, the Dash's
# background layer renders on every empty workspace (so Video/ws3 looks identical to ws1).
# Mirrors music-card/bin/np-music-watch but for the default eww (Dash) config.
set -uo pipefail

EWW="$HOME/.local/bin/eww"
WS_DASH="1:Dash"

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

open()  { "$EWW" open  dashboard >/dev/null 2>&1 || true; }
close() { "$EWW" close dashboard >/dev/null 2>&1 || true; }

focused_ws() {
  swaymsg -t get_workspaces 2>/dev/null | python3 -c \
    'import sys,json; print(next((w["name"] for w in json.load(sys.stdin) if w.get("focused")),""))' 2>/dev/null
}

"$EWW" daemon >/dev/null 2>&1 || true
[ "$(focused_ws)" = "$WS_DASH" ] && open || close

swaymsg -m -r -t subscribe '["workspace"]' 2>/dev/null | while read -r line; do
  name=$(printf '%s' "$line" | python3 -c \
    'import sys,json
try:
    e=json.load(sys.stdin); print((e.get("current") or {}).get("name",""))
except Exception:
    print("")' 2>/dev/null)
  [ -z "$name" ] && continue
  if [ "$name" = "$WS_DASH" ]; then open; else close; fi
done

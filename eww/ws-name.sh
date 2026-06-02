#!/usr/bin/env bash
# deflisten source for eww: prints the focused sway workspace name, once now and then
# on every change. The `deck` window switches mode content off this value.
set -uo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${SWAYSOCK:-}" ]; then
  for s in "$XDG_RUNTIME_DIR"/sway-ipc.*.sock; do [ -S "$s" ] && { SWAYSOCK="$s"; break; }; done
  export SWAYSOCK
fi

# initial value
swaymsg -t get_workspaces 2>/dev/null | python3 -c \
  'import sys,json; print(next((w["name"] for w in json.load(sys.stdin) if w.get("focused")),"1:Dash"))' 2>/dev/null

# stream on change. Only the "focus" change carries the newly-focused workspace in
# `current`; "empty"/"init" events (fired when leaving a layer-only Dash/Music ws)
# carry a DIFFERENT workspace and would clobber the value one event late.
swaymsg -m -r -t subscribe '["workspace"]' 2>/dev/null | while read -r line; do
  printf '%s' "$line" | python3 -c \
    'import sys,json
try:
    e=json.load(sys.stdin)
    if e.get("change")=="focus":
        n=(e.get("current") or {}).get("name","")
        if n: print(n)
except Exception:
    pass' 2>/dev/null
done

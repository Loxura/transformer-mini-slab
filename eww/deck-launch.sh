#!/usr/bin/env bash
# Start the eww daemon (with a resolved Wayland/sway env) and open the single `deck`
# window. Replaces dash-watch + card-watch: there is no per-workspace gating anymore,
# the deck's content follows the focused workspace via the `ws` deflisten.
set -uo pipefail
EWW="$HOME/.local/bin/eww"

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

"$EWW" daemon >/dev/null 2>&1 || true
sleep 1
"$EWW" open deck >/dev/null 2>&1 || true

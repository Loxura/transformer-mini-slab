#!/usr/bin/env bash
# Switch the deck to a mode (sway workspace) by number -- used by the Dash mode rail taps,
# so mode-switching never depends solely on a swipe gesture that can misfire. Discovers
# SWAYSOCK the same way ws-name.sh does, so it works whether or not eww exported it.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${SWAYSOCK:-}" ]; then
  for s in "$XDG_RUNTIME_DIR"/sway-ipc.*.sock; do [ -S "$s" ] && { SWAYSOCK="$s"; break; }; done
  export SWAYSOCK
fi
case "${1:-}" in
  1) ws="1:Dash" ;;
  2) ws="2:Music" ;;
  3) ws="3:Cooking" ;;
  *) exit 1 ;;
esac
exec swaymsg workspace "$ws" >/dev/null 2>&1

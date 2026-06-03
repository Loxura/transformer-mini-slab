#!/usr/bin/env bash
# Single-value audio level for the "breathing" cover glow. cava with ONE bar
# emits a smoothed overall loudness (0-100); we push it to the eww `level` var
# each frame. One var + one widget = cheap, and the cover's CSS transition tweens
# between frames so the glow breathes instead of stepping. Same anti-leak handling
# as the old visualizer: reap any stale cava for this config and make our child
# die with us (eww restarts this deflisten on every reload).
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
CFG="$HOME/.config/cava/level.conf"

pkill -f "cava -p $CFG" 2>/dev/null
sleep 0.2

coproc CAVA { stdbuf -oL cava -p "$CFG" 2>/dev/null; }
trap 'kill "$CAVA_PID" 2>/dev/null' EXIT INT TERM

while IFS= read -r line <&"${CAVA[0]}"; do
  printf '%s\n' "${line%;}"      # "NN;" -> "NN"
done

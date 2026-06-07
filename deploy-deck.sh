#!/usr/bin/env bash
# Deploy the deck (Dash + Music + Cooking) to the tablet. Mirrors how the deck is laid out there:
#   eww/*.sh         -> ~/.local/bin/<name>      (strip .sh, +x; these are the deck's commands)
#   sway/deck-swipe.sh-> ~/.local/bin/deck-swipe
#   eww/gcal-events.py-> ~/.local/bin/gcal-events.py
#   eww.yuck/scss, events.txt -> ~/.config/eww/
#   eww/level.conf   -> ~/.config/cava/         (audio-level reads it there)
#   sway/config      -> ~/.config/sway/config
# Then backs up the previous eww.{yuck,scss} to .predeploy and reloads eww (+ sway, best-effort).
#
# The deck's eww binary, secrets (tandoor-token/url, gcal-url) and the separate music-card
# (~/.config/eww-music, deployed by music-card/bin/deploy-card) are NOT touched.
#
# Usage:  ./deploy-deck.sh [user@host]        (default: $DECK or minideck@192.168.0.32)
#         DECK=minideck@192.168.0.32 ./deploy-deck.sh
#         ./deploy-deck.sh --dry-run          (show what would ship, change nothing)
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
DRY="${DRY:-0}"; ARGS=()
for a in "$@"; do case "$a" in --dry-run) DRY=1;; *) ARGS+=("$a");; esac; done
DECK="${ARGS[0]:-${DECK:-minideck@192.168.0.32}}"

say(){ printf '  %s\n' "$*"; }
scpq(){ [ "$DRY" = 1 ] && { say "would scp $1 -> $2"; return; }; scp -q "$@"; }

lbl=""; [ "$DRY" = 1 ] && lbl=" (dry-run)"
echo "== deploy deck -> $DECK$lbl =="

# 0. reachable?
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$DECK" true 2>/dev/null; then
  echo "  ! $DECK unreachable over ssh — is the tablet on and on the LAN?" >&2; exit 1
fi

# 1. ensure target dirs + back up the configs we replace (one-level rollback)
[ "$DRY" = 1 ] || ssh "$DECK" '
  mkdir -p ~/.local/bin ~/.config/eww ~/.config/cava ~/.config/sway
  cd ~/.config/eww && for f in eww.yuck eww.scss; do [ -f "$f" ] && cp "$f" "$f.predeploy"; done; true'
say "backed up ~/.config/eww/{eww.yuck,eww.scss} -> .predeploy"

# 2. deck command scripts -> ~/.local/bin/<name> (strip .sh)
for f in "$REPO"/eww/*.sh "$REPO"/sway/deck-swipe.sh; do
  scpq "$f" "$DECK:.local/bin/$(basename "$f" .sh)"
done
scpq "$REPO/eww/gcal-events.py" "$DECK:.local/bin/gcal-events.py"
[ "$DRY" = 1 ] || ssh "$DECK" 'chmod +x ~/.local/bin/* 2>/dev/null; true'
say "installed deck scripts -> ~/.local/bin"

# 3. config files to their homes
scpq "$REPO/eww/eww.yuck"  "$DECK:.config/eww/eww.yuck"
scpq "$REPO/eww/eww.scss"  "$DECK:.config/eww/eww.scss"
scpq "$REPO/eww/events.txt" "$DECK:.config/eww/events.txt"
scpq "$REPO/eww/level.conf" "$DECK:.config/cava/level.conf"
scpq "$REPO/sway/config"   "$DECK:.config/sway/config"
say "installed eww/cava/sway configs"

# 4. reload (eww always; sway best-effort — only matters if sway/config changed)
if [ "$DRY" = 1 ]; then echo "== dry-run: nothing changed =="; exit 0; fi
ssh "$DECK" '
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  ~/.local/bin/eww reload >/dev/null 2>&1 && echo "  eww reloaded" || echo "  ! eww reload failed (daemon running?)"
  sock=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)
  [ -n "$sock" ] && SWAYSOCK="$sock" swaymsg reload >/dev/null 2>&1 && echo "  sway reloaded" || echo "  (sway not reloaded — reload by hand if sway/config changed)"
  echo "  active windows: $(~/.local/bin/eww active-windows 2>/dev/null | tr "\n" " ")"'
echo "== done =="

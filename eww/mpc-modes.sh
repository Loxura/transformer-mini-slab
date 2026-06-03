#!/usr/bin/env bash
# mpd play-mode flags as JSON {repeat,single,consume,random} for the Music card toggles.
# Parsed from the `mpc status` flag line (e.g. "repeat: on  random: off  single: off ...").
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
s=$(mpc status 2>/dev/null | grep -E 'repeat:|random:|single:|consume:')
get(){ printf '%s' "$s" | grep -oE "$1: ?[a-z0-9]+" | head -1 | awk '{print $2}'; }
j(){ [ "$1" = "on" ] && echo true || echo false; }   # "oneshot"/"off" -> false
printf '{"repeat":%s,"single":%s,"consume":%s,"random":%s}\n' \
  "$(j "$(get repeat)")" "$(j "$(get single)")" "$(j "$(get consume)")" "$(j "$(get random)")"

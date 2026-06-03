#!/usr/bin/env bash
# Now-playing progress as JSON {pct,elapsed,total} for the Music card seek bar. Parses the
# "M:SS/M:SS (NN%)" field of `mpc status`. pct drives the segmented fill; tapping a segment
# calls `music-ctl seek <pct>` (discrete tap-seek -- drag-scrub is unreliable on this surface).
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
line=$(mpc status 2>/dev/null | sed -n '2p')
times=$(printf '%s' "$line" | grep -oE '[0-9]+:[0-9]{2}/[0-9]+:[0-9]{2}' | head -1)
pct=$(printf '%s' "$line" | grep -oE '\([0-9]+%\)' | grep -oE '[0-9]+' | head -1)
el="${times%%/*}"; to="${times##*/}"
[ -z "$el" ] && el="0:00"; [ -z "$to" ] && to="0:00"; [ -z "$pct" ] && pct=0
printf '{"pct":%d,"elapsed":"%s","total":"%s"}\n' "$pct" "$el" "$to"

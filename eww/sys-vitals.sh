#!/usr/bin/env bash
# System vitals for the Dash status rail: battery+charge, thermal, root + music-disk
# usage, loadavg. All LOCAL (sysfs / df / /proc) -- no network, light enough to poll at
# 30s. Every field degrades to "--" when its source is absent (e.g. WSL/VM has no
# battery or thermal zone) so the rail never breaks. The *_warn flags drive the cell's
# hazard colour in eww. This matters on a 2016 Atom: it thermally throttles, and a full
# music disk is the other thing that actually breaks the appliance.
set -uo pipefail

bat=""; chg="false"
for b in /sys/class/power_supply/BAT*; do
  [ -r "$b/capacity" ] || continue
  bat=$(cat "$b/capacity" 2>/dev/null)
  st=$(cat "$b/status" 2>/dev/null)
  { [ "$st" = "Charging" ] || [ "$st" = "Full" ]; } && chg="true"
  break
done

temp=""; hot=0
for z in /sys/class/thermal/thermal_zone*/temp; do
  [ -r "$z" ] || continue
  v=$(cat "$z" 2>/dev/null); [ -z "$v" ] && continue
  v=$(( v / 1000 )); [ "$v" -gt "$hot" ] && hot=$v
done
[ "$hot" -gt 0 ] && temp=$hot

disk=$(df -P /        2>/dev/null | awk 'NR==2{print $5}')
sd=$(df   -P "$HOME/Music" 2>/dev/null | awk 'NR==2{print $5}')
load=$(awk '{print $1}' /proc/loadavg 2>/dev/null)

python3 - "$bat" "$chg" "$temp" "$disk" "$sd" "$load" <<'PY'
import sys, json
bat, chg, temp, disk, sd, load = sys.argv[1:7]
def pct(x):
    try: return int(str(x).rstrip("%"))
    except: return None
b=int(bat) if bat else None; t=int(temp) if temp else None
d=pct(disk); s=pct(sd)
print(json.dumps({
  "bat":  (bat+"%") if bat else "--",
  "chg":  chg == "true",
  "temp": (temp+"C") if temp else "--",
  "disk": disk or "--",
  "sd":   sd or "--",
  "load": load or "--",
  "bat_warn":  (b is not None and b < 20 and chg != "true"),
  "temp_warn": (t is not None and t >= 70),
  "disk_warn": (d is not None and d >= 90),
  "sd_warn":   (s is not None and s >= 90),
}))
PY

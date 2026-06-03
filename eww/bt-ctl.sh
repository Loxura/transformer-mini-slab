#!/usr/bin/env bash
# Bluetooth pairing/connection backend for the deck (bluez 5.82). Drives
# bluetoothctl and pushes device JSON into eww vars; the panel in the music
# card renders it. An audio device connected here shows up as a PipeWire sink
# and WirePlumber auto-routes mpd to it. Runs in the sway session, so polkit
# permits power/scan/pair/connect without sudo.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
EWW="$HOME/.local/bin/eww"
CACHE="$HOME/.cache/music-card"; mkdir -p "$CACHE"
SCANPID="$CACHE/bt-scan.pid"

# Known + discovered devices -> JSON, connected first then paired then named.
list_json(){
  local all conn pair
  all=$(bluetoothctl devices 2>/dev/null)
  conn=$(bluetoothctl devices Connected 2>/dev/null)
  pair=$(bluetoothctl devices Paired 2>/dev/null)
  CONN="$conn" PAIR="$pair" python3 -c '
import sys, os, json, re
conn=set(re.findall(r"Device (\S+)", os.environ.get("CONN","")))
pair=set(re.findall(r"Device (\S+)", os.environ.get("PAIR","")))
out=[]
for ln in sys.stdin.read().splitlines():
    m=re.match(r"Device (\S+) (.+)", ln.strip())
    if not m: continue
    mac, name = m.group(1), m.group(2)
    unnamed = name.replace("-",":").upper()==mac.upper()
    out.append({"mac":mac, "name":("Unknown device" if unnamed else name),
                "connected":mac in conn, "paired":mac in pair, "unnamed":unnamed})
# Stable order keyed on the immutable MAC. Sorting by connected/paired/name made
# rows JUMP whenever a device connected or its name resolved mid-scan -- the list
# churned under the user finger and looked like it was tapping itself.
out.sort(key=lambda d: d["mac"])
print(json.dumps(out))' <<<"$all"
}

status_json(){
  local powered conn
  bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && powered=true || powered=false
  conn=$(bluetoothctl devices Connected 2>/dev/null | sed -n 's/^Device [^ ]* //p' | head -1)
  conn=${conn//\"/}
  printf '{"powered":%s,"connected":"%s"}' "$powered" "$conn"
}

push(){ "$EWW" update bt="$(list_json)" btstatus="$(status_json)" >/dev/null 2>&1; }

stop_scan(){ [ -f "$SCANPID" ] && kill "$(cat "$SCANPID")" 2>/dev/null; rm -f "$SCANPID"; }

# Timed discovery in the background, refreshing the list as devices appear.
start_scan(){
  stop_scan
  ( bluetoothctl --timeout 20 scan on >/dev/null 2>&1 ) &
  echo $! > "$SCANPID"
  for _ in 1 2 3 4 5 6 7; do sleep 3; push; done
  rm -f "$SCANPID"
}

is_connected(){ bluetoothctl devices Connected 2>/dev/null | grep -qiF "$1"; }

is_paired(){ bluetoothctl devices Paired 2>/dev/null | grep -qiF "$1"; }

connect_dev(){
  local mac="$1"
  is_paired "$mac" || bluetoothctl pair "$mac" >/dev/null 2>&1   # don't re-pair every tap
  bluetoothctl trust "$mac"   >/dev/null 2>&1
  bluetoothctl connect "$mac" >/dev/null 2>&1
}

case "${1:-}" in
  open)   bluetoothctl power on    >/dev/null 2>&1
          bluetoothctl pairable on >/dev/null 2>&1
          # disarm the rows so the tap that opened the panel can't fall through onto one
          "$EWW" update bting=true bt_armed=false >/dev/null 2>&1
          ( sleep 0.4; "$EWW" update bt_armed=true >/dev/null 2>&1 ) &
          push; ( "$0" _scan >/dev/null 2>&1 & ) ;;
  close)  stop_scan; bluetoothctl scan off >/dev/null 2>&1
          bluetoothctl pairable off >/dev/null 2>&1
          "$EWW" update bting=false bt_armed=true >/dev/null 2>&1 ;;
  _scan)  start_scan ;;
  rescan) ( "$0" _scan >/dev/null 2>&1 & ) ;;
  toggle) mac="${2:-}"; [ -z "$mac" ] && exit 0
          # Per-device lock: a stray double-contact (or a 2nd tap while the 1st is
          # still connecting) is dropped instead of thrashing connect<->disconnect.
          LOCK="$CACHE/bt-${mac//[^A-Fa-f0-9]/_}.lock"
          exec 9>"$LOCK"; flock -n 9 || exit 0
          if is_connected "$mac"; then bluetoothctl disconnect "$mac" >/dev/null 2>&1
          else connect_dev "$mac"; fi
          sleep 1; push ;;
  power)  bluetoothctl power "${2:-on}" >/dev/null 2>&1; push ;;
esac

#!/usr/bin/env python3
# Upcoming events for the eww Dash from a Google Calendar *secret iCal URL*.
# Pure standard library (no extra packages). The URL is read from
# ~/.config/eww/gcal-url (kept private — NOT in the repo). Add/edit events in the
# Google Calendar app; they appear here on the next poll.
# (Non-recurring events; repeating events show their base date.)
import datetime, os, sys, urllib.request
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

URLFILE = os.path.expanduser("~/.config/eww/gcal-url")
try:
    url = open(URLFILE).read().strip()
except FileNotFoundError:
    print("add your Google Calendar iCal URL to ~/.config/eww/gcal-url"); sys.exit()
if not url:
    print("add your Google Calendar iCal URL to ~/.config/eww/gcal-url"); sys.exit()
try:
    raw = urllib.request.urlopen(url, timeout=15).read().decode("utf-8", "replace")
except Exception:
    print("calendar unavailable"); sys.exit()

# unfold continuation lines (ICS folds with a leading space/tab)
lines = []
for ln in raw.split("\n"):
    ln = ln.rstrip("\r")
    if ln[:1] in (" ", "\t") and lines:
        lines[-1] += ln[1:]
    else:
        lines.append(ln)

def parse_dt(val, params):
    if "VALUE=DATE" in params or (len(val) == 8 and "T" not in val):
        try:
            return datetime.datetime.strptime(val, "%Y%m%d").replace(tzinfo=datetime.timezone.utc), True
        except Exception:
            return None, None
    tz = datetime.timezone.utc
    v = val
    if v.endswith("Z"):
        v = v[:-1]
    else:
        for p in params.split(";"):
            if p.startswith("TZID=") and ZoneInfo:
                try: tz = ZoneInfo(p[5:])
                except Exception: pass
    try:
        return datetime.datetime.strptime(v, "%Y%m%dT%H%M%S").replace(tzinfo=tz), False
    except Exception:
        return None, None

now = datetime.datetime.now(datetime.timezone.utc)
evs, cur = [], None
for ln in lines:
    if ln == "BEGIN:VEVENT":
        cur = {}
    elif ln == "END:VEVENT":
        if cur and cur.get("start") and cur["start"][0] and cur["start"][0] >= now - datetime.timedelta(hours=12):
            d, allday = cur["start"]
            evs.append((d, allday, cur.get("summary", "(no title)")))
        cur = None
    elif cur is not None and ":" in ln:
        head, val = ln.split(":", 1)
        name = head.split(";", 1)[0]
        params = head[len(name):]
        if name == "DTSTART":
            cur["start"] = parse_dt(val, params)
        elif name == "SUMMARY":
            cur["summary"] = val.replace("\\,", ",").replace("\\n", " ").strip()

evs.sort(key=lambda e: e[0])
if not evs:
    print("nothing upcoming")
for d, allday, summ in evs[:5]:
    local = d.astimezone()
    when = local.strftime("%b %d") if allday else local.strftime("%b %d · %H:%M")
    print(f"{when}  —  {summ}")

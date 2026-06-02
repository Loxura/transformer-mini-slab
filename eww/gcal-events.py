#!/usr/bin/env python3
# Upcoming events for the eww Dash, from a Google Calendar *secret iCal URL*.
# The URL is read from ~/.config/eww/gcal-url (kept private — NOT in the repo).
# Add/edit events in the Google Calendar app; they appear here on the next poll.
import datetime, os, sys, urllib.request

URLFILE = os.path.expanduser("~/.config/eww/gcal-url")
try:
    url = open(URLFILE).read().strip()
except FileNotFoundError:
    print("add your Google Calendar secret iCal URL to ~/.config/eww/gcal-url"); sys.exit()
if not url:
    print("add your Google Calendar secret iCal URL to ~/.config/eww/gcal-url"); sys.exit()

try:
    from icalendar import Calendar
except ImportError:
    print("run: sudo apt install -y python3-icalendar"); sys.exit()

try:
    data = urllib.request.urlopen(url, timeout=15).read()
except Exception:
    print("calendar unavailable"); sys.exit()

now = datetime.datetime.now(datetime.timezone.utc)
evs = []
for c in Calendar.from_ical(data).walk("VEVENT"):
    d = c.get("dtstart")
    if not d:
        continue
    dt = d.dt
    if isinstance(dt, datetime.datetime):
        dtc = dt if dt.tzinfo else dt.replace(tzinfo=datetime.timezone.utc); allday = False
    else:  # date-only (all-day)
        dtc = datetime.datetime(dt.year, dt.month, dt.day, tzinfo=datetime.timezone.utc); allday = True
    if dtc >= now - datetime.timedelta(hours=12):
        evs.append((dtc, allday, str(c.get("summary", "(no title)"))))

evs.sort(key=lambda e: e[0])
if not evs:
    print("nothing upcoming")
for dtc, allday, summ in evs[:5]:
    local = dtc.astimezone()
    when = local.strftime("%b %d") if allday else local.strftime("%b %d · %H:%M")
    print(f"{when}  —  {summ}")

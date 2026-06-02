# music-card — the Now Playing panel

A touch "now-playing card" for the deck: big album art, large skip/play buttons, and a
background/accent palette pulled **live from the current album cover** (2010s-Spotify style).
This is the deliberate colour-adaptive exception to the slab's e-ink aesthetic
(see [`../docs/deck.md`](../docs/deck.md)).

Self-contained so it never collides with the Dash ricing: it runs in its **own eww config**
(`eww -c ~/.config/eww-music`, separate daemon and window names).

## Pieces
- `bin/np-now` — emits one JSON line/sec for eww `deflisten`: track, art path, and a palette
  (`bg`, `accent`, `accent2`, `text`, `muted`) derived from the cover. `--once` for testing.
- `bin/np-ctl` — touch controls: `toggle|next|prev|seek <pos>|vol <amt>`. Transport → mpd;
  volume → wpctl (mpd has no mixer).
- `eww/` — the eww card (windows, widgets, SCSS) *(coming next)*.

## How art + colour resolve (cached per album in `~/.cache/music-card/art/`)
1. local `cover.*`/`folder.*` next to the tracks (Lidarr writes one per album), else
2. embedded picture (extracted with ffmpeg), else
3. Cover Art Archive via the `MUSICBRAINZ_ALBUMID` tag.

Then ffmpeg downscales the cover to 16×16 and `np-now` derives the palette from those pixels.

## Requirements (all already on the deck)
python3 stdlib, `ffmpeg`/`ffprobe`, `mpc`, `wpctl`. No Pillow/pip/curl.

## Deploy
Synced to the deck at `~/.config/eww-music/` (scripts in `bin/`). mpd runs on `127.0.0.1:6600`.

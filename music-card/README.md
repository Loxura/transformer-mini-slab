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
- `eww/` — the eww card (`eww.yuck` window/widgets, `eww.scss`). Runs as its own daemon:
  `eww -c ~/.config/eww-music`. The `music` window is a fullscreen layer-shell overlay.
- `bin/np-music-watch` + `systemd/eww-music.service` — a sample sway-event watcher that
  showed the card only on `2:Music`. **Disabled** (see handoff note below).
- `bin/deploy-card` — rsync to the deck and inject the Font Awesome glyphs.

## How art + colour resolve (cached per album in `~/.cache/music-card/art/`)
1. local `cover.*`/`folder.*` next to the tracks (Lidarr writes one per album), else
2. embedded picture (extracted with ffmpeg), else
3. Cover Art Archive via the `MUSICBRAINZ_ALBUMID` tag.

Then ffmpeg downscales the cover to 16×16 and `np-now` derives the palette from those pixels.

## Requirements (all already on the deck)
python3 stdlib, `ffmpeg`/`ffprobe`, `mpc`, `wpctl`. No Pillow/pip/curl.

## Deploy
`bin/deploy-card` rsyncs to the deck `~/.config/eww-music/` and injects the FA glyphs.
mpd runs on `127.0.0.1:6600`.

## Integration handoff (→ ricing agent)
The **engine and card render correctly** (cover-derived palette, art, transport buttons).
What's left is *when/how the card shows* on the swipe deck — that lives in the swipe/workspace
model the ricing agent owns, so it's yours to wire. Interface:

- **Show:** `eww -c ~/.config/eww-music open music`   **Hide:** `… close music`
- The card is a fullscreen `:stacking "overlay"` layer surface (eww can't make a normal
  per-workspace window on Wayland), so *something* must open it on `2:Music` and close it
  elsewhere. Gate it however fits the deck — e.g. from `deck-swipe`, or replace the
  `exec foot -a music ncmpcpp` line in `sway/config` with the card.

**Lessons from my attempt (`np-music-watch` + the user service — left DISABLED):**
- It broke swiping: the overlay got **stuck open over every workspace** (a watcher event-parse
  bug + orphaned watcher copies never closed it). Ensure **exactly one** watcher and that it
  reliably closes the window when leaving Music.
- The window is `:focusable true` (grabs keyboard); set **`:focusable false`** unless you need
  key input — touch on the buttons works without it.
- `bin/np-ctl volget`/`np-now` are independent of all this; reuse freely.

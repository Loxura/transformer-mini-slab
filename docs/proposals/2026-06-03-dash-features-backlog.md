# Dash features backlog

**Date:** 2026-06-03
**Status:** Ideation — discussion captured, nothing committed to ship.
**Scope:** The main **Dash** (ws1) — today a read-only board (clock, calendar/events,
market ticker, topbar). Everything below respects the hardware (2016 ASUS T102HA,
Cherry Trail Atom) and the documented touch constraints (no touch-scroll on the
rotated layer-shell surface — paginate; `:active` not `:hover`; FA v4 glyphs only;
never interpolate library strings into single-quoted `onclick`).

This came out of a 4-lens brainstorm (music-core / ambient-info / interaction /
visual-identity). The headline finding: **all four lenses independently concluded
the Dash should gain music presence and control** — it's currently dead board space.

---

## Decisions made in this session

- **Clock direction: brutalist analog re-skin** (not a digital slab). Keep the dial,
  restamp it: square/rectangular ink hands (no rounded caps), hard thick ring, flat
  tick blocks, one `cover.glow` accent hand. Optional cheap delight: box-shadow
  offset steps with the cava `level` in 2–3 *hard* jumps (no tween). The current
  `analog-clock.sh` is still on the leftover Tokyo-night palette (`#1a1b26` /
  `#7aa2f7`) — that's the off-brand leak to fix.
- **First build: not yet.** Stay in ideation; this doc is the backlog.

---

## Consensus (3–4 of 4 lenses agreed)

1. **Now-playing + transport on the Dash.** Unanimous. Pausing/skipping today forces a
   swipe round-trip to ws2. Near-zero cost: `np_title/np_artist/state/level/cover` are
   global polls already running; just rehome them. **Effort S.**
2. **Re-skin the analog clock** (decided above).
3. **Surface existing-but-unused signals:** `new-arrivals.sh` emits JSON nothing
   consumes; the cava `level` signal and `cover-palette` run on ws2, unused on ws1.
4. **Reuse the pagination machinery, never scroll** — clone `album-grid.sh`'s
   cached-list + page-state pattern for any new list.
5. **Quoting safety:** route taps through a `music-ctl` verb taking `"$1"`; never
   interpolate `np_title` / file paths into a single-quoted `onclick`.

---

## Backlog (prioritised)

### MUST
- **Dash music control strip** — now-playing (palette-tinted, mini 6-seg VU reusing
  the `level` deflisten) + prev/toggle/next + a persistent **tappable mode rail**
  (Dash/Music/Video, active state from the `ws` deflisten) as swipe insurance against
  lisgd misfires. One cohesive bottom strip, not scattered widgets. *eww.yuck +
  eww.scss only, reuses existing scripts/vars.* **S.**
- **Brutalist clock re-skin** (decided). `analog-clock.sh` SVG body + optional
  `.clock-card` beat-step in `eww.yuck`. **S.**
- **System vitals strip** — battery/charge, thermal (Atom *throttles* — this matters),
  disk + music-SD usage, loadavg, from local sysfs/`df`/`/proc`. New `sys-vitals.sh`
  + one 30s `defpoll` + one widget; cells flip to accent over threshold. **S.**
- **Ambient dim schedule + pixel-drift** — the always-on burn-in safety valve every
  flat-colour-block feature depends on. Night backlight drop via `brightnessctl`/sysfs
  (systemd-timer or sway idle, not eww) + a ~10min `drift` defvar nudging Dash padding
  a few px. Both essentially free (state flips, no animation). **S.**

### SHOULD
- **Live queue panel** — tap UP NEXT → paginated next-~8 tracks, tap to jump
  (`mpc play <pos>`, numeric only). Near-mechanical clone of `album-grid.sh`. **M.**
- **Seek/progress bar** (music card) — chunky segmented bar from `mpc status`
  `%elapsed%/%totaltime%`, ~10 tap-to-seek blocks (`mpc seek N%`) — discrete taps
  dodge the broken drag-scrub. Biggest now-playing gap. **S–M.**
- **Repeat / single / consume toggles** (music card) — core mpd controls currently
  absent; text labels dodge the missing FA v4 repeat/single glyphs. Shares the seek
  status poll. **S.**
- **Pager edge-tap zones** — full-height invisible L/R eventboxes on paginated lists
  calling `gridpage prev|next`, so paging isn't gated on the small centred buttons.
  Must sit below tiles in stacking order and below the header band. **M.**
- **Weather as a stamped glyph block** — promote weather from buried topbar text to a
  bordered block with an FA v4 condition glyph + hi/lo. Reuses the existing 1800s
  `wttr.in` poll (keep that cadence; map condition word → glyph yourself, don't emit
  Unicode into a FA-family label). **S–M.**
- **Markets ticker as green/red signage block** — full-slab colour flip on direction
  (not a tint), hazard arrow. `stock-ticker.sh` emits a sign token. **S.**
- **Letter jump-strip on album grid** — A–Z bucket strip jumping `grid_page`, so a big
  library isn't 30 pager taps deep. Index math over the cached `albums.tsv`. **S–M.**

### COULD
- **Recent-played rail** — 4 cached cover thumbs of just-finished tracks, tap to
  replay (by numeric history index, not path). Needs a small append-on-change history
  hook. **M.**
- **Dash quick-launch tiles** — Shuffle All / Favorites one-tap from home
  (`music-ctl shuffleall|playfav`, already implemented, static onclicks). Pair with the
  control strip into one music zone. **S.**
- **New Arrivals shelf** — revive the unused `new-arrivals.sh`; paginated tiles, tap to
  add via a `music-ctl addpath "$1"` wrapper. **M.**
- **Genre "MIX" button** (music card) — `mpc findadd genre` for local discovery beyond
  shuffle-artist; degrade to artist if the genre tag is empty. Tag-quality dependent. **S.**
- **Home gesture + swipe tuning** — a distinct multi-finger/long swipe-down → snap to
  Dash; re-tune lisgd `-t`/`-r`. Empirical, needs the physical device. **S.**
- **Mechanical mode-flip feedback** — a 1-frame stamped destination label on ws change.
  GPU-risky on Atom — prototype in the `~/deck-sandbox` WSL replica; ship the
  static-sticker fallback if any transition stutters. **M.**

---

## Open questions / tensions for next time

- **Dash real estate.** Four lenses each want a strip (transport, vitals, now-playing
  spine, quick-launch, recent). More than fits a 3-card board — consolidate into one
  music control zone + one status zone rather than many widgets.
- **Confirm the `level` deflisten (cava) stays alive while ws1 is focused** — the
  control strip's mini-VU, the clock beat-step, and the markets/identity work all ride
  that signal onto the home screen. Untested that cava isn't gated to ws2.
- **lisgd multi-finger reliability** on the ELAN digitizer is unverified — single
  contact is clean, multitouch (for the home gesture) is not yet tested.

---

## Files most touched by this backlog

- `eww/eww.yuck` — dash widgets/polls (~18–42), deck-root (~215–218), VU (~173–180),
  album-grid pager (~112–117)
- `eww/eww.scss` — dash rules (~77–101), VU (~130–132), sticker mixin (~65–73)
- `eww/music-ctl.sh` — transport/shuffleall/playfav exist; add seek/repeat/queue/etc.
- `eww/album-grid.sh` — pagination template + `gridpage`/`trackpage` commands
- `eww/analog-clock.sh` — the clock SVG to re-skin
- `eww/new-arrivals.sh`, `eww/stock-ticker.sh`, `eww/cover-palette.sh`,
  `eww/audio-level.sh` + `level.conf` — existing sources to surface
- `docs/proposals/2026-06-03-neobrutalist-redesign.md` — P6 covers Dash *structure*;
  this backlog is Dash *identity + behaviour*, complementary.

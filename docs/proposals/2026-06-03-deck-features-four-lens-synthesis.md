# Deck Features — Four-Lens Brainstorm Synthesis

**Date:** 2026-06-03
**Method:** Four parallel `ux-proposer` agents, each given a distinct lens (daily-driver, music experience, home hub, contrarian/polish). This doc merges their backlogs into one ranked plan and records where they independently converged — convergence is the strongest signal.

Companion to `2026-06-03-dash-features-backlog.md` (this sharpens and re-ranks it) and `2026-06-03-cooking-tab-plan.md`.

---

## TL;DR — suggested first sprint

1. **Fix the apostrophe bug** — foundation, cheap, unblocks all safe taps.
2. **Live Queue panel** — the unanimous #1 feature.
3. **Poll-storm → `mpd idleloop` + optimistic toggle** — makes the whole deck feel faster.

Then pick an identity direction: **Arrivals/INCOMING ticker** (lean music-deck) or **Kitchen Timers** (lean home-hub).

Prototype each in `~/deck-sandbox` before touching the tablet, per the deploy model.

---

## Where the agents converged (highest confidence)

### ★ Live Queue panel — flagged #1 by three of four agents
`UP NEXT` shows exactly one track (`eww.yuck:95`) and there's no way to see or jump the queue. Skipping forward N tracks = N blind taps.

- **Build:** clone `album-grid.sh`'s overlay + pagination machinery into `queue.sh`. Data: `mpc -f '%position%\t%artist% - %title%' playlist`. Jump = `mpc -q play <pos>`, remove = `mpc -q del <pos>`, bump = `mpc -q move`. Wrap the UP NEXT row in an eventbox → `queue.sh open`. Highlight the current row.
- **Quoting-safe by construction:** dispatch every row action by **integer position**, never by interpolating the track string.
- **Effort:** M. Reuses proven scaffolding. **Risk:** paginate hard (queues can be 1000+ tracks); `mpc move` can race the poll — let the next poll repaint.

### ★ The apostrophe bug is STILL LIVE — not just a memory note
Flagged in memory + gotchas but **not fixed in code**. Every library-string interpolated into a single-quoted onclick is a live break:
- `eww.yuck:141` `album '${it.aa}' '${it.album}'`
- `eww.yuck:151` `playalbum '${gridaa}' '${gridtitle}'`
- `eww.yuck:156` `playtrack '${t.file}'`
- `eww.yuck:315` `cook pick ${it.id} '${it.name}'`

An album named `Sgt. Pepper's` or recipe `Mom's Stew` silently does nothing. The `cook pick` path is newest and least battle-tested → highest risk.

- **Fix (preferred):** pass **IDs/keys**, not names. `album-grid` already has an md5 `key`; `cook` has `it.id`. Re-resolve the human string server-side. `playtrack` should pass an index into the playlist, not raw `%file%`.
- **Fallback:** base64 the name in the yuck source, `base64 -d` in the script — no quote ever reaches the shell.
- **Effort:** S→M. Eliminates a whole bug class.

### ★ Revive `new-arrivals.sh` — written, wired to nothing
Two agents independently noticed the script exists but nothing consumes it. The conveyor (`sync-to-tablet.sh`) drops new music into `~/Music` every ~10 min; surfacing it is nearly free.

- **Tier A (S):** `(defpoll arrivals :interval "120s" ...)`, a row of 4 cover tiles on the Dash, tap → `mpc -q clear; mpc -q add "$path"; mpc -q play` via a quoting-safe verb (`music-ctl addpath "$1"`).
- **Note:** `new-arrivals.sh` emits no `art` field yet — add a `cover.*`/`folder.jpg` lookup or fall back to the note-glyph placeholder like `album-grid`.

---

## Foundations & polish (the contrarian's case — do alongside features)

### 1. Kill the poll storm — M, biggest hidden hardware tax
Six `:interval "1s"` polls (`np_title/artist/track`, `state`, `nextup`, `progress`) + cover@3s + vol@2s = **~8 process spawns/sec, 24/7**, even when Music isn't focused. `nextup` shells `mpc current` + `mpc playlist` + `sed` every second to compute something that only changes on track change.

- **Fix:** one `deflisten` backed by `mpc idleloop player mixer` — blocks until mpd actually changes, emits one JSON blob. Copy the long-lived-process hygiene from `audio-level.sh`. Keep `progress` on a poll but drop to 2s (the 10-segment bar can't resolve finer than 10%). Net: ~8 spawns/sec → ~1, most seconds zero.

### 2. Instant transport feedback — S
Tap play/pause → glyph lags up to 1s (the worst place for latency on a brutalist "instant flip" deck).

- **Fix:** optimistic update in `music-ctl toggle` — write the new state to the eww var *before* `mpc toggle`; the 1s poll reconciles. Same pattern already used for `immersive` (`music-ctl.sh:14-17`).

### 3. Honest failure states — M (keep minimal)
The deck has no failure language: mpd down → `0:00 / 0:00` + `--`; the known rt5645 silent-but-playing boot bug is **invisible**. A brutalist UI should be loud about being broken.

- **Fix:** an `mpd_up`/`audio_up` boolean + one swappable red `MPD OFFLINE` / `AUDIO ASLEEP — TAP TO WAKE` sticker (tap → `systemctl --user restart wireplumber`). Reuse `.badge` + `$c-red`. **Resist** growing this into a status dashboard.

### 4. Immersive view is a touch dead-end — S
`immersive-w` exits on *any* tap, so the whole cover is a hidden "exit" button with no affordance; `.imm-info` uses a soft gradient scrim — the lone soft-Spotify holdover.

- **Fix:** explicit stamped `X` close sticker top-right; shrink the tap-to-exit eventbox to the margins. Re-skin `.imm-info` to a hard black bar with `3px solid $ink` and uppercase `$paper` type.

### 5. Retire dead weight — S, pure subtraction
- `card-watch.sh` / `dash-watch.sh` — orphaned by the single-window `ws` model.
- `dash_vu` (`eww.yuck:53`) — a second VU array duplicating `vu_segs`.
- `.album*` / `.sec` SCSS (`eww.scss:186-189`) — rounded/translucent soft leftovers that contradict the brutalist tokens and tempt copy-paste.
- **Gotcha:** SCSS edits need a full eww restart (not reload) to recompile; keep files pure ASCII.

---

## Identity-direction features (pick one to lean into)

### Music-deck direction
- **INCOMING ticker (M) — signature differentiator.** Live Lidarr/slskd download progress on the deck. Keep ALL API access server-side: extend `sync-to-tablet.sh` to drop `~/.cache/deck/incoming.json`; the tablet only reads the file (no creds/VPN surface on the tablet). slskd `GET /api/v0/transfers/downloads`, Lidarr `GET /api/v1/queue` (`:8686`). Render as a stepped progress block reusing `.seek-seg` cells — no smooth animation.
- **VU: kill the soft glow (S).** Promote the stepped VU into a hard pulsing cover border. Change border *color* not *width* to avoid GTK relayout (the thing that got cava pulled). Quantize `audio-level` to ~5 bands.
- **History "RECENTLY SPUN" (S).** Append-on-track-change log, tap to requeue by **index**. Dedupe on `%file%` change, not every poll.
- **RADIO "KEEP GOING" (S).** Toggle that top-ups the queue from the current albumartist when it runs low (reuse `shuffleartist` logic). Append 5–10, never `clear`.
- **Favorites as a destination (S).** `playfav` exists but has no UI hook; add a `PLAY FAV` button + heart-state feedback (filled when current track is in `favorites.m3u`).

### Home-hub direction
- **Kitchen Timers (S/M) — completes Cook mode.** Full-screen overlay, preset tiles (5/10/20/30m) + running-timer stack, hard red flash + chime on zero. New `timer-ctl.sh` + 1s `deflisten`, reuse cook tile CSS. Audio on Cherry Trail needs the wireplumber route alive (the `audio-route-fix` quirk) — test the chime path. Route the user-typed label through `"$1"`, never inline it.
- **Shopping List mode (M) — closes the plan→shop→cook loop.** Tandoor `/api/shopping-list-entry/` (token already stored). Deck *builds* the list + shows "X to buy"; phone carries it. Pass entry **id** to onclicks (food names have apostrophes). Verify Tandoor 2.x schema shape first.
- **Today Agenda (S).** Promote `gcal-events.py` from buried grey text to a first-class TODAY block with a "next event" hero + relative stamp ("IN 2H · DENTIST") + a topbar chip. Change the script to emit JSON. Flag recurring-event base-date limitation.
- **Home-control toggle strip (M/L).** 4–6 brutalist toggles (lights/plug/scene) via HA REST or MQTT. Config-driven `home-targets.json`; show last *confirmed* state from a 30s poll, not optimistic. **Gated:** no HA/MQTT exists today — stand one up first; start with one device.
- **Idle/now-playing takeover (M).** After ~90s no-touch, swayidle routes to a fullscreen cover+clock+VU; first tap dismisses. Makes the always-on screen glanceable across the room + mitigates burn-in. State flip only, no animation. Confirm cava `level` survives the mode switch in the sandbox first.
- **Sticky-note dropbox (S).** Read-only Dash note card off a synced `~/notes.txt` (edit elsewhere, the detached keyboard makes on-deck typing miserable). Set `:show-truncated false` with `:wrap true`.

---

## Cross-cutting rules (apply to every feature above)

- **Never interpolate library strings into single-quoted onclicks** — dispatch by integer position / opaque id / base64, re-resolve server-side.
- **No eww-driven loops for time** — use external `sleep`/state files + a poll for display (timers, countdowns, sleep timer).
- **Keep acquisition-stack API access server-side** — the tablet reads pre-baked JSON only.
- **Long-lived processes copy `audio-level.sh`'s trap/anti-leak hygiene.**
- **SCSS edits = full eww restart, pure ASCII only.**
- **Prototype in `~/deck-sandbox` before the tablet.**

---

## Relevant files
- `eww/eww.yuck`, `eww/eww.scss` — widgets + brutalist tokens
- `eww/music-ctl.sh` — transport (add `addpath`, `radio`, optimistic `toggle`)
- `eww/album-grid.sh` — pagination template to clone for `queue.sh` / `history.sh`
- `eww/new-arrivals.sh` — written, unwired (revive for Arrivals)
- `eww/audio-level.sh` — the correct long-lived-process pattern
- `eww/np-progress.sh`, `eww/mpc-modes.sh` — poll consumers to fold into the idle listener
- `eww/cook.sh`, `eww/gcal-events.py` — home-hub extensions
- `eww/card-watch.sh`, `eww/dash-watch.sh` — orphans to delete
- server `sync-to-tablet.sh` — extend to drop `incoming.json`

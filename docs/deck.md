# Deck design - the swipe deck

Interaction model: **each mode is a fullscreen sway workspace; swipe left/right to
move between them.** No launcher, no chrome - just screens you flick through. Calm,
one-handed, and the lightest possible design (which happens to suit the Cherry Trail
GPU). The visual language is neo-brutalist - see [aesthetic.md](aesthetic.md).

> Implementation note: this was originally specced on Hyprland. It now runs on **sway +
> eww**, as a single always-mapped layer-shell window whose content follows the focused
> workspace. The interaction model below is current; the compositor table reflects sway.

## Modes (swipe order)
1. **Dash (home)** - eww widgets: clock, weather, now-playing mini, system, toggles.
2. **Music (Now Playing)** - the touch music card: big album art (tap = immersive
   full-screen), large transport buttons, "UP NEXT", and a palette pulled live from the
   cover. Album-grid browser + bluetooth panel reachable from the corner overlay.
3. **Video** - mpv (VA-API hardware decode for 1080p) on top.

```
 [ DASH ]  [ MUSIC ]  [ VIDEO ]
    1          2          3
    |<------- swipe ------->|
```

## Architecture (current)
One eww layer-shell window `deck` (`:stacking "bg"`, full-screen), **always mapped**.
Its content follows the focused sway workspace via a `ws` deflisten (`ws-name`):
`1:Dash`, `2:Music`, `3:Video`. This replaced an older per-window watcher that caused
occlusion / frozen repaints. Launched by `deck-launch` (sway `exec`).

## Controls
- **Touch:** swipe L/R between modes (lisgd -> `deck-swipe prev|next`); tap the cover
  for immersive; corner icons for album-grid / bluetooth / refresh. Design for big
  targets and `:active` feedback (hover is sticky on touch).
- **Keyboard (attached):** workspace keys jump to modes.
- **On-screen keyboard:** `wvkbd` for search/text when the keyboard's detached.

## Music card layout (`musiccard-w`, landscape 2-col, fills screen)
`card-root` is `orientation h`, `halign fill` + two `hexpand` halves:
- **Left (`mc-art`):** cover ~480px, wrapped in an eventbox (tap -> immersive).
- **Right (`mc-info`):** title -> artist -> transport (prev / play-pause / next) ->
  secondary row (shuffle, fav, vol-/vol%/vol+, mute) -> "UP NEXT".
- **Corner overlay (top-right):** album-grid, bluetooth, refresh.

Brutalist treatment: title in a heavy uppercase block, transport as big bordered
button cells, the cover-palette feeding **full blocks** (panel fills, stamped button
rows) with hard `ink` borders on top - not soft tints. Re-evaluate the breathing glow
as a hard pulsing border / blocky VU readout (see aesthetic.md motion budget).

## Other screens
- **Immersive (`immersive-w`):** tap cover -> full-screen cover (CSS `background-size:
  cover`), title/artist + minimal transport over a bottom block, tap anywhere to exit.
- **Album-grid (`album-grid`):** full-screen cover grid built from mpd tags -> track
  list -> play. (Filesystem layout is inconsistent, so it reads tags, not folders.)
- **Bluetooth (`bt-panel`):** full-screen pair/connect panel via `bt-ctl`.

## Shell components
| Piece | Tool |
|---|---|
| Compositor | sway (rotated landscape, touch workspace-swipe) |
| UI surface | eww (single layer-shell `deck` window) |
| Gestures | lisgd -> `deck-swipe` |
| On-screen keyboard | wvkbd |
| Music | mpd + cava (one bar -> level) |
| Audio | PipeWire / WirePlumber |
| Video | mpv + yt-dlp |
| Icons | FontAwesome v4 |

## Aesthetic = performance-gated
The look scales to whatever the Atom GPU can sustain - but brutalism is *cheap by
nature* (flat fills, hard borders, no blur), so the baseline already fits. Ship lean,
measure, then dial up. Stop where it starts to stutter; avoid full-screen shaders and
blur entirely on this Atom.

## Autostart on boot (appliance mode)
Power on -> straight into the deck, no login. Two pieces (no extra packages):

1. **Autologin minideck on tty1** - install the drop-in:
   ```sh
   sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
   sudo cp sway/getty-autologin.conf /etc/systemd/system/getty@tty1.service.d/autologin.conf
   sudo systemctl daemon-reload
   ```
2. **Launch sway on tty1 login** - append to `~/.profile`:
   ```sh
   if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
       exec sway
   fi
   ```

Boot -> agetty autologins minideck on tty1 -> `.profile` execs sway -> deck launches.
Need a plain shell? Switch VT with **Ctrl+Alt+F2**. To undo: delete the drop-in + the
`.profile` block.

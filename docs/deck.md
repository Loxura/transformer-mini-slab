# Deck design — the swipe deck

Interaction model: **each mode is a fullscreen Hyprland workspace; swipe left/right to move
between them.** No launcher, no chrome — just screens you flick through. Calm, one-handed,
and the lightest possible design (which happens to suit the Cherry Trail GPU).

## Modes (swipe order)
1. **Dash (home)** — eww widgets: clock, weather, now-playing mini, system, calendar, toggles.
2. **Now Playing** — the music view: cava heartbeat + rmpc track info.
3. **Video** — mpv + yt-dlp (VA-API hardware decode for 1080p).

```
 ●  ○  ○
 Dash  NowPlaying  Video
 └──── swipe <-> ───┘
```

## Controls
- **Touch:** swipe L/R between modes; swipe-up = on-screen keyboard / overview;
  edge-swipe = quick controls (volume / brightness / wifi).
- **Keyboard (attached):** `Alt+1/2/3` jump to modes.
- **On-screen keyboard:** `wvkbd` for search/text when the keyboard's detached.

## Shell components
| Piece | Tool |
|---|---|
| Compositor | Hyprland (rotated landscape, touch workspace-swipe) |
| Home widgets | eww |
| Workspace dots / clock | waybar (thin, top) |
| On-screen keyboard | wvkbd |
| Music | mpd + rmpc + cava |
| Video | mpv + yt-dlp |

Starter config: [`../themes/hyprland.conf`](../themes/hyprland.conf).

## Aesthetic = performance-gated
The look scales to whatever the Atom GPU can sustain. Ship lean, measure, then dial up.

**Probe (once apt works):**
```sh
glxinfo -B | grep -i 'opengl version'   # GLES/GL level (Hyprland needs GLES3+)
vainfo                                   # confirm VA-API HW video decode
glmark2                                  # GPU score = your effects budget
```

**Ladder — stop where it starts to stutter:**
1. Lean e-ink — animations off, blur off   ← always-safe baseline
2. subtle fade animations
3. `swww` wallpaper / soft transitions
4. blur
5. full-colour Video mode

Palette + motion rules: [aesthetic.md](aesthetic.md).

# Architecture

## Audio pipeline
Everything routes through **PipeWire**, so the EQ applies to *any* output (wired or Bluetooth),
and the visualiser taps the same stream:

```
  mpd ──▶ PipeWire ──▶ [ EQ + effects ] ──▶ output (3.5mm / USB-DAC / Bluetooth)
                  └──▶ monitor tap ──▶ cava (the heartbeat)
```

- **Player:** `mpd` (daemon) + a TUI client — `rmpc` (modern) or `ncmpcpp`.
  Bonus: mpd can be controlled from the main PC over the network.
- **EQ:** `EasyEffects` (GUI, has a built-in spectrum) *or* a PipeWire **filter-chain** config
  (static, near-zero overhead — better for the Atom). EQ is pre-output, so it works over BT too.
- **Visualiser:** `cava`, reading PipeWire's monitor (or mpd's FIFO), themed monochrome.

## Album-art → palette flow (optional flourish)
```
  track change ──▶ mpd hook ──▶ extract cover art ──▶ dominant colours
                                              │
                                              ▼
                       tint accent (+ cava gradient), regenerate theme bits
```
- Trigger: an mpd "on song change" hook (e.g. via `mpc idleloop` or a client event).
- Colour extraction: a small script (ImageMagick/Pillow, or a pywal-style tool).
- Apply: rewrite the accent colour used by the UI / cava and reload.

## Display / shell
- Lightweight: `sway`/`labwc` for a windowed setup, or **`cage`** for a single fullscreen
  now-playing kiosk.
- Portable rice configs (kitty/fish/zellij) carry over from existing dotfiles; here they finally
  run on a *real* compositor (unlike WSL).

## Component list
| Role | Choice | Notes |
|---|---|---|
| Audio server | PipeWire | EQ + monitor tap in one graph |
| Player | mpd | + rmpc / ncmpcpp |
| Visualiser | cava | the monochrome heartbeat |
| EQ | EasyEffects / filter-chain | filter-chain is lighter |
| Palette | mpd hook + extractor | optional album-art tint |
| Shell/WM | sway / labwc / cage | cage = pure kiosk |

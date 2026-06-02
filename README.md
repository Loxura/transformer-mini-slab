# transformer-mini-slab 🎵📖

Reviving a **2016 ASUS Transformer Mini (T102HA, Intel Cherry Trail)** as a calm,
always-on **music slab** running Debian Linux — styled **"e-ink with a heartbeat."**

> Old hardware, great battery, lovely screen. Give it one job and make it beautiful.

**Status:** 🚧 Planning / hardware revival. This repo currently documents the *design*;
configs land here as the build progresses (see [roadmap](docs/roadmap.md)).

---

## The vision

A low-power, plugged-in-always slab that does one thing well: **play music, beautifully.**
The aesthetic is mostly paper-and-ink minimalism — static, monochrome, no motion —
*except* a single living element: a **monochrome spectrum analyser that breathes with the
music.** Calm, but alive. The heartbeat.

Optional flourish: on every track change, pull the **dominant colours from the album art**
and tint the UI — so the (otherwise grayscale) slab subtly "wears" each record.

## Hardware target

| | |
|---|---|
| Device | ASUS Transformer Mini **T102HA** (detachable 2-in-1) |
| SoC | Intel Atom **x5-Z8350** (Cherry Trail) |
| RAM | 4 GB |
| Storage | 64/128 GB eMMC **+ microSD** (music library) |
| Display | 10.1" 1280×800 touch |

Cherry Trail Linux support is real but has a checklist — see [docs/hardware.md](docs/hardware.md).

## Planned stack

- **OS:** Debian (recent/backports kernel for Cherry Trail support)
- **Desktop:** lightweight — `sway`/`labwc`, or `cage` kiosk for a pure now-playing screen
- **Audio:** PipeWire → EQ → output (wired / Bluetooth)
- **Player:** `mpd` + a TUI client (`rmpc` / `ncmpcpp`)
- **Visualiser:** `cava` (monochrome, the "heartbeat")
- **EQ:** EasyEffects or a PipeWire filter-chain
- **Palette:** album-art colour extraction on track change
- **Look:** "e-ink with a heartbeat" — [docs/aesthetic.md](docs/aesthetic.md)

Architecture & data flow: [docs/architecture.md](docs/architecture.md).

## Repo layout

```
transformer-mini-slab/
├── README.md
├── docs/
│   ├── hardware.md       # Cherry Trail revival checklist (UEFI, wifi/BT, audio, touch)
│   ├── aesthetic.md      # the "e-ink with a heartbeat" design language
│   ├── architecture.md   # audio pipeline + visualiser + palette flow
│   └── roadmap.md        # phased build plan
├── themes/
│   ├── kitty-eink.conf   # paper/ink kitty colourscheme (starter)
│   └── cava.conf         # monochrome spectrum config (the heartbeat)
└── LICENSE
```

## License

MIT — see [LICENSE](LICENSE).

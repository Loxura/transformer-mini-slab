# Design language — "e-ink with a heartbeat"

The slab looks like paper and ink: static, monochrome, calm, text-first. **One** element
is allowed to move — the spectrum analyser — so the device feels alive without being busy.

## Principles
1. **Subtraction over decoration.** Empty space is the feature. No shadows, no blur, no gloss.
2. **Monochrome.** Paper background, ink foreground, a few grays. Colour is a guest, not a host.
3. **No motion** — except the heartbeat (the `cava` spectrum). Transitions are instant.
4. **Typography carries the design.** A calm serif or a clean mono; minimal icons.
5. **High contrast, flat chrome.** 1px borders, little/no rounding.

## Palette (paper / ink)
```
paper    #F4F1EA   warm paper background   (clinical alt: #FFFFFF)
ink      #1B1B1B   primary text
gray-1   #3A3A3A   strong
gray-2   #6E6E6E   secondary text
line     #B7B3A9   borders / dividers
accent   #45577A   desaturated ink-blue — used sparingly, once per screen
```

## The heartbeat
A `cava` spectrum rendered in a **paper→ink grayscale gradient** (see `themes/cava.conf`).
It's the only animated thing on screen. On a now-playing view it can sit under the track
title like a pulse line.

## Optional: album-art tint
On track change, extract the album cover's dominant colours and apply a *subtle* tint to the
accent (and optionally the heartbeat gradient). The slab stays grayscale-calm but quietly
"wears" each record. Keep it understated — this is e-ink, not a disco.

## Motion budget on Cherry Trail
The GPU is weak, but the device is always plugged in. `cava` is CPU-cheap and fine. Avoid a
full-screen GLSL grayscale shader (Hyprland-style) here — too heavy for this Atom; achieve the
monochrome look via **per-app theming** instead (palette above applied everywhere).

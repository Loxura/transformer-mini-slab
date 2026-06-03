# Design language - "neo-brutalist deck"

The slab is **raw, structural, and loud**. Honest boxes with hard borders, big
confident type, flat saturated color. Nothing is soft: no blur, no gloss, no gentle
fades. If something casts a shadow it's a hard offset block, never a blur. The screen
should read like a control surface stamped out of thick stock - unapologetic and
finger-sized.

> This supersedes the old "e-ink with a heartbeat" direction. That paper/ink,
> motion-minimal, monochrome language is **deprecated** - ignore it.

## Principles
1. **Structure is the decoration.** Visible boxes, panels, and labels. Components look
   like outlined cards and big stamped buttons. Let the grid show.
2. **Hard edges only.** 1-4px solid borders (usually near-black). Shadows are hard
   offsets (`4px 4px 0 #000`), never blurred. Little to no rounding.
3. **Loud, flat color.** Big blocks of saturated fill against stark black/white. Color
   can be pulled live from the album cover, but used as bold blocks - not subtle tint.
4. **Type carries the layout.** Oversized, heavy, tight. Mono or grotesque sans,
   often UPPERCASE. The text *is* the composition.
5. **Asymmetry over symmetry.** Deliberately blocky, slightly "unrefined" alignment.
   Off-grid is a feature, not a bug.
6. **Chunky touch targets.** Brutalist buttons are big rectangles - which also suits a
   finger-driven 10" tablet. Lean into it.
7. **Mechanical motion.** State flips are instant and hard. No easing-heavy fades.
   Motion, if any, is stepped/blocky (a pulsing border, a jumping VU readout), never a
   smooth glow.

## Palette
The chrome is black/white/gray with one or two loud accents. Per-screen accents may be
pulled from the current cover (see below), but the *structure* color stays constant so
the device always reads as the same machine.
```
bg        #FFFFFF   paper-white base (or #111111 inverted blocks)
ink       #111111   borders, heavy text, stamped fills
gray      #BDBDBD   secondary fills / disabled
accent-1  #FF4D00   loud orange     (use boldly, as a block)
accent-2  #2962FF   electric blue
accent-3  #FFE600   hazard yellow
```
Rule of thumb: a screen has **one dominant loud block**, everything else is
black-on-white structure. Don't rainbow it.

## Album-art color (the live accent)
On track change, `cover-palette` emits `{art, bg, accent, text, glow}` from the current
cover. In brutalism these feed **blocks**, not tints: e.g. a full-bleed `cover.bg`
panel behind the title, an `cover.accent` stamped button row, hard `ink` borders on
top. The slab quietly "wears" each record while staying structurally identical.

## Motion budget on Cherry Trail
The GPU is weak; the device is mains-powered 24/7. Cheap effects only - **no
full-screen shaders, no blur, no large continuous animation.** A stepped/blocky readout
is both on-aesthetic *and* cheap. The old soft "breathing glow" (one cava bar ->
box-shadow scale) is being re-evaluated: a **hard pulsing border** or a blocky VU bar
fits brutalism better than a soft halo - prefer that.

## Rendering constraints (eww 0.6 / GTK3)
The look has to survive eww's GTK3 CSS subset:
- Box-shadow renders - use it for hard offset shadows.
- No flexbox/grid CSS; lay out with eww boxes (`halign fill` + `hexpand`).
- Style `:active`, not `:hover` (hover is sticky on touch).
- **SCSS must be pure ASCII.** A single non-ASCII byte (em-dash, smart quotes) makes
  grass emit `@charset` and the whole stylesheet silently falls back to the default GTK
  theme. Keep all SCSS - and the copy in it - ASCII-only.
- Icons are FontAwesome v4; pick glyphs that exist there.

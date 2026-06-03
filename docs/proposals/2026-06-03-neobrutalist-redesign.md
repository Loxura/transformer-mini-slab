# Neo-brutalist redesign - first pass

Date: 2026-06-03
Scope: player UI only (music card hero + reusable brutalist vocabulary, then dash /
album-grid / bluetooth). Ignores `server/`. No live code edited - this is a spec.

Ground truth read before writing: `shots/11-deck-overlay.png`,
`shots/20-dash.png`, `shots/21-album-grid.png`. The current UI is soft-Spotify:
circular buttons (`.ico` `border-radius: 40px`), rounded glowing cover frame
(`.cover-wrap` blurred box-shadow), 18px-rounded cards, hairline `1px #292e42`
chrome, centered symmetric layout. The brief (`docs/aesthetic.md`,`docs/deck.md`)
asks for the opposite: hard borders, hard offset block-shadows, flat saturated
blocks, oversized uppercase type, exposed grid, chunky rectangles.

Everything below survives the eww 0.6 / GTK3 CSS subset, is ASCII-only, styles
`:active` not `:hover`, uses FA v4 glyphs, and is cheap on Cherry Trail (flat fills +
hard borders + one hard offset shadow; no blur, no large continuous animation).

Palette ground truth (`cover-palette`): emits `{art,bg,accent,text,glow}` where `bg`
is a dark cover-tint, `accent` is the most-saturated cover pixel, `text` is fixed
`#e6e6ee`, `glow` is `accent` brightened. `level` (`audio-level`) is 0-100 loudness.

---

## RANKED BACKLOG (one line)

1. P1 Brutalist token layer (borders/shadow/no-radius reset) -> 2. P2 Music-card
button cells (kill circles, stamped rectangles) -> 3. P3 Cover frame: hard `ink`
border + hard offset block-shadow (kill blurred glow) -> 4. P4 Title/artist
label-block (oversized uppercase, accent fill) -> 5. F1 Blocky stepped VU strip
(replace breathing glow) -> 6. P5 Album-grid as stamped tiles -> 7. P6 Dash panels
as labeled cards -> 8. P7 Bluetooth rows as bordered cells -> 9. F2 "NOW / NEXT"
split-flap stack -> 10. F3 Hazard-stripe state bar (paused/scanning).

POLISH = P1-P7 (restyle what exists, mostly `eww.scss` only). FEATURES = F1-F3 (new
widgets/markup, touch `eww.yuck`).

---

# POLISH

## P1 - Brutalist token layer
Pitch: one block of SCSS variables + a hard reset so every later proposal is a
two-line change, not a rewrite.

Problem / opportunity: `eww.scss` has no shared vocabulary. Borders are ad-hoc
(`1px #292e42` on `.card`, none on `.ico`), radius is sprinkled (`40px`, `18px`,
`16px`, `12px`, `10px`), fills are one-off `rgba(255,255,255,0.0x)`. There is nothing
to make "brutalist" mean the same thing twice. Defining tokens first is what turns
this from a paint job into a system.

Proposal: add a token header at the top of `eww.scss` (after the `* { all: unset }`
block). Pure ASCII, no glyphs.

```scss
/* ===== brutalist tokens ===== */
$ink:    #111111;   /* borders, heavy text, stamped fills */
$paper:  #f2f2ec;   /* light structural fill */
$gray:   #bdbdbd;
$bd:     3px;       /* standard hard border */
$bd-fat: 4px;       /* hero border (cover, title block) */
$shadow:  4px 4px 0 #{$ink};   /* hard offset block-shadow, never blurred */
$shadow-lg: 6px 6px 0 #{$ink};

/* structural mixins */
@mixin cell {              /* the button cell / panel base */
  border: $bd solid $ink;
  border-radius: 0;
  box-shadow: $shadow;
  background-color: $paper;
}
@mixin cell-press {        /* brutalist press: shadow collapses, block "drops" */
  box-shadow: 0 0 0 $ink;
  margin: 4px -4px -4px 4px;   /* nudge into the vacated shadow space */
}
```

The press feel - shadow snaps to zero and the block shifts into the gap - is the
canonical neo-brutalist tactile flip, and it is free (no blur, no animation; GTK
applies it instantly on `:active`).

Why it fits: aesthetic - radius 0 + hard 3px ink border + 4px offset shadow IS the
language. Touch - `:active` press is unmistakable feedback on a finger UI. Hardware -
flat fill + 1 solid border + 1 non-blurred shadow is about the cheapest thing GTK can
draw; cheaper than the current blurred `box-shadow` glow.

Effort: S. Files: `eww/eww.scss` (additive header only).

Risk/gotchas: keep it ASCII (no smart quotes in comments). `border-radius: 0` must be
set explicitly everywhere we currently round, or GTK theme defaults can creep back -
P2/P3/P5 each restate it. The `cell-press` negative margins assume the cell has 4px of
breathing room around it; verify per-widget so adjacent cells do not overlap on press.

---

## P2 - Music-card button cells (kill the circles)
Pitch: transport and secondary controls become big stamped rectangles with hard
borders, not floating circles.

Problem / opportunity: `eww.scss:71-79` `.ico` is `border-radius: 40px` (a circle) on
a faint `rgba(255,255,255,0.08)` fill with no border - the single most "soft-Spotify"
element in the shot (`shots/11`, the round play/pause cluster). It reads as a phone
app, not a control surface.

Proposal: rectangular cells, hard ink border, FA glyph centered. Play/pause is the one
loud block (fills `cover.accent` via the inline `:style` already on the card root - or
add an `.ico.big` accent rule). ASCII mockup of the transport row:

```
+----------+   +==============+   +----------+
|    |<<    |  ||     ||      |  |    >>|    |     <- prev / PLAY(accent block) / next
+----------+   +==============+   +----------+
   3px ink        4px ink            3px ink
   +shadow      +accent fill        +shadow
```

```scss
.ico {
  @include cell;
  padding: 18px 24px;     /* chunky finger target, was 13px 16px */
  margin: 0 7px;
}
.ico:active { @include cell-press; }
.ico.big { padding: 22px 30px; border-width: $bd-fat; }
.ico.big .g { font-size: 30px; }
.ico.sm  { padding: 11px 13px; margin: 0; box-shadow: $shadow; }  /* corner icons */
.g { font-family: "FontAwesome"; font-size: 24px; color: $ink; }
/* play/pause as the loud block: accent fill comes from the cover.
   set inline on the button in yuck: :style "background-color: ${cover.accent};" */
.ico.fav .g { color: #f7768e; }   /* keep fav loud-pink, it reads as a stamp */
```

In `eww.yuck:166` give the big button an inline accent fill so it is the dominant
block per the "one loud block per screen" rule:
`(button :class "ico big" :style "background-color: ${cover.accent};" ...)`.

Why it fits: aesthetic - rectangles + hard borders + one accent block = textbook
brutalism; type/glyph sits in a labeled cell. Touch - 18-24px padding makes targets
larger than the current circles, easier one-handed. Hardware - removes the soft fill,
adds only solid borders + offset shadow (cheap).

Effort: S. Files: `eww/eww.scss` (`.ico*`,`.g`), `eww/eww.yuck:166` (one inline style).

Risk/gotchas: glyph color flips to `$ink` (dark) so cells must stay on the `$paper`
fill - if you instead fill cells with `cover.bg` (dark), set `.g` color to `cover.text`
inline. The accent play button needs a dark glyph only if `cover.accent` is light;
since accent is "most saturated pixel" it can be either - safest is glyph `#111` with a
3px ink border so it reads on any accent. Do not interpolate any library string into
these onclicks (they are static `music-ctl` verbs - safe).

---

## P3 - Cover frame: hard border + hard offset block-shadow
Pitch: replace the soft breathing halo with a thick ink border and a hard 6px offset
block-shadow - the cover looks stamped onto the panel.

Problem / opportunity: `eww.scss:65-67` + `eww.yuck:157-160`. `.cover` is
`border-radius: 18px`; `.cover-wrap` carries a blurred, animated `box-shadow` scaled by
`level` (`0 0 NNpx ...glow`). In `shots/11` it is a yellow blurred glow with rounded
corners - the antithesis of the brief, and a continuous animated blur is the single
most expensive effect on the Atom.

Proposal: square the cover, wrap it in a 4px ink border, and give it a hard offset
block-shadow tinted with `cover.accent` (no blur radius). The "heartbeat" moves to a
discrete VU strip (see F1) instead of pulsing this shadow.

```
   +================+
   |                |  4px ink border
   |   ALBUM ART    |  radius 0
   |                |
   +================+
       \\           hard offset block-shadow
        \\          6-8px, NO blur, tinted cover.accent
```

```scss
.cover { border-radius: 0; }
.cover-wrap {
  border: $bd-fat solid $ink;
  border-radius: 0;
  /* hard offset, accent-tinted, NO blur radius. set the color inline from cover: */
  /* yuck :style "box-shadow: 8px 8px 0 ${cover.accent};" */
}
```

Remove the `level`-driven inline box-shadow on `eww.yuck:158`; replace with a static
hard offset:
`:style "box-shadow: 8px 8px 0 ${cover.accent};"`.

Why it fits: aesthetic - hard offset block-shadow is the named brutalist move
(`aesthetic.md` principle 2). Touch - cover stays the same tap target (immersive).
Hardware - kills the continuous animated blur entirely; a static non-blurred offset is
near-free. This is the biggest single perf win in the redesign.

Effort: S. Files: `eww/eww.scss:65-67`, `eww/eww.yuck:158` (drop `level` interp).

Risk/gotchas: `level` is still consumed by F1; do not delete the `level` deflisten.
GTK box-shadow with 0 blur and a large offset renders fine but is clipped by the
parent - `mc-art` has `padding: 80px` (`eww.scss:63`) so there is room; keep >= 8px
padding on the shadow side. Square corners mean cover art with its own rounding will
look doubly-framed - acceptable and on-brand.

---

## P4 - Title / artist label-block
Pitch: now-playing becomes an oversized uppercase title in a hard-bordered block with
an accent underline - type IS the layout.

Problem / opportunity: `eww.scss:68-69` `.np-title` 32px bold centered, `.np-artist`
19px centered, both floating with no structure (`shots/11`: "Track 2 / Mono Unit"
hangs in space). It is legible but timid - no block, no case, no weight statement.

Proposal: left-align (asymmetry over centered symmetry), uppercase, heavier, wrapped in
a label-block with a thick bottom border in `cover.accent`.

```
+--------------------------------+
| TRACK 2                        |   <- 34px uppercase, ink, tight
| ============================== |   <- 4px accent underline (cover.accent)
| MONO UNIT                      |   <- 18px uppercase, gray
+--------------------------------+
```

```scss
.np-title {
  font-size: 36px; font-weight: bold;
  /* uppercase: GTK CSS has no text-transform in eww's subset.
     UPPERCASE the source text in yuck instead (see note). */
  color: $ink;
  letter-spacing: -1px;
}
.np-artist { font-size: 18px; color: #555; margin-top: 2px; letter-spacing: 1px; }
.np-block {                      /* wrap title+artist in a box with this class */
  border-bottom: $bd-fat solid $ink;   /* accent set inline: cover.accent */
  padding-bottom: 10px; margin-bottom: 22px;
}
```

GTK3 CSS in eww has no `text-transform`, so uppercase must come from the data. Either
uppercase in the poll (`mpc ... | tr a-z A-Z`) or wrap the existing label expr:
`:text {arg_upper}` is not available - simplest is to add `tr` in the `np_title` /
`np_artist` defpolls in `eww.yuck:45-46`. Keep it ASCII.

Why it fits: aesthetic - oversized uppercase tight type, left-aligned, accent rule =
the type-as-layout principle. Touch - non-interactive, pure structure. Hardware - text +
one border, free.

Effort: S-M. Files: `eww/eww.scss:68-69`, `eww/eww.yuck:45-46` (uppercase via `tr`),
`eww.yuck:161-163` (wrap title+artist in a `.np-block` box, set accent inline, switch
`xalign` to 0).

Risk/gotchas: `tr a-z A-Z` is ASCII-only - non-ASCII track titles pass through
unchanged (fine). If `cover.text` is used for the title instead of `$ink`, it is fixed
`#e6e6ee` (light) and will vanish on a `$paper` card - on this screen the card-root bg
is `cover.bg` (dark), so on dark use `cover.text`; if you put the title in a `$paper`
block use `$ink`. Pick one substrate. The `letter-spacing` is supported; `text-align`
is not - use `xalign` on the eww label.

---

## P5 - Album-grid as stamped tiles
Pitch: the cover grid gets hard ink borders + offset shadows and a real header block,
so it matches the deck instead of being faint rounded cards on near-black.

Problem / opportunity: `eww.scss:103-109`. `.tile` is `border-radius: 16px` on
`rgba(255,255,255,0.04)` (almost invisible), `.tile-art` rounded 12px. In `shots/21`
the loud sample covers float on faint rounded panels - the covers are brutalist, the
chrome is not.

Proposal: square tiles, 3px ink border, hard offset shadow, uppercase name block; the
back/close gets the cell treatment; header is a label-block.

```
[X] ALBUMS                                      <- header: close cell + uppercase title

+==========+  +==========+  +==========+
|  COVER   |  |  COVER   |  |  COVER   |        3px ink border, radius 0,
+==========+  +==========+  +==========+        4px offset shadow per tile
 OFF GRID      RAW POWER     HARD EDGE           uppercase name (ink)
 asymmetry     brutalist     mono unit           artist (gray, lowercase)
```

```scss
.tile { @include cell; padding: 0; margin: 10px; }
.tile:active { @include cell-press; }
.tile-art, .tile-ph { border-radius: 0; }
.tile-ph { min-width: 210px; min-height: 210px; }
.tile-name   { color: $ink; font-size: 17px; font-weight: bold; margin-top: 10px; }
.tile-artist { color: #777; font-size: 14px; }
.grid-title  { color: $ink; font-size: 26px; font-weight: bold; margin-left: 16px; }
.grid-root   { /* keep cover.bg inline, but cards now read on it */ }
```

Why it fits: aesthetic - tiles become labeled stamped cards, the exposed grid is the
decoration. Touch - same tile target, clearer `:active` press. Hardware - flat + border
+ offset shadow per tile; grid is paginated (no scroll) so tile count per frame is
bounded - cheap.

Effort: M. Files: `eww/eww.scss:97-109`. Optionally uppercase `.tile-name` via the
album-grid script output (it builds the JSON) - or leave mixed-case; brutalism tolerates
loud mixed case if heavy.

Risk/gotchas: `.tile` press uses `cell-press` negative margins; tiles sit in
`.grid-row` h-boxes with `margin: 10px` - confirm the 4px nudge does not clip the
neighbor. The tile `onclick` interpolates `'${it.aa}' '${it.album}'` (`eww.yuck:88`) -
this is the single-quote trap: an album or artist named with a literal apostrophe
breaks the shell. Flag for the album-grid script to emit shell-escaped values or switch
to a key-based dispatch (`album-grid album '${it.key}'`). Not introduced by this
proposal, but P5 is the moment to fix it.

---

## P6 - Dash panels as labeled cards
Pitch: dash cards get hard borders + offset shadows + a stamped header label, so home
reads as the same machine as music.

Problem / opportunity: `eww.scss:50` `.card` is `border-radius: 18px` + `1px #292e42`
hairline on `#1a1b26` - in `shots/20` the clock/calendar/markets panels are barely
distinguishable from the background. `.ticker-h`/`.events-h` headers are 13px faint
blue - timid.

Proposal: square cards, 3px ink border, offset shadow, and a real "tab" label-block on
each (a small filled ink rectangle with uppercase white text sitting on the top-left
border - the brutalist "labeled component").

```
+===============================+
|[MARKETS]                      |   <- filled ink tab, white uppercase
|                               |
|  GOLD    4436.75              |   <- big mono number
|         -1.2%                 |
+===============================+   3px ink border + 5px offset shadow
```

```scss
.card { border: $bd solid $ink; border-radius: 0; box-shadow: $shadow-lg;
        background-color: $paper; color: $ink; padding: 24px 28px; margin: 0 14px; }
.card-tab {                         /* add a label box with this class at top of each card */
  background-color: $ink; color: $paper;
  font-size: 13px; font-weight: bold; padding: 4px 10px;
  margin: -24px 0 16px -28px;       /* pull it onto the card's top-left corner */
}
.ticker { font-size: 30px; font-weight: bold; color: $ink; }   /* number stays loud */
.events-h, .ticker-h { /* replaced by .card-tab */ }
```

Whether dash goes paper-light or stays dark is a call: simplest is dark cards
(`background-color:#111; color:#e6e6ee; border:3px solid #000; box-shadow:5px 5px 0
#000`) so dash keeps its night look but gains hard structure. The tab + offset shadow
do the brutalist work either way.

Why it fits: aesthetic - labeled stamped panels, exposed structure, one loud number per
panel. Touch - dash is mostly non-interactive; bigger borders aid glanceability.
Hardware - borders + offset shadow, free; the analog clock image is unchanged.

Effort: M. Files: `eww/eww.scss:50-59`, `eww/eww.yuck:29-37` (add a `.card-tab` label
box at the top of each card). The calendar `.cal:selected` (`eww.scss:54`) should also
square: `border-radius: 0; background-color: <accent>`.

Risk/gotchas: the `.card-tab` negative margin must match the card padding exactly or it
drifts off the corner. If dash stays dark, the offset shadow color should be pure black
on `#16161e` so it reads. The clock card has different padding (`.clock-card`) - tab
margin needs a per-card override.

---

## P7 - Bluetooth rows as bordered cells
Pitch: bt device rows become hard-bordered cells; connected state is a loud accent
block, not a faint green tint.

Problem / opportunity: `eww.scss:112-113`,`93-94`. `.brow-row` is `border-radius: 12px`
faint fill; `.bt-on` is `rgba(158,206,106,0.16)` - a wash. Connected vs not is hard to
read at a glance.

Proposal: square cells with 3px ink border; connected = filled green block with ink
border (`#9ece6a` fill, ink text), the check glyph on the right.

```
+--------------------------------------------+
| (bt)  WH-1000XM4                    [paired]|   3px ink border, paper fill
+--------------------------------------------+
+============================================+
| (bt)  SOUNDCORE MOTION         [connected v]|   GREEN BLOCK, ink border (bt-on)
+============================================+
```

```scss
.brow-row { @include cell; padding: 16px 18px; margin: 6px 0; }
.brow-row:active { @include cell-press; }
.brow-label { color: $ink; font-size: 20px; }
.bt-on { background-color: #9ece6a; }      /* loud connected block */
.bt-on .brow-label, .bt-on .bt-state { color: $ink; }
.bt-state { font-size: 18px; }
.grid-title { color: $ink; }               /* "Bluetooth" header */
```

Why it fits: aesthetic - state communicated by a flat color block, not a tint. Touch -
big bordered rows are easy targets; `:active` press confirms the tap before the toggle
round-trips. Hardware - flat fills + borders, free.

Effort: S. Files: `eww/eww.scss:112-113,93-94,91`.

Risk/gotchas: `.brow-row` is shared by the album-grid track list (`eww.yuck:103`) and
play-all - this restyle hits both (good, consistent), but check the track rows still
read on `cover.bg`. The bt toggle onclick interpolates `'${d.mac}'` (`eww.yuck:121`) -
a MAC has no apostrophes, safe.

---

# FEATURES

## F1 - Blocky stepped VU strip (replaces the breathing glow)
Pitch: turn the one cava `level` value into a discrete 10-segment hazard-colored bar
under the cover - the "heartbeat" becomes a brutalist readout, not a soft halo.

Problem / opportunity: the breathing glow (P3) is being retired; `level` (0-100) is
still live and should drive something on-aesthetic. `aesthetic.md` motion budget
explicitly asks for "a blocky VU bar" over a soft glow.

Proposal: a fixed strip of 10 segment boxes; the first `round(level/10)` segments fill
`cover.accent`, the rest stay `$ink` outlines. Stepped (snaps between 10 states), so it
is cheap and reads as mechanical.

```
[##][##][##][##][##][  ][  ][  ][  ][  ]   level ~ 50
 filled = cover.accent      empty = ink outline
```

yuck (new widget, place under the cover in `mc-art` or under the title block):
```
(box :class "vu" :orientation "h" :space-evenly true :halign "fill"
  (for i in '[0,1,2,3,4,5,6,7,8,9]'
    (box :class "vu-seg"
      :style {(level / 10) > i
              ? "background-color: ${cover.accent};"
              : "background-color: transparent;"})))
```
```scss
.vu-seg { min-width: 0; min-height: 22px; margin: 0 2px;
          border: 2px solid $ink; border-radius: 0; }
```

`level` is a string from the deflisten; compare numerically with `(level + 0)` if eww
does not coerce: `{((level + 0) / 10) > i ? ...}`.

Why it fits: aesthetic - 10 hard blocks, stepped, flat fill = brutalist readout.
Hardware - 10 tiny boxes recolored ~10x/sec via inline style is far cheaper than an
animated blurred shadow; it snaps (no tween) which is both cheaper and on-aesthetic.
Touch - non-interactive.

Effort: M. Files: `eww/eww.yuck` (new `.vu` box in `musiccard-w`, ~line 160), removes
the `level` interp on `eww.yuck:158` (P3), `eww/eww.scss` (new `.vu*` rules).

Risk/gotchas: eww `for` over an inline JSON array is supported; if numeric coercion is
flaky, precompute in a defvar or use a `literal`. 10 inline-styled boxes re-rendered
each `level` frame is fine; do NOT go to 30+ segments. The strip width is `halign fill`
so it spans the column - keep `min-height` modest (~22px) so it does not crowd the
controls. This is the replacement for the deleted glow, so land it WITH P3.

## F2 - "NOW / NEXT" split-flap stack
Pitch: replace the single faint "UP NEXT" line with a two-row stacked block - a filled
NOW row and an outlined NEXT row - like a departures board.

Problem / opportunity: `eww.scss:85` `.nextup` is 12px `rgba(...,0.5)` centered - the
weakest text on the hero (`shots/11`, bottom). Up-next is a genuinely useful glance and
it is nearly invisible.

Proposal: two stacked label-blocks. NOW = filled `cover.accent` block, ink text, the
current title. NEXT = ink-outlined block, the queued track. Left-aligned, monospace.

```
+--------------------------------+
| NOW  | TRACK 2                 |   filled accent block, ink text
+--------------------------------+
| NEXT | MONO UNIT - TRACK 3     |   ink outline, paper fill
+--------------------------------+
```

```scss
.flap      { border: $bd solid $ink; border-radius: 0; margin: 4px 0; padding: 8px 12px; }
.flap-now  { /* accent inline: background-color: ${cover.accent}; */ color: $ink; }
.flap-next { background-color: transparent; color: $ink; }
.flap-tag  { font-weight: bold; font-size: 12px; margin-right: 12px; }
.flap-val  { font-size: 15px; }
```

Why it fits: aesthetic - stacked labeled blocks, one filled / one outlined = the
component vocabulary applied to data. Touch - could become tappable later (NEXT -> jump
in queue) but ship non-interactive first. Hardware - text + borders, free.

Effort: M. Files: `eww/eww.yuck:176` (replace `.nextup` with the two `.flap` rows),
`eww/eww.scss:85` (new `.flap*` rules). Reuses existing `np_title` + `nextup` polls.

Risk/gotchas: if you later make NEXT tappable, the onclick must not interpolate the
track string unescaped (single-quote trap) - dispatch by queue position instead. The
NOW row duplicates the title block (P4) - keep NOW as a compact echo, not a second big
title, or drop NOW and keep only the NEXT flap.

## F3 - Hazard-stripe state bar (paused / scanning / muted)
Pitch: a thin diagonal hazard-stripe bar that appears across the top only in a
non-default state (paused, muted, bt scanning) - instant, loud, mechanical status.

Problem / opportunity: state today is implicit (the play glyph flips to pause). On a
glanceable always-on deck there is no loud "this is PAUSED" signal. Brutalism loves a
hazard stripe.

Proposal: a full-width 12px bar, hidden by default, shown when `state == "paused"` (or
muted). Diagonal stripes via a repeating linear-gradient in `cover.accent` + ink.

```
/////////////////  PAUSED  /////////////////////   <- 12px hazard bar, only when paused
[ ... cover ... ]              [ ... info ... ]
```

```scss
.hazard {
  min-height: 14px;
  background-image: repeating-linear-gradient(45deg,
      #111 0px, #111 10px, #ffe600 10px, #ffe600 20px);
}
```
yuck: `(box :class "hazard" :visible {state == "paused"})` pinned `valign start` in the
card overlay.

Why it fits: aesthetic - the literal hazard-tape motif, hard and loud. Touch - pure
signal. Hardware - `repeating-linear-gradient` is a static fill GTK caches; shown only
in a transient state, no animation. Cheap.

Effort: S-M. Files: `eww/eww.yuck` (one `.hazard` box in the `musiccard-w` overlay),
`eww/eww.scss` (`.hazard`).

Risk/gotchas: confirm eww's GTK3 build renders `repeating-linear-gradient` (linear
gradients render in eww; repeating is the question - fall back to a solid `#ffe600` bar
with bold ink "PAUSED" text if not). Keep it OUT of the immersive view (already minimal).
Do not animate it - a static stripe is enough and stays cheap.

---

# WHAT I'D DO FIRST

Land P1 + P2 + P3 together as one commit, then screenshot. That is the smallest change
that flips the hero from soft-Spotify to brutalist: tokens (P1) give you the
border/shadow/no-radius system, P2 turns the circular controls into stamped cells, and
P3 kills the rounded blurred glowing cover for a hard ink-bordered, offset-shadowed
block - which is also the biggest Cherry Trail perf win (no more animated blur).
Immediately follow with F1 (the stepped VU strip) since P3 retires the `level` glow and
F1 gives `level` a new, on-aesthetic, cheaper home - ship them as a pair. P4 (title
block) is the cheap finishing touch on the same screen. Only then fan the vocabulary out
to P5/P6/P7 across album-grid, dash, and bluetooth.

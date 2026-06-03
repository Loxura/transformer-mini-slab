#!/usr/bin/env bash
# Renders a NEO-BRUTALIST analog clock face to an SVG and prints its path.
# Used by eww `(image :path clockimg)`; the filename changes each minute so eww reloads it.
# Hard look: paper disc, thick ink ring, square flat-end ink hands, ink tick BLOCKS, and
# one clash-orange minute hand (matches the clock-card's orange offset shadow). The accent
# is fixed here (the SVG is regenerated once/minute, so it can't cheaply track cover.glow).
H=$(( 10#$(date +%I) % 12 )); M=$(( 10#$(date +%M) ))
hang=$(( H*30 + M/2 ))   # hour hand: 30deg/hr + 0.5deg/min
mang=$(( M*6 ))          # minute hand: 6deg/min
f="/tmp/eww-clock-$(date +%H%M).svg"
if [ -f "$f" ]; then echo "$f"; exit 0; fi   # already drawn this minute
rm -f /tmp/eww-clock-*.svg 2>/dev/null

INK="#111111"; PAPER="#f2f2f2"; ACCENT="#FF4D00"

# Tick blocks: fat ink rectangles at the 12 hours; quarter ticks (i%3) are longer/wider.
ticks=""; i=0
while [ $i -lt 12 ]; do
  a=$(( i*30 ))
  if [ $(( i % 3 )) -eq 0 ]; then
    ticks="$ticks<rect x='105' y='12' width='10' height='24' fill='$INK' transform='rotate($a 110 110)'/>"
  else
    ticks="$ticks<rect x='107' y='14' width='6' height='16' fill='$INK' transform='rotate($a 110 110)'/>"
  fi
  i=$(( i+1 ))
done

cat > "$f" <<SVG
<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220' viewBox='0 0 220 220'>
  <circle cx='110' cy='110' r='100' fill='$PAPER' stroke='$INK' stroke-width='7'/>
  $ticks
  <rect x='104' y='56' width='12' height='62' fill='$INK' transform='rotate($hang 110 110)'/>
  <rect x='106' y='30' width='8' height='88' fill='$ACCENT' transform='rotate($mang 110 110)'/>
  <rect x='99' y='99' width='22' height='22' fill='$INK'/>
</svg>
SVG
echo "$f"

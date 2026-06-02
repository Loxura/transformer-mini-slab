#!/usr/bin/env bash
# Renders an analog clock face to an SVG (dark theme) and prints its path.
# Used by eww `(image :path clockimg)`; the filename changes each minute so eww reloads it.
H=$(( 10#$(date +%I) % 12 )); M=$(( 10#$(date +%M) ))
hang=$(( H*30 + M/2 ))   # hour hand: 30°/hr + 0.5°/min
mang=$(( M*6 ))          # minute hand: 6°/min
f="/tmp/eww-clock-$(date +%H%M).svg"
if [ -f "$f" ]; then echo "$f"; exit 0; fi   # already drawn this minute
rm -f /tmp/eww-clock-*.svg 2>/dev/null

ticks=""; i=0
while [ $i -lt 12 ]; do
  a=$(( i*30 ))
  ticks="$ticks<line x1='110' y1='14' x2='110' y2='26' stroke='#565f89' stroke-width='3' transform='rotate($a 110 110)'/>"
  i=$(( i+1 ))
done

cat > "$f" <<SVG
<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220' viewBox='0 0 220 220'>
  <circle cx='110' cy='110' r='104' fill='#1a1b26' stroke='#292e42' stroke-width='4'/>
  $ticks
  <line x1='110' y1='110' x2='110' y2='62' stroke='#c0caf5' stroke-width='7' stroke-linecap='round' transform='rotate($hang 110 110)'/>
  <line x1='110' y1='110' x2='110' y2='38' stroke='#7aa2f7' stroke-width='5' stroke-linecap='round' transform='rotate($mang 110 110)'/>
  <circle cx='110' cy='110' r='7' fill='#c0caf5'/>
</svg>
SVG
echo "$f"

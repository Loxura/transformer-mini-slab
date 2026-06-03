#!/usr/bin/env bash
# Winnipeg weather as JSON {glyph,temp,cond} for the Dash topbar chip. ONE network call
# (same wttr.in source + 30-min cadence as before). The condition word is mapped to a
# FontAwesome v4 glyph HERE, so the FA-font label never has to render a non-ASCII wttr
# weather symbol. The temp keeps its degree text (rendered in the mono font, not FA).
raw=$(curl -s --max-time 8 'wttr.in/Winnipeg?format=%C|%t' 2>/dev/null || wget -qO- --timeout=8 'wttr.in/Winnipeg?format=%C|%t' 2>/dev/null)
cond="${raw%%|*}"; temp="${raw#*|}"
[ "$raw" = "$cond" ] && temp=""    # split failed (no '|') -> no temp
lc=$(printf '%s' "$cond" | tr 'A-Z' 'a-z')
case "$lc" in
  *thunder*|*storm*)               g=0xf0e7 ;;  # bolt
  *snow*|*sleet*|*blizzard*|*ice*) g=0xf2dc ;;  # snowflake-o
  *rain*|*drizzle*|*shower*)       g=0xf043 ;;  # tint
  *fog*|*mist*|*haze*|*smoke*)     g=0xf0c2 ;;  # cloud
  *overcast*|*cloud*)              g=0xf0c2 ;;  # cloud
  *clear*|*sunny*|*sun*)           g=0xf185 ;;  # sun-o
  *)                               g=0xf0c2 ;;  # cloud (fallback)
esac
python3 -c "import json,sys; print(json.dumps({'glyph':chr($g),'temp':sys.argv[1].strip(),'cond':sys.argv[2]}))" "$temp" "$cond"

#!/usr/bin/env bash
# FontAwesome (v4) glyphs as JSON for the card, built from codepoints (no glyphs stored in
# the repo). json.dumps emits \uXXXX escapes which eww decodes and FontAwesome renders.
python3 -c 'import json
ic={"prev":0xf048,"play":0xf04b,"next":0xf051,"shuffle":0xf074,"artist":0xf007,
    "heart":0xf004,"voldn":0xf027,"volup":0xf028,"mute":0xf026}
print(json.dumps({k:chr(v) for k,v in ic.items()}))'

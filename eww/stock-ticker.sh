#!/usr/bin/env bash
# Rotating market ticker for the eww Dash (used via eww `deflisten`).
# Prints one "SYM  price  ±x%" line every 5s, cycling the list; refreshes ALL quotes
# from Stooq (no API key) every ~60s. Gold/Silver via XAUUSD/XAGUSD spot.
set -u

TICKERS=( "spy.us|SPY" "qqq.us|QQQ" "xauusd|GOLD" "xagusd|SILVER"
          "nvda.us|NVDA" "asml.us|ASML" "googl.us|GOOGL" "msft.us|MSFT"
          "aapl.us|AAPL" "amzn.us|AMZN" "meta.us|META" "tsla.us|TSLA" "amd.us|AMD" )

fetch() { curl -s "$1" 2>/dev/null || wget -qO- "$1" 2>/dev/null; }

declare -A PRICE CHG
refresh() {
  local q csv sym o c rest
  q=$(IFS=+; printf '%s' "${TICKERS[*]%%|*}")          # spy.us+qqq.us+xauusd+...
  csv=$(fetch "https://stooq.com/q/l/?s=${q}&f=soc&h&e=csv")   # Symbol,Open,Close
  [ -z "$csv" ] && return
  while IFS=, read -r sym o c rest; do
    [ "$sym" = "Symbol" ] && continue
    sym=$(printf '%s' "$sym" | tr 'A-Z' 'a-z')
    if [ -z "$c" ] || [ "$c" = "N/D" ]; then continue; fi
    PRICE[$sym]="$c"
    CHG[$sym]=$(awk -v o="$o" -v c="$c" 'BEGIN{ if (o+0>0) printf "%+.1f%%",(c-o)/o*100 }')
  done <<< "$csv"
}

last=0; i=0
while :; do
  now=$(date +%s)
  if [ $(( now - last )) -ge 60 ]; then refresh; last=$now; fi
  entry="${TICKERS[$(( i % ${#TICKERS[@]} ))]}"
  sym="${entry%%|*}"; disp="${entry##*|}"
  p="${PRICE[$sym]:-}"; ch="${CHG[$sym]:-}"
  if [ -n "$p" ]; then printf '%s   %s   %s\n' "$disp" "$p" "$ch"; else printf '%s   …\n' "$disp"; fi
  i=$(( i + 1 ))
  sleep 5
done

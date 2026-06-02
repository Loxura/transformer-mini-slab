#!/usr/bin/env bash
# Music controls for the deck card. Playback via mpc (mpd @127.0.0.1:6600); volume via wpctl.
set -uo pipefail
SINK="@DEFAULT_AUDIO_SINK@"
FAV_DIR="$HOME/.config/mpd/playlists"
FAV="$FAV_DIR/favorites.m3u"

case "${1:-}" in
  toggle) mpc -q toggle ;;
  next)   mpc -q next ;;
  prev)   mpc -q prev ;;

  # one-tap play a whole album (arg = album dir relative to the music library)
  playalbum) shift; mpc -q clear; mpc -q add "$1"; mpc -q play ;;

  # shuffle every track by the currently-playing artist
  shuffleartist)
      a=$(mpc -f %albumartist% current 2>/dev/null); [ -z "$a" ] && a=$(mpc -f %artist% current 2>/dev/null)
      [ -n "$a" ] && { mpc -q clear; mpc -q findadd artist "$a" || mpc -q findadd albumartist "$a"; mpc -q shuffle; mpc -q play; } ;;

  # shuffle the whole library
  shuffleall) mpc -q clear; mpc -q add /; mpc -q shuffle; mpc -q play ;;

  # one-tap: add the current track to the favorites playlist (dedup)
  favorite)
      f=$(mpc -f %file% current 2>/dev/null)
      [ -n "$f" ] && { mkdir -p "$FAV_DIR"; grep -qxF "$f" "$FAV" 2>/dev/null || printf '%s\n' "$f" >> "$FAV"; } ;;
  playfav) mpc -q clear; mpc -q load favorites 2>/dev/null; mpc -q play ;;

  # rescan the library so mpd picks up anything new dropped into ~/Music
  rescan)  mpc -q update ;;

  # volume (mpd output goes through PipeWire, so control the sink, not mpd's mixer)
  volup)   wpctl set-volume "$SINK" 5%+ ;;
  voldown) wpctl set-volume "$SINK" 5%- ;;
  mute)    wpctl set-mute "$SINK" toggle ;;
esac

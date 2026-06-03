#!/usr/bin/env bash
# T102HA (cht-bsw-rt5645): on a cold boot WirePlumber's first UCM pass leaves the
# speaker route dead — the sink looks correct and unmuted but no audio reaches the
# codec's analog stage (proven: a direct ALSA test tone works, only the WirePlumber
# path was silent until restarted). Restarting WirePlumber once the session is up
# re-runs UCM and routes sound to the speaker. Launched from sway `exec` at startup.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
sleep 8
systemctl --user restart wireplumber

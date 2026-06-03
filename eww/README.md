# Dash (eww) — cross-built, shipped to the tablet

eww ships no prebuilt binaries and compiling on the Cherry Trail Atom is painful (~RAM-tight),
so the binary is built on a faster x86_64 Linux box and copied over. This works because:
older-glibc build → runs on the tablet's newer glibc (forward-compatible), and GTK3 +
gtk-layer-shell are linked dynamically and already present on the tablet.

## Build (on the fast machine)
```sh
sudo apt install -y build-essential pkg-config libgtk-3-dev libgtk-layer-shell-dev libdbusmenu-gtk3-dev
# + a current Rust via rustup (distro rust is often too old)
git clone --depth 1 https://github.com/elkowar/eww
cd eww && cargo build --release --no-default-features --features=wayland   # wayland/sway backend
# -> target/release/eww
```

## Install on the tablet
```sh
scp target/release/eww  minideck@<tablet>:~/.local/bin/eww
scp eww.yuck eww.scss   minideck@<tablet>:~/.config/eww/
ldd ~/.local/bin/eww | grep "not found"    # should be empty
```

sway starts it as a **background layer**: `exec ~/.local/bin/eww open dashboard` (see `sway/config`).
It shows on the empty Dash workspace and sits behind app windows on the others.

Widgets: clock · date · now-playing (`mpc`) · CPU / RAM / battery. Tweak `eww.yuck` / `eww.scss`.

## Touch input — three GTK3/Wayland gotchas (hard-won)

This is a touchscreen-only deck (ELAN digitizer, output rotated `transform 90`). Three GTK3
quirks made taps land on the wrong widget. The digitizer hardware is fine — verified by reading
raw `/dev/input/event0`: a tap reports one clean contact with correct down/up coords.

1. **Motionless taps fired the top-left widget.** A Wayland `wl_touch.up` carries no
   coordinates, so GTK processed the release at the surface origin `(0,0)` unless a
   touch-*motion* updated the position first. A still tap therefore activated whatever sat
   top-left (a panel's close button). **Fix:** `export GDK_CORE_DEVICE_EVENTS=1` in
   `deck-launch.sh` before `eww daemon` — GTK then consumes sway's *pointer-emulation* events,
   which always carry coords (including on release). Must restart the daemon (not just reload)
   for the env to take.

2. **A `(scroll)` placed below a header offset every tap by ~one row.** A GtkScrolledWindow
   whose viewport starts below other widgets isn't having that header height subtracted during
   hit-testing, so taps land ~one row too low. Visible in short-row lists (track list, BT
   devices); masked in the album-cover grid because a tile row is taller than the offset.
   **Fix:** keep each scroll's viewport at the top edge. The panels (`album-grid`, `bt-panel`)
   put the scroll first in an `(overlay)` and **float the header/back button on top** of it
   (`:valign "start"`), with top padding on the scroll content (`.grid-scrollpad` /
   `.bt-scrollpad`) so row 1 clears the floating header.

3. **Highlights were sticky.** With pointer-emulation the cursor parks at the last touch
   point and never "leaves", so `:hover` stayed lit — a row looked permanently *selected*.
   **Fix:** style `:active` (pressed) instead of `:hover` — feedback only while the finger
   is down. See `eww.scss`.

Unrelated robustness in `bt-ctl`: device list sorts by **MAC** (stable, so rows don't jump
as devices connect / names resolve mid-scan), and `toggle` takes a per-device `flock` + skips
re-pairing, so a stray double-tap can't thrash connect/disconnect.

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

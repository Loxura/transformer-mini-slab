# Roadmap

Phased so each stage produces something usable. Don't wipe Windows until Phase 0 passes.

## Phase 0 — recon ✅ gate before wiping
- [ ] Identify WiFi/BT chip (Device Manager)
- [ ] Check UEFI bitness (`msinfo32`)
- [ ] Live-USB test: WiFi, touch, disk visible
- [ ] Buy a microSD for the music library

## Phase 1 — Debian base
- [ ] Install Debian (backports kernel if needed)
- [ ] Handle 32-bit UEFI (`bootia32.efi`) if required
- [ ] Confirm eMMC + microSD mount

## Phase 2 — make the hardware work
- [ ] WiFi up
- [ ] Bluetooth up (or decide: wired-only)
- [ ] Audio output working (codec UCM)
- [ ] Touchscreen + brightness
- [ ] Power tuning (`tlp`, `powertop --auto-tune`) — though it's mains-powered

## Phase 3 — base rice
- [ ] Lightweight WM (sway/labwc) or cage kiosk
- [ ] Port terminal dotfiles (kitty/fish/zellij)
- [ ] Apply the e-ink palette everywhere

## Phase 4 — music stack
- [ ] mpd + library on microSD
- [ ] TUI client (rmpc/ncmpcpp)
- [ ] cava reading PipeWire monitor

## Phase 5 — the look
- [ ] e-ink theming across all apps (`themes/kitty-eink.conf` etc.)
- [ ] No-motion pass (disable animations)
- [ ] Monochrome cava heartbeat (`themes/cava.conf`)

## Phase 6 — the heartbeat polish
- [ ] PipeWire EQ (EasyEffects or filter-chain)
- [ ] Album-art palette tint on track change
- [ ] Now-playing kiosk view

## Stretch
- [ ] Control playback from the main PC over the network
- [ ] Wall/desk mount
- [ ] Wake-on-touch now-playing screen

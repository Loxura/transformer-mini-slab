# Hardware revival checklist — Cherry Trail (T102HA)

Cherry Trail Atom support has improved a lot with modern 6.x kernels, but it's a checklist,
not plug-and-play. Work it in order.

## Phase 0 — recon (BEFORE wiping Windows)
- [ ] **Identify the WiFi/BT chip** in Windows Device Manager. This is the make-or-break item.
      Most likely a **Realtek RTL8723BS** (SDIO combo) — WiFi is in mainline; BT is fussier
      (UART-attached). If it's a **Broadcom `brcmfmac`**, WiFi needs a device-specific NVRAM
      `.txt` calibration file that may not ship in `linux-firmware` (extract from Windows driver).
- [ ] **Firmware mode**: `msinfo32` → "BIOS Mode". Cherry Trail tablets sometimes ship a
      **32-bit UEFI** on a 64-bit CPU → need a `bootia32.efi` on the USB/ESP to boot amd64.
- [ ] **Boot a live USB first** and verify WiFi + touch + disk *before* committing.

## Phase 1 — install
- [ ] Debian (recent kernel; use **backports** if the stable kernel misses your hardware).
- [ ] If 32-bit UEFI: add `bootia32.efi` (GRUB) to the EFI partition.
- [ ] **eMMC** not detected by installer? It needs `sdhci`/`sdhci-acpi`; a newer kernel usually fixes it.

## Phase 2 — drivers / quirks
- [ ] **WiFi**: `rtl8723bs` (mainline) or `brcmfmac` (+ NVRAM file).
- [ ] **Bluetooth**: the painful half — `btrtl` / `hci_uart`, may need a serial-attach service.
- [ ] **Audio**: Cherry Trail uses `bytcr-rt5640` / `rt5651` / ES8316 codecs that often need a
      **UCM** config, or it's silent. (Most relevant item for a *music* device — budget time here.)
- [ ] **Touchscreen**: usually Silead `gslx680` (i2c-HID), needs a per-model DMI config in-kernel.
- [ ] **Backlight/brightness**: may need an `i915` kernel param (`video=`/`acpi_backlight=`).
- [ ] **Suspend**: ⚠️ Cherry Trail S0ix/deep-sleep is notoriously broken — idle drain in "sleep"
      can be bad. **Mitigated here:** device is plugged in 24/7, so we don't rely on suspend.
- [ ] **Camera**: Atom ISP — effectively unsupported. Don't bother.

## Useful references
- Debian wiki: InstallingDebianOn Intel Atom tablets
- linuxium / `isorespin` spins historically bundled the bootia32 + rtl8723bs/brcmfmac firmware
  + audio configs for exactly these devices.

## This unit's findings (fill in)
- WiFi/BT chip: _TBD — check Device Manager_
- Firmware mode (32/64-bit UEFI): _TBD_
- eMMC size: _TBD_
- What worked / what didn't: _TBD_

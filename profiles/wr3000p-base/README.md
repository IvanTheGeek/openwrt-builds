# Profile: wr3000p-base

My base image for the **Cudy WR3000P v1** (device `cudy_wr3000p-v1`, board code **R57**): the same
software as [`wr3000h-base`](../wr3000h-base/README.md) and [`wr3000s-base`](../wr3000s-base/README.md)
on the P. One image, flashed to any unit; a unit's role is applied as configuration after flashing.

It is the fleet base for the P. [`wr3000p-mule`](../wr3000p-mule/README.md) remains a single bench
unit's development image and is not this.

- **`overlay-from`** names `wr3000h-base`, so the P carries the H's public and private overlays
  (OpenSSH on :22 and dropbear on :2222, both key-only; base root password; UTC; remote syslog;
  LuCI kept off WAN by the firewall zone). `build.sh` refuses to build if this seed and the H's
  differ outside `CONFIG_TARGET_*` lines, so **a package change there must be made here too**.
- **Hardware extras come from upstream `DEVICE_PACKAGES`**: USB 3 (`kmod-usb3`) and the Wi-Fi
  drivers. The P's 2.5 GbE WAN PHY needs no extra package.
- **LEDs:** upstream `board.d` already drives the WAN lamp (from the WAN PHY's LED) and the Internet
  lamp (`white:wan-online`, link on `wan`) for this device, so no lamp script is needed.
- **Diagnostics:** `iw` and `iperf3`, for the per-unit Wi-Fi radio test.
- **Flash layout:** OEM (Cudy) layout. Upstream also has `cudy_wr3000p-v1-ubootmod`, whose
  preloader is `cudy-ddr4` (the S and H use `cudy-ddr3`). No P here has been converted, so there
  is no `wr3000p-ubootmod-base` profile yet; it would be a seed with the device switched and
  `overlay-from wr3000h-base`.

## Build

```sh
./build.sh wr3000p-base              # homelab flavor, with overlays
./build.sh wr3000p-base --mainline   # pure upstream, no overlays or secrets
```

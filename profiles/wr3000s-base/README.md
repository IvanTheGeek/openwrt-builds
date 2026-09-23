# Profile: wr3000s-base

The estate's **base image for the Cudy WR3000S v1**. One image, flashed to any unit; a unit's
role is applied as configuration *after* flashing, not baked in. It is the S twin of
[`wr3000h-base`](../wr3000h-base/README.md) and carries the same baseline.

- **Sibling profile:** [`wr3000s-ubootmod-base`](../wr3000s-ubootmod-base/README.md) builds the
  same software for units converted to OpenWrt's own U-Boot layout. It reuses this profile's
  overlays (`overlay-from`), and `build.sh` refuses to build it if the two seeds' package lists
  differ, so **a package change here must be made in both seeds.**
- **Target:** mediatek / filogic, device `cudy_wr3000s-v1` (OEM flash layout). Cudy's board
  code is **R59**. The H is R63 and the P is R57, and Cudy's three intermediate images are all
  exactly 14,945,872 bytes with filenames that differ by one letter. Verify by MD5, never by
  size.
- **No external WAN PHY, so no `kmod-phy-*`.** Unlike the H and P, the S's WAN is port 0 of the
  internal MT7531 switch, at 1 GbE. The only `2500base-x` in its device tree is the internal
  CPU link (`port@6`). Upstream `DEVICE_PACKAGES` already carries the wifi drivers
  (`kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware`).
- **New-flash units need a new tree.** Units built from 2025 week 43 onward carry the ESMT
  F50L1G41LC SPI-NAND, which OpenWrt supports from 24.10.5. Any current `main` qualifies.
- **LEDs:** the five GPIO LEDs are System, Internet, WPS, 2.4G and 5G. The panel's WAN and
  LAN1–4 lamps are MT7531 switch LEDs that light on link in hardware, with no OpenWrt config
  (confirmed on the first unit, 2026-09-22). **Upstream gives the Internet lamp
  (`white:wan-online`) no trigger, so it stays dark; this profile fixes that** (below).

## What the image carries

The same as `wr3000h-base`; its README explains the reasons behind each choice.

| | |
|---|---|
| SSH | **OpenSSH on :22** (key-only) + **dropbear on :2222** (key-only break-glass) |
| Root password | set from the private overlay; **must be changed at commissioning** |
| Time | UTC |
| Logging | syslog to the estate's central collector, udp/514; the address is set in the private overlay |
| LuCI | present; kept off WAN/transit by the **firewall zone**, not by a pinned address |
| Diagnostics | `iw` (per-antenna signal, station and link details) and `iperf3` (throughput); used for the per-unit Wi-Fi radio test |
| Internet lamp | follows the WAN port's link (`netdev` trigger on `wan`, mode `link`); **S-only** |

## Overlays

- **Public** (`files/`): `99-homelab-base` and the sshd drop-in are **copies** of
  `wr3000h-base/files/`, byte-identical when this profile was created. **Change both profiles
  together.** One file is **S-only**: `98-homelab-internet-led` adds the Internet-lamp trigger.
  It steps aside if anything already drives that LED. That covers the upstream board.d line
  proposed for the S (the same line the H and P already have), so once it merges, the script
  does nothing and can be deleted. When it does add the LED, it writes exactly what
  `config_generate` writes from board.d, so the resulting config is identical either way
  (verified on a unit, 2026-09-22: same `uci export system` md5).
  The shared files are copies rather than `common/files/` because the mule and GL.iNet
  profiles do not ship OpenSSH, and moving dropbear to :2222 on those images would lock them
  out.
- ⚠️ **uci-defaults cannot use `logger`.** They run in `S10boot`, before `S12log` starts logd, so
  a first boot's `logger` output is lost. `98-homelab-internet-led` writes to `/dev/kmsg`
  instead, which the ring buffer keeps and `logread`/`dmesg` show.
- **Private** (`$OPENWRT_PRIVATE/wr3000s-base/files/`): the same fleet-wide base keys
  (`openwrt-base-openssh-20260908`, `openwrt-base-breakglass-20260908`), base root password
  and `99-homelab-syslog` as `wr3000h-base`. The keys are replaced by per-unit keys at
  commissioning.

## Build

```sh
./build.sh wr3000s-base              # homelab flavor, with overlays
./build.sh wr3000s-base --mainline   # pure upstream, no overlays or secrets
```

Record the buildroot commit (the output directory's suffix) whenever an image is deployed.

# Profile: wr3000s-base

The estate's **base image for the Cudy WR3000S v1**. One image, flashed to any unit; a unit's
role is applied as configuration *after* flashing, not baked in. It is the S twin of
[`wr3000h-base`](../wr3000h-base/README.md) and carries the same baseline.

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
- **LEDs are not fully wired upstream.** Upstream gives `led-internet` no default trigger, so
  that lamp stays dark out of the box. Cudy's own device tree has no GPIO for the panel's WAN
  and LAN lamps, so they are presumably switch-port LEDs. To be confirmed on the first unit.

## What the image carries

The same as `wr3000h-base`; its README explains the reasons behind each choice.

| | |
|---|---|
| SSH | **OpenSSH on :22** (key-only) + **dropbear on :2222** (key-only break-glass) |
| Root password | set from the private overlay; **must be changed at commissioning** |
| Time | UTC |
| Logging | syslog to `172.22.88.15` udp/514 |
| LuCI | present; kept off WAN/transit by the **firewall zone**, not by a pinned address |

## Overlays

- **Public** (`files/`): a **copy** of `wr3000h-base/files/`, byte-identical when this profile
  was created. **Change both profiles together.** They are copies rather than `common/files/`
  because the mule and GL.iNet profiles do not ship OpenSSH, and moving dropbear to :2222 on
  those images would lock them out.
- **Private** (`$OPENWRT_PRIVATE/wr3000s-base/files/`): the same fleet-wide base keys
  (`openwrt-base-openssh-20260908`, `openwrt-base-breakglass-20260908`) and base root password
  as `wr3000h-base`, replaced by per-unit keys at commissioning.

## Build

```sh
./build.sh wr3000s-base              # homelab flavor, with overlays
./build.sh wr3000s-base --mainline   # pure upstream, no overlays or secrets
```

Record the buildroot commit (the output directory's suffix) whenever an image is deployed.

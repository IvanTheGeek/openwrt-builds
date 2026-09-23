# Profile: wr3000s-ubootmod-base

My base image for a **Cudy WR3000S v1 on OpenWrt's own U-Boot layout** (device
`cudy_wr3000s-v1-ubootmod`, upstream since 25.12.4). Same software as
[`wr3000s-base`](../wr3000s-base/README.md), on the other flash layout: OpenWrt's BL2 and U-Boot
replace Cudy's, and the `ubi` partition grows from 64 MiB to 122.25 MiB. With this image on one
converted unit, `/overlay` measured 91.7 MiB instead of 41.3 MiB.

**The two layouts are not interchangeable.** A unit reports which one it runs in
`/tmp/sysinfo/board_name`: `cudy,wr3000s-v1` needs `wr3000s-base`, and `cudy,wr3000s-v1-ubootmod`
needs this profile. Sysupgrade refuses the wrong layout's image; never force it with `-F`.

## How it is built

- **`overlay-from`** names `wr3000s-base`. `build.sh` merges that profile's public *and* private
  overlays, so both profiles carry the same keys, password hash and settings from one copy.
- **`seed`** is `wr3000s-base`'s seed with the device switched. It also states
  `CONFIG_TARGET_ROOTFS_INITRAMFS=y`, which the TFTP recovery image needs; that is already the
  default on this target. `build.sh` refuses to build if the two seeds differ outside
  `CONFIG_TARGET_*` lines.
- The default buildroot is the homelab tree (upstream `main` plus my unmerged patches). **The one
  conversion done so far used the preloader and FIP from an `openwrt-25.12` branch build**
  (TF-A 2025-07-11, U-Boot 2025.10), built with
  `OPENWRT_HOMELAB=~/openwrt-2512 ./build.sh wr3000s-ubootmod-base`. The `main` bootloader
  (TF-A 2026-01-23, U-Boot 2026.07) is a different build and has not been written to a unit here.
  After conversion, OS updates can come from either tree: sysupgrade never touches the bootloader.

## What a build produces

| File | Used for |
|---|---|
| `…-ubootmod-squashfs-sysupgrade.itb` | **routine updates** (`sysupgrade`), and the last step of a conversion. **Homelab builds carry the private overlay: never publish.** |
| `…-ubootmod-initramfs-recovery.itb` | TFTP recovery. U-Boot (at 192.168.1.1) requests exactly `openwrt-mediatek-filogic-cudy_wr3000s-v1-ubootmod-initramfs-recovery.itb` from `192.168.1.254`. Builds from this repo already have that name; rename an official release download (`openwrt-25.12.x-mediatek-…`) to it. **Homelab builds carry the private overlay: serve it only over a direct cable, and remove it from the TFTP server afterwards.** |
| `…-ubootmod-preloader.bin` | BL2. **Conversion or bootloader repair only.** Carries no overlay. |
| `…-ubootmod-bl31-uboot.fip` | BL31 + U-Boot. **Conversion or bootloader repair only.** Carries no overlay. |

🚨 **The preloader and FIP replace the bootloader.** A bad or interrupted write leaves a unit that
can only be recovered over serial. Updating an already-converted unit needs the sysupgrade `.itb`
alone.

## Converting a unit (outline)

A unit on Cudy's stock firmware accepts only Cudy-signed images, so it needs Cudy's signed
"intermediate" OpenWrt image first, then an OpenWrt image on the Cudy layout that includes
`kmod-mtd-rw`. `wr3000s-base` does not include it, and a kmod must match the running kernel. As far
as I know the conversion is one-way: Cudy's own reset-button recovery stops working, and nobody has
documented a return to Cudy firmware.

Upstream's procedure is in commit `b7b4938303` ("mediatek: add cudy wr3000s-v1 ubootmod"), which
was cherry-picked to 25.12 as `8afab079a5`. My deviations are marked:
1. Back up every partition, especially **Factory** and **bdinfo** (upstream: "bdata"), which are
   unique per unit.
2. `insmod mtd-rw i_want_a_brick=1` (upstream installs it with `apk add kmod-mtd-rw`, which only
   works on a release image).
3. `mtd -e BL2 write …-preloader.bin BL2` and `mtd -e FIP write …-bl31-uboot.fip FIP`.
4. Connect the PC to a LAN port, set it to `192.168.1.254/24`, and serve the recovery `.itb` over
   TFTP. Then power-cycle the router (upstream's instruction; a plain `reboot` also worked for me).
5. From the recovery system:
   `ubidetach -p /dev/mtd5; ubiformat /dev/mtd5 -y; ubiattach -p /dev/mtd5`, then
   `ubimkvol /dev/ubi0 -n 0 -N ubootenv -s 128KiB` and
   `ubimkvol /dev/ubi0 -n 1 -N ubootenv2 -s 128KiB`.
6. `sysupgrade` the sysupgrade `.itb` (I used `-n`).

Checks worth doing first, learned converting one 2026-built unit:
- **Know the flash chip.** Units with serial date code 2543 (2025 week 43) or later have carried
  the ESMT **F50L1G41LC**, and I converted one such unit successfully. Cudy's stock 2.5.30
  (Aug 2026) also supports a **HeYangTek HYF1GQ4UDACAE**, so later units may carry that instead.
  OpenWrt's U-Boot has no driver for it, and the ID table in OpenWrt's BL2 does not list it: **do
  not convert a unit with that chip.** On a unit already running OpenWrt,
  `dmesg | grep 'SPI NAND was found'` names the maker: `ESMT` is fine. Only kernels from `main`
  after 2026-08-14 or the `openwrt-25.12` branch after 2026-09-03 recognize `HeYangTek`; 25.12.5
  and earlier do not, so they cannot run from that chip at all.
- **Bad blocks.** On the Cudy layout the kernel writes BL2 and FIP through NMBM's block mapping,
  but the boot chain reads them at fixed raw offsets (OpenWrt's BL2 reads the FIP at `0x3c0000`).
  Before writing, `dmesg | grep 'info table with writecount'` must show `writecount 0` for both
  tables, and `dmesg | grep 'mapped to physical block'` must print nothing. Run the second check
  again after the writes, and if a line appears, do not reboot. These checks only catch remaps NMBM
  has recorded: a factory-bad block among the first ~46 blocks could shift the mapping without
  either sign. I ruled that out on my unit with a raw bad-block scan from a custom kernel.
- **RAM speed.** The `cudy-ddr3` preloader in releases 25.12.4 and 25.12.5 does not cap the DDR3 at
  its rated 1866 MT/s; the cap landed after 25.12.5. Build the preloader from the `openwrt-25.12`
  branch (what I used) or `main`, and write the preloader and FIP from the same build.
- **The PC's `192.168.1.254` must be static and unmanaged.** While the router sits in U-Boot it
  serves no DHCP, and a network manager whose DHCP fails can remove a hand-added address.

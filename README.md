# openwrt-builds

Reproducible OpenWrt **buildroot recipes** for my routers (Cudy WR3000P/H, GL.iNet, the truck
router, wifi-as-WAN) and the **neighbornet** community-network project — built from source so they
can carry my own patches and LuCI fixes, while still tracking mainline and feeding fixes upstream.

**This repo is public on purpose.** Everything here is safe to share: build configs, non-secret
overlays, and scripts. **No keys, passwords, or private config live here** — those sit in a separate
private overlay repo that is merged in only at build time (see *Public / private split* below).

## Layout

```
profiles/<name>/
    seed              # `diffconfig` output: target, device, package selection. The build recipe.
    files/            # PUBLIC rootfs overlay for this profile (hostnames, safe defaults) — may be empty
    public-only       # OPTIONAL marker: if present, the private overlay is NEVER applied (neighbornet)
    overlay-from      # OPTIONAL: bare name of ONE other profile whose public+private overlays this one
                      #   reuses (same software, different flash layout). The two seeds must be identical
                      #   apart from CONFIG_TARGET_* lines, or build.sh refuses.
    README.md
common/files/         # PUBLIC overlay applied to every image
build.sh              # build one profile
sync.sh              # track upstream: ff `main`, rebase `build/homelab`, update feeds
```

## The buildroot (on the build host)

Git worktrees of `openwrt/openwrt`, sharing one object store:

| Worktree | Branch | What |
|---|---|---|
| `~/openwrt` | `build/homelab` | `upstream/main` + my not-yet-merged patches (e.g. the WR3000P WAN-LED fix). Builds **homelab** flavor. |
| `~/openwrt-mainline` | `main` | pristine `upstream/main`. Builds **mainline** flavor for comparison/testing. |
| `~/openwrt-2512` | a topic branch on `openwrt-25.12` | a release-branch tree, used through `OPENWRT_HOMELAB` (below). |

Remotes: `upstream` = openwrt/openwrt (fetch only), `fork` = IvanTheGeek/openwrt (PR topic branches).
`build/homelab` **self-cleans**: `sync.sh` rebases it onto upstream, so any commit that merges upstream
silently drops out — the branch shrinks toward zero as my PRs land.

## Build

```sh
./build.sh wr3000p-mule              # homelab flavor: my patches + overlays (incl. private)
./build.sh wr3000p-mule --mainline   # pristine upstream, seed only, NO overlays at all (A/B comparison)
./build.sh neighbornet-node          # public-only profile: private overlay refused even if present
```
Images land in `~/builds/<profile>-<flavor>-<shorthash>/` (`homelab-noprivate` when the private overlay
was skipped) with `SHA256SUMS`, one fresh directory per build: an existing one is renamed
`….prev-<time>`, never overwritten. The assembled `files/` overlay is wiped after every build; the
buildroot's `build_dir` and `bin/` still hold secret-bearing copies until the next build replaces
them. Only one `build.sh` runs per buildroot at a time (a lock in the tree's `tmp/`).

For a device on OpenWrt's own U-Boot layout (a `…-ubootmod` device), the output also holds the TFTP
recovery image and the bootloader (`*-initramfs-recovery.itb`, `*-preloader.bin`,
`*-bl31-uboot.fip`) next to the `*-squashfs-sysupgrade.itb`. The bootloader files are for converting
or repairing a unit only; see [`profiles/wr3000s-ubootmod-base`](profiles/wr3000s-ubootmod-base/README.md).

To build the homelab flavor from another buildroot, such as a release-branch worktree, set
`OPENWRT_HOMELAB`: `OPENWRT_HOMELAB=~/openwrt-2512 ./build.sh <profile>`. The flavor label stays
`homelab`; the commit hash in the directory name tells the trees apart. Every collected file must be
named for a device the profile's **seed** selects: a tree that lacks the device makes `defconfig`
fall back to another board, and `build.sh` refuses that.

## Public / private split

Overlays are merged in this order (later wins), then discarded:

```
common/files/  →  profiles/<p>/files/  →  $OPENWRT_PRIVATE/<p>/files/
```

A profile whose `overlay-from` file contains `<base>` gets `<base>`'s layers first:
`common/ → <base>/files/ → <p>/files/ → $OPENWRT_PRIVATE/<base>/files/ → $OPENWRT_PRIVATE/<p>/files/`.

- **This repo (public):** seeds, `common/`, `profiles/*/files`, scripts. GitHub.
- **Private overlay repo** (`$OPENWRT_PRIVATE`, default `~/repos/openwrt-private`): per-profile
  `files/` holding `authorized_keys`, password hashes, WireGuard keys, PSKs. Lives on a private
  Forgejo, **never** on GitHub. WireGuard private keys are age-encrypted at rest.
- The private overlay is applied **only** to homelab-flavor builds of profiles that are *not*
  marked `public-only`. `--mainline` (which applies no overlay at all), `--no-private`, the
  `public-only` marker, and an `overlay-from` base marked `public-only` each force it off.

**Rule:** an image built with the private overlay is itself secret-bearing. Never publish its
sysupgrade image (`.bin` or `.itb`) or its `initramfs-recovery.itb`: all of them carry the overlay.
(A U-Boot-layout build's `preloader.bin` and `bl31-uboot.fip` carry none.) Only `--mainline` /
`public-only` images may be shared. Serve a secret-bearing recovery image only over a direct cable,
and delete it from the TFTP server afterwards.

## Track upstream

```sh
./sync.sh          # fetch upstream, ff main, rebase build/homelab, refresh feeds
```
A rebase conflict means upstream changed code one of my patches touches — resolve it consciously
(for a kernel patch, `make target/linux/refresh` is usually the fix). That is a feature, not a bug:
it is upstream telling me my patch drifted, before a user ever hits it.

## Upstreaming

Fixes destined for OpenWrt/LuCI live as **topic branches on the forks** (`IvanTheGeek/openwrt`,
`IvanTheGeek/luci`) and go out as PRs — they do not live in this repo. My own *packages* (when they
exist) will live in a separate public feed repo. This repo is only the build recipes.

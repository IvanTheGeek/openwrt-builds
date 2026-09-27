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
| `~/openwrt-be9300` | `port/ipq53xx-be9300` | a parked port branch for the GL.iNet GL-BE9300; no feeds installed. |

The same layout is written down as data in [`trees.conf`](trees.conf), which `bootstrap.sh` reads.

Remotes: `upstream` = openwrt/openwrt (fetch only), `fork` = IvanTheGeek/openwrt (PR topic branches).
`build/homelab` **self-cleans**: `sync.sh` rebases it onto upstream, so any commit that merges upstream
silently drops out — the branch shrinks toward zero as my PRs land.

## Fresh build host

On a new build host (Debian 13 with the buildroot prerequisites installed), as the build user and
never as root:

```sh
git clone https://github.com/IvanTheGeek/openwrt-builds.git ~/repos/openwrt-builds
cd ~/repos/openwrt-builds
./bootstrap.sh                          # trees from trees.conf, LuCI fork via a src-link feed, feeds
./bootstrap.sh --seed-bundle <file>     # same, cloning openwrt.git from a local git bundle first
./bootstrap.sh --pin <manifest>         # exact commits, e.g. to prove a rebuilt host matches an old one
```

`bootstrap.sh` is idempotent: a tree, clone or feeds directory that already exists is reported and
left alone (never reset, rebased, pulled or re-checked-out), so running it on an existing host
changes nothing. `--pin` freezes each feed with `^<sha>` in that tree's `feeds.conf`, and `sync.sh`
then keeps them frozen until the suffixes are removed; use it for proofs, not for a normal host.
After bootstrap: supply the private overlay (`$OPENWRT_PRIVATE`) and, if you want packages built on
the new host to verify on routers flashed from the old one, the old tree's apk signing key pair
(`private-key.pem`, `public-key.pem` in each tree root; git-ignored, never in this repo). Then the
normal loop is `./sync.sh` and `./build.sh <profile>`.

## Build

```sh
./build.sh wr3000p-mule              # homelab flavor: my patches + overlays (incl. private)
./build.sh wr3000p-mule --mainline   # pristine upstream, seed only, NO overlays at all (A/B comparison)
./build.sh neighbornet-node          # public-only profile: private overlay refused even if present
./build.sh <profile> --site <name>   # plus ONE private site layer, merged last (see Site layers)
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

### Site layers

Some units share configuration because of *where* they are, not what they are: a location's Wi-Fi
passphrase, and the role each unit plays there. That lives in a **site layer** in the private repo,
never here, so nothing public names a site:

```
$OPENWRT_PRIVATE/sites/<name>/profiles   # the profiles this site layer may be built into, one per line
$OPENWRT_PRIVATE/sites/<name>/files/     # merged LAST, after every profile layer
```

`./build.sh <profile> --site <name>` refuses when no private overlay applies (`--mainline`,
`--no-private`, `public-only`) and when `profiles` does not list the profile. Every file that came
from the site layer is made owner-only in the image (git cannot carry `0600`). The output directory
is labelled `homelab-site<name>`. A site layer's role scripts pick a unit's role from its own
identity at first boot, so one image serves every unit of the site and the profiles stay
role-agnostic. Every site image is secret-bearing, like any homelab image.

**Secret placeholders.** A private file may be committed as a single PLACEHOLDER line carrying the
marker `@@UNSET-SECRET@@`, so that the layout is in git before the value exists. `build.sh` refuses
any overlay that still carries the marker (it prints the file names, never contents).
[`tools/set-site-psk.sh`](tools/set-site-psk.sh) writes a site's Wi-Fi passphrase file from a desktop
dialog or an existing 0600 file, and `--check` tells whether it is filled in, without showing it. Its
dialog captures live in a private tmpfs directory, never in the overlay tree, and `build.sh` refuses an
overlay that still holds one of its `.psk-*` temporary files (as it refuses `*.plain` and `*.age-key`).

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

#!/bin/bash
# build.sh — build one profile's OpenWrt image.
#
#   ./build.sh <profile> [--mainline] [--no-private] [-j N]
#
# Flavors:
#   (default)     build/homelab worktree  (~/openwrt)          = upstream + our patches, WITH overlays
#   --mainline    pristine main worktree  (~/openwrt-mainline) = pure upstream, seed only, NO overlays
#   OPENWRT_HOMELAB=<dir> selects another buildroot for the homelab flavor, e.g. a worktree of a
#   release branch. The flavor label stays "homelab"; the commit hash in the output dir name
#   identifies the tree.
#
# Overlay precedence (later wins), assembled into the buildroot's files/ then WIPED after:
#   common/files/  →  profiles/<p>/files/  →  $OPENWRT_PRIVATE/<p>/files/
# The private overlay is SKIPPED when: --no-private, or the profile (or its overlay-from base)
# contains a `public-only` marker file (neighbornet images must never carry secrets).
# --mainline applies NO overlay at all, public or private.
#
# overlay-from: a profile may name ONE other profile (a bare name) in a file `overlay-from`. That
# profile's public and private overlays are then merged in first, so two profiles that ship the
# same software on different flash layouts (e.g. wr3000s-base and wr3000s-ubootmod-base) share one
# copy of the secrets:
#   common/ → <base>/files/ → <p>/files/ → $PRIVATE/<base>/files/ → $PRIVATE/<p>/files/
# The two seeds must be identical apart from CONFIG_TARGET_* lines; the build refuses otherwise.
#
# Collected: the sysupgrade image (*-squashfs-sysupgrade.bin or .itb) and, for devices on
# OpenWrt's own U-Boot layout ("…-ubootmod"), the TFTP recovery image and the bootloader
# (*-initramfs-recovery.itb, *-preloader.bin, *-bl31-uboot.fip). Every collected file must be
# named for a device the SEED selects.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOMELAB="${OPENWRT_HOMELAB:-$HOME/openwrt}"
MAINLINE="${OPENWRT_MAINLINE:-$HOME/openwrt-mainline}"
PRIVATE="${OPENWRT_PRIVATE:-$HOME/repos/openwrt-private}"
OUTBASE="${OPENWRT_BUILDS_OUT:-$HOME/builds}"

profile=""; mainline=0; no_private=0; jobs="$(nproc)"
while [ $# -gt 0 ]; do case "$1" in
  --mainline) mainline=1;;
  --no-private) no_private=1;;
  -j) shift; jobs="$1";;
  -*) echo "unknown flag: $1" >&2; exit 2;;
  *) profile="$1";;
esac; shift; done

[ -n "$profile" ] || { echo "usage: $0 <profile> [--mainline] [--no-private] [-j N]"; echo "profiles:"; ls "$REPO_DIR/profiles"; exit 2; }
PROF="$REPO_DIR/profiles/$profile"
[ -d "$PROF" ] || { echo "no such profile: $profile (see $REPO_DIR/profiles/)" >&2; exit 2; }
[ -f "$PROF/seed" ] || { echo "profile '$profile' has no seed file" >&2; exit 2; }

# A PARKED profile documents a device we CANNOT build yet (no upstream target, etc). Its seed
# selects no target, so defconfig would silently fall back to the x86 default and emit a useless
# image that looks like a successful build. Refuse loudly instead.
if [ -f "$PROF/PARKED" ]; then
  echo "⛔ profile '$profile' is PARKED and cannot be built:" >&2
  sed 's/^/   /' "$PROF/PARKED" >&2
  echo "   See $PROF/README.md for the full reasoning." >&2
  exit 3
fi

# The device(s) the SEED selects. The artifact guard below compares against these, not against
# the post-defconfig .config: a tree that does not know the device makes defconfig fall back to
# the subtarget's default board silently, and the guard must not approve that board's images.
want=$(grep -oP '^CONFIG_TARGET_[A-Za-z0-9_]+_DEVICE_\K[^=]+(?==y)' "$PROF/seed" || true)
[ -n "$want" ] || { echo "profile '$profile': the seed selects no device (CONFIG_TARGET_…_DEVICE_…=y)" >&2; exit 2; }

# --- overlay-from: reuse another profile's overlays (see header) ---
BASEP=""; BPROF=""
if [ -f "$PROF/overlay-from" ]; then
  BASEP=$(tr -d '[:space:]' < "$PROF/overlay-from")
  case "$BASEP" in ''|*/*|.*) echo "profile '$profile': overlay-from must hold a bare profile name, got '$BASEP'" >&2; exit 2;; esac
  BPROF="$REPO_DIR/profiles/$BASEP"
  { [ "$BASEP" != "$profile" ] && [ -f "$BPROF/seed" ]; } ||
    { echo "profile '$profile': overlay-from names '$BASEP', which is not another profile with a seed" >&2; exit 2; }
  [ -f "$BPROF/overlay-from" ] &&
    { echo "profile '$profile': overlay-from '$BASEP' has its own overlay-from; chains are not supported" >&2; exit 2; }
  [ -f "$BPROF/PARKED" ] &&
    { echo "profile '$profile': overlay-from '$BASEP' is PARKED" >&2; exit 3; }
  # "Change both profiles together", enforced: apart from the target/device lines the two seeds
  # must be identical, deselections (# CONFIG_… is not set) included.
  body(){ { grep -E '^(# )?CONFIG_' "$1" || true; } | { grep -v -E '^(# )?CONFIG_TARGET_' || true; } | sort; }
  if [ "$(body "$PROF/seed")" != "$(body "$BPROF/seed")" ]; then
    echo "ERROR: '$profile' shares its overlays with '$BASEP', but the two seeds differ outside CONFIG_TARGET_*:" >&2
    { diff <(body "$BPROF/seed") <(body "$PROF/seed") || true; } |
      sed -n "s/^< /    only in $BASEP: /p; s/^> /    only in $profile: /p" >&2
    echo "  Update both seeds together, or drop overlay-from and give '$profile' its own overlays." >&2
    exit 1
  fi
fi

if [ "$mainline" = 1 ]; then TREE="$MAINLINE"; flavor="mainline"; else TREE="$HOMELAB"; flavor="homelab"; fi
[ -d "$TREE" ] || { echo "buildroot not found: $TREE" >&2; exit 1; }
echo "==> profile=$profile  flavor=$flavor  tree=$TREE  jobs=$jobs"

# One build per buildroot at a time. files/, .config and bin/targets are shared: a second run
# would replace the first one's overlay mid-build (a private overlay could land in a public-only
# image), wipe its files/ on exit, and delete its artifacts. make's children inherit fd 9 and
# exit with it; `9>&-` below keeps it from anything longer-lived.
mkdir -p "$TREE/tmp"; exec 9>"$TREE/tmp/.build.sh.lock"   # tmp/ is git-ignored in an OpenWrt tree
flock -n 9 || { echo "another build.sh is using $TREE — wait for it to finish" >&2; exit 1; }

# --- assemble the files/ overlay (idempotent, wiped on exit) ---
FILES="$TREE/files"
cleanup(){ rm -rf "$FILES"; }
trap cleanup EXIT
rm -rf "$FILES"; mkdir -p "$FILES"
# Fails the build if a layer cannot be copied in full (set -e): a partial private overlay must
# never produce an image that looks complete.
merge(){ cp -a "$1/." "$FILES/"; echo "    + overlay: $1"; }
use_private=1
[ "$no_private" = 1 ] && use_private=0
[ -e "$PROF/public-only" ] && { use_private=0; echo "    ! profile is public-only: private overlay SKIPPED"; }
[ -n "$BASEP" ] && [ -e "$BPROF/public-only" ] && { use_private=0; echo "    ! overlay-from '$BASEP' is public-only: private overlay SKIPPED"; }
if [ "$mainline" = 1 ]; then
  use_private=0
  echo "==> --mainline: no overlays (pure upstream)"
else
  echo "==> assembling overlay into $FILES"
  [ -d "$REPO_DIR/common/files" ] && merge "$REPO_DIR/common/files"
  [ -n "$BASEP" ] && { echo "    (overlay-from: $BASEP)"; [ -d "$BPROF/files" ] && merge "$BPROF/files"; }
  [ -d "$PROF/files" ] && merge "$PROF/files"
  if [ "$use_private" = 1 ]; then
    found=0
    for pp in ${BASEP:+"$BASEP"} "$profile"; do
      if [ -d "$PRIVATE/$pp/files" ]; then merge "$PRIVATE/$pp/files"; found=1; fi
    done
    [ "$found" = 1 ] || echo "    (no private overlay at $PRIVATE/${BASEP:+$BASEP|}$profile/files — building without secrets)"
  else
    echo "    ⚠️  no private overlay: any public hardening (e.g. key-only SSH) ships WITHOUT the keys"
  fi
fi
# strip .gitkeep placeholders so they don't land in the rootfs
find "$FILES" -name .gitkeep -delete 2>/dev/null || true
# Normalize permissions: git cannot carry directory modes, so a contributor
# umask of 0002 bakes group-writable dirs into the rootfs — dropbear then
# refuses ALL pubkey auth ("/etc/dropbear must be owned by user or root, and
# not writable by group or others"), masked by blank-password auth until a
# password is set. Strip group/other write from everything in the overlay.
chmod -R go-w "$FILES"

# --- configure from the seed ---
echo "==> applying seed"
cp "$PROF/seed" "$TREE/.config"
grep -q '^CONFIG_DEVEL=y'  "$TREE/.config" || echo 'CONFIG_DEVEL=y'  >> "$TREE/.config"
grep -q '^CONFIG_CCACHE=y' "$TREE/.config" || echo 'CONFIG_CCACHE=y' >> "$TREE/.config"
( cd "$TREE" && make defconfig >/dev/null 9>&- )
# Guard: defconfig silently DROPS unknown symbols: packages whose feed is not installed, and a
# target or device this tree does not have (it then falls back to the default board). Every
# =y package and target line the seed asked for must survive into .config.
dropped=$({ grep -E '^CONFIG_(PACKAGE|TARGET)_.*=y' "$PROF/seed" || true; } | while read -r line; do
  grep -qxF "$line" "$TREE/.config" || echo "    $line"
done)
if [ -n "$dropped" ]; then
  echo "ERROR: defconfig dropped seed lines (feeds not installed, or a device this tree does not have?):" >&2
  echo "$dropped" >&2
  echo "  fix: cd $TREE && ./scripts/feeds update -a && ./scripts/feeds install -a — or build from a newer tree" >&2
  exit 1
fi

# --- build ---
# Clear previous artifacts FIRST. bin/targets/ persists across builds, so the collector
# below would otherwise sweep up a stale image from a DIFFERENT profile — which happened
# on 2026-09-08: a wr3000p-v1 image from the 2026-08-30 mule build (carrying the mule's
# private key) was collected into the wr3000h-base output dir. The H and P images are
# dangerously easy to confuse, so this is a flashing hazard, not just untidiness.
echo "==> clearing previous artifacts ($TREE/bin/targets)"
rm -rf "$TREE/bin/targets"
echo "==> building (this can take a while; ccache warms subsequent runs)"
( cd "$TREE" && make -j"$jobs" 9>&- )

# --- collect output ---
# Candidates: sysupgrade images, plus the U-Boot-layout recovery image and bootloader.
cand=$(cd "$TREE" && ls bin/targets/*/*/*-squashfs-sysupgrade.bin bin/targets/*/*/*-squashfs-sysupgrade.itb \
         bin/targets/*/*/*-initramfs-recovery.itb bin/targets/*/*/*-preloader.bin bin/targets/*/*/*-bl31-uboot.fip \
         2>/dev/null || true)
# Guard: every candidate must be named for a device the SEED selected, matched on the full
# suffix. A substring match would let 'cudy_wr3000s-v1' accept '…-cudy_wr3000s-v1-ubootmod-…'.
imgs=""; nsys=0
for f in $cand; do
  base=$(basename "$f"); hit=0
  for d in $want; do for dn in "$d" "${d//_/-}"; do
    case "$base" in
      *-"$dn"-squashfs-sysupgrade.bin|*-"$dn"-squashfs-sysupgrade.itb) hit=1; nsys=$((nsys+1));;
      *-"$dn"-initramfs-recovery.itb|*-"$dn"-preloader.bin|*-"$dn"-bl31-uboot.fip) hit=1;;
    esac
    [ "$hit" = 1 ] && break 2
  done; done
  [ "$hit" = 1 ] || { echo "ERROR: build produced '$base', which is not named for a device this seed selected:" >&2
                      echo "$want" | sed 's/^/         want: /' >&2
                      echo "  A stale, fallback-board or cross-profile artifact was about to be shipped. Aborting." >&2; exit 1; }
  imgs="$imgs $f"
done
[ "$nsys" -ge 1 ] || { echo "no sysupgrade image produced for: $want — check the build log" >&2; exit 1; }
# A U-Boot-layout device must yield its whole set, or a conversion would be missing a piece.
for d in $want; do case "$d" in *-ubootmod)
  for suf in squashfs-sysupgrade.itb initramfs-recovery.itb preloader.bin bl31-uboot.fip; do
    case "$imgs" in *"-$d-$suf"*) ;; *) echo "ERROR: '$d' built no *-$d-$suf" >&2; exit 1;; esac
  done;;
esac; done

stamp="$(cd "$TREE" && git rev-parse --short HEAD)"
label="$flavor"; [ "$flavor" = homelab ] && [ "$use_private" = 0 ] && label="homelab-noprivate"
outdir="$OUTBASE/${profile}-${label}-${stamp}"
# A fresh directory per build, so nothing from an earlier run of the same commit sits next to
# this run's files unlisted. An existing one is kept, renamed, never deleted.
if [ -e "$outdir" ]; then
  prev="$outdir.prev-$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$outdir" "$prev"; echo "    (earlier output kept as $prev)"
fi
mkdir -p "$outdir"
names=""
for f in $imgs; do cp "$TREE/$f" "$outdir/"; names="$names $(basename "$f")"; done
( cd "$outdir" && sha256sum -- $names > SHA256SUMS )
echo "==> DONE"
echo "    images -> $outdir"
sed 's/^/      /' "$outdir/SHA256SUMS"
case "$names" in *-preloader.bin*|*-bl31-uboot.fip*)
  echo "    ⚠️  preloader.bin / bl31-uboot.fip REPLACE THE BOOTLOADER. They are for converting a unit"
  echo "       to the U-Boot layout (or repairing one), not for updates: a routine update is the"
  echo "       sysupgrade .itb alone. See the profile README before writing either.";;
esac
[ "$use_private" = 1 ] && echo "    🔒 secret-bearing: every image here except preloader/fip carries the private overlay — never publish them"
echo "    (overlay files/ wiped)"

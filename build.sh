#!/bin/bash
# build.sh — build one profile's OpenWrt image.
#
#   ./build.sh <profile> [--mainline] [--no-private] [-j N]
#
# Flavors:
#   (default)     build/homelab worktree  (~/openwrt)          = upstream + our patches, WITH overlays
#   --mainline    pristine main worktree  (~/openwrt-mainline) = pure upstream, seed only, NO overlays
#
# Overlay precedence (later wins), assembled into the buildroot's files/ then WIPED after:
#   common/files/  →  profiles/<p>/files/  →  $OPENWRT_PRIVATE/<p>/files/
# The private overlay is SKIPPED when: --mainline, or --no-private, or the profile
# contains a `public-only` marker file (neighbornet images must never carry secrets).
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

if [ "$mainline" = 1 ]; then TREE="$MAINLINE"; flavor="mainline"; else TREE="$HOMELAB"; flavor="homelab"; fi
[ -d "$TREE" ] || { echo "buildroot not found: $TREE" >&2; exit 1; }
echo "==> profile=$profile  flavor=$flavor  tree=$TREE  jobs=$jobs"

# --- assemble the files/ overlay (idempotent, wiped on exit) ---
FILES="$TREE/files"
cleanup(){ rm -rf "$FILES"; }
trap cleanup EXIT
rm -rf "$FILES"; mkdir -p "$FILES"
merge(){ [ -d "$1" ] && cp -a "$1/." "$FILES/" 2>/dev/null && echo "    + overlay: $1" || true; }
echo "==> assembling overlay into $FILES"
merge "$REPO_DIR/common/files"
merge "$PROF/files"
use_private=1
[ "$mainline" = 1 ] && use_private=0
[ "$no_private" = 1 ] && use_private=0
[ -e "$PROF/public-only" ] && { use_private=0; echo "    ! profile is public-only: private overlay SKIPPED"; }
if [ "$use_private" = 1 ]; then
  if [ -d "$PRIVATE/$profile/files" ]; then merge "$PRIVATE/$profile/files"
  else echo "    (no private overlay at $PRIVATE/$profile/files — building without secrets)"; fi
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
( cd "$TREE" && make defconfig >/dev/null )

# --- build ---
echo "==> building (this can take a while; ccache warms subsequent runs)"
( cd "$TREE" && make -j"$jobs" )

# --- collect output ---
stamp="$(cd "$TREE" && git rev-parse --short HEAD)"
outdir="$OUTBASE/${profile}-${flavor}-${stamp}"
mkdir -p "$outdir"
imgs=$(cd "$TREE" && ls bin/targets/*/*/*-squashfs-sysupgrade.bin 2>/dev/null || true)
[ -n "$imgs" ] || { echo "no sysupgrade image produced — check the build log" >&2; exit 1; }
for f in $imgs; do cp "$TREE/$f" "$outdir/"; done
( cd "$outdir" && sha256sum ./*.bin > SHA256SUMS )
echo "==> DONE"
echo "    images -> $outdir"
sed 's/^/      /' "$outdir/SHA256SUMS"
echo "    (overlay files/ wiped)"

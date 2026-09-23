#!/bin/bash
# bootstrap.sh — recreate the buildroot trees on a FRESH build host.
# Run as the build user. Idempotent: a tree/clone that already exists is VERIFIED and left alone —
# never reset, rebased, pulled or re-checked-out. Afterwards the normal loop is ./sync.sh.
#
#   ./bootstrap.sh                       # trees from trees.conf, feeds at their current heads
#   ./bootstrap.sh --pin <manifest>      # exact SHAs, from a manifest captured on an existing host.
#                                        #   ⚠ pins feeds with ^<sha> in feeds.conf: sync.sh then keeps
#                                        #   them frozen until the ^<sha> suffixes are removed.
#   ./bootstrap.sh --seed-bundle <file>  # clone openwrt.git from a local git bundle, then fetch only
#                                        #   the difference from GitHub (local copies first)
#
# trees.conf (this repo), one tree per line:
#   <dir under $HOME>  <branch>  <start ref|sha>  <upstream to track|->  <feeds: yes|no>
# The FIRST line is the primary clone; the others are worktrees of it (one object store).
# Manifest lines: `tree:<dir> <sha>`, `feed:<dir>:<feed> <sha>`, `luci <sha>`.
# Public repo: nothing here may name a site-specific address, host, or path outside $HOME (README).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/openwrt/openwrt.git}"
FORK_URL="${FORK_URL:-https://github.com/IvanTheGeek/openwrt.git}"
RELEASE_BRANCH="${RELEASE_BRANCH:-openwrt-25.12}"
LUCI_URL="${LUCI_URL:-https://github.com/IvanTheGeek/luci.git}"
LUCI_BRANCH="${LUCI_BRANCH:-theme-nopassword-warning-on-admin-page}"
LUCI_DIR="$HOME/luci"
PIN=""; BUNDLE=""
while [ $# -gt 0 ]; do case "$1" in
  --pin) PIN="$2"; shift ;;
  --seed-bundle) BUNDLE="$2"; shift ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac; shift; done
[ -z "$PIN" ] || [ -s "$PIN" ] || { echo "manifest $PIN missing or empty" >&2; exit 2; }
[ -z "$BUNDLE" ] || git bundle verify -q "$BUNDLE" || { echo "bundle $BUNDLE does not verify" >&2; exit 2; }
[ -s trees.conf ] || { echo "trees.conf missing" >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo "run as the build user, not root (buildroot refuses root)" >&2; exit 2; }

pin() { [ -n "$PIN" ] && awk -v k="$1" '$1==k{print $2; f=1} END{exit !f}' "$PIN"; }
PRIMARY="$HOME/$(awk '!/^#/ && NF {print $1; exit}' trees.conf)"

# ── 1. the primary clone ────────────────────────────────────────────────────────────────
FRESH=0
if [ -d "$PRIMARY/.git" ]; then
  echo "== $PRIMARY exists - left as is"
else
  src="$UPSTREAM_URL"; [ -z "$BUNDLE" ] || src="$BUNDLE"
  git clone -q --no-checkout --origin upstream "$src" "$PRIMARY"
  git -C "$PRIMARY" remote set-url upstream "$UPSTREAM_URL"
  git -C "$PRIMARY" config --replace-all remote.upstream.fetch '+refs/heads/main:refs/remotes/upstream/main'
  git -C "$PRIMARY" config --add remote.upstream.fetch "+refs/heads/${RELEASE_BRANCH}:refs/remotes/upstream/${RELEASE_BRANCH}"
  git -C "$PRIMARY" remote add fork "$FORK_URL"
  git -C "$PRIMARY" fetch -q upstream
  git -C "$PRIMARY" fetch -q fork
  FRESH=1
fi

# ── 2. branches + worktrees ─────────────────────────────────────────────────────────────
while read -r dir branch start track _; do
  case "$dir" in ''|'#'*) continue ;; esac
  t="$HOME/$dir"
  # An existing tree is checked FIRST and never resolved against: on a long-lived host the remote-
  # tracking refs can predate the start branch (the fork's topic branches, 2026-09-23), and an
  # "exists - left as is" run must not depend on a fetch it deliberately does not make.
  if [ -e "$t/.git" ] && { [ "$t" != "$PRIMARY" ] || [ "$FRESH" = 0 ]; }; then
    p="$(pin "tree:$dir" || true)"
    echo "== $t exists at $(git -C "$t" rev-parse --short=10 HEAD)${p:+ (manifest: ${p:0:10})} - left as is"
    continue
  fi
  want="$(pin "tree:$dir" || git -C "$PRIMARY" rev-parse --verify "${start}^{commit}")" \
    || { echo "FATAL: cannot resolve '$start' for $dir in $PRIMARY (fetch the remote, or fix trees.conf)" >&2; exit 1; }
  if [ "$t" = "$PRIMARY" ]; then
    git -C "$PRIMARY" checkout -q -b "$branch" "$want"
    mkdir -p "$PRIMARY/dl"
  else
    # -B only on a clone made by THIS run, where the one pre-existing branch is the clone's own `main`
    if [ "$FRESH" = 1 ]; then git -C "$PRIMARY" worktree add -q -B "$branch" "$t" "$want"
    elif git -C "$PRIMARY" show-ref -q --verify "refs/heads/$branch"; then git -C "$PRIMARY" worktree add -q "$t" "$branch"
    else git -C "$PRIMARY" worktree add -q -b "$branch" "$t" "$want"; fi
    [ -e "$t/dl" ] || ln -s "$PRIMARY/dl" "$t/dl"
  fi
  [ "$track" = - ] || git -C "$PRIMARY" branch -q --set-upstream-to="$track" "$branch"
  got="$(git -C "$t" rev-parse HEAD)"
  [ "$got" = "$want" ] || echo "   ⚠ $t is at ${got:0:10}, not ${want:0:10} (existing branch kept)"
  echo "== $t: $branch at ${got:0:10}"
done < trees.conf

# ── 3. the LuCI fork, consumed by the PRIMARY tree through a src-link feed ──────────────
if [ ! -d "$LUCI_DIR/.git" ]; then
  git clone -q --branch "$LUCI_BRANCH" "$LUCI_URL" "$LUCI_DIR"
  if w="$(pin luci)"; then git -C "$LUCI_DIR" checkout -q -B "$LUCI_BRANCH" "$w"; fi
fi
if [ ! -f "$PRIMARY/feeds.conf" ]; then
  sed -E "s|^src-git(-full)? luci .*|src-link luci $LUCI_DIR|" "$PRIMARY/feeds.conf.default" > "$PRIMARY/feeds.conf"
fi
grep -qx "src-link luci $LUCI_DIR" "$PRIMARY/feeds.conf" || { echo "FATAL: $PRIMARY/feeds.conf has no luci src-link" >&2; exit 1; }

# ── 4. feeds, only for trees marked yes ─────────────────────────────────────────────────
while read -r dir _ _ _ feeds; do
  case "$dir" in ''|'#'*) continue ;; esac
  [ "$feeds" = yes ] || continue
  t="$HOME/$dir"
  if [ -d "$t/feeds" ]; then echo "== $t/feeds exists - left as is (sync.sh refreshes the primary)"; continue; fi
  if [ -n "$PIN" ]; then
    conf="$t/feeds.conf"; [ -f "$conf" ] || cp "$t/feeds.conf.default" "$conf"
    for f in packages routing telephony video luci; do
      s="$(pin "feed:$dir:$f")" || continue
      sed -i -E "s|^(src-git(-full)? $f [^ ;^]+)([;^].*)?$|\\1^$s|" "$conf"
    done
  fi
  ( cd "$t" && ./scripts/feeds update -a </dev/null >/dev/null && ./scripts/feeds install -a </dev/null >/dev/null )
  echo "== $t feeds updated + installed"
done < trees.conf
echo "bootstrap complete. Next, from the operator side: private overlay, then (owner's call) signing keys; then ./sync.sh"

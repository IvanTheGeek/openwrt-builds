#!/bin/bash
# sync.sh — track upstream. Run before a build session or weekly.
#   - fast-forwards the pristine `main` worktree to upstream/main
#   - rebases `build/homelab` onto upstream/main (commits merged upstream drop out automatically)
#   - updates + installs feeds
# Stops loudly on a rebase conflict: that means upstream moved under one of our patches
# (the openwrt-ai lesson) — resolve consciously, don't paper over it.
set -euo pipefail
HOMELAB="${OPENWRT_HOMELAB:-$HOME/openwrt}"
MAINLINE="${OPENWRT_MAINLINE:-$HOME/openwrt-mainline}"

echo "==> fetching upstream + fork"
git -C "$HOMELAB" fetch upstream --quiet
git -C "$HOMELAB" fetch fork --quiet || true
new=$(git -C "$HOMELAB" rev-parse --short upstream/main)
echo "    upstream/main = $new"

echo "==> fast-forwarding pristine main ($MAINLINE)"
git -C "$MAINLINE" merge --ff-only upstream/main && echo "    main -> $new"

echo "==> rebasing build/homelab onto upstream/main"
cur=$(git -C "$HOMELAB" symbolic-ref --short HEAD)
[ "$cur" = "build/homelab" ] || { echo "    ! $HOMELAB is on '$cur', expected build/homelab — aborting"; exit 1; }
if git -C "$HOMELAB" rebase upstream/main; then
  left=$(git -C "$HOMELAB" rev-list --count upstream/main..HEAD)
  echo "    ✅ rebased; $left local patch commit(s) remain on build/homelab"
  [ "$left" = 0 ] && echo "    🎉 all our patches have merged upstream — build/homelab is now pure upstream"
else
  echo "    ⛔ REBASE CONFLICT — upstream changed something one of our patches touches."
  echo "       Resolve in $HOMELAB (git status), 'git rebase --continue', or 'git rebase --abort'."
  echo "       If a kernel patch no longer applies: 'make target/linux/refresh' is usually the fix."
  exit 1
fi

echo "==> updating feeds"
( cd "$HOMELAB" && ./scripts/feeds update -a >/dev/null && ./scripts/feeds install -a >/dev/null ) && echo "    feeds updated + installed"
echo "==> sync complete."

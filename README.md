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
    README.md
common/files/         # PUBLIC overlay applied to every image
build.sh              # build one profile
sync.sh              # track upstream: ff `main`, rebase `build/homelab`, update feeds
```

## The buildroot (on the build host)

Two git worktrees of `openwrt/openwrt`, sharing one object store:

| Worktree | Branch | What |
|---|---|---|
| `~/openwrt` | `build/homelab` | `upstream/main` + my not-yet-merged patches (e.g. the WR3000P WAN-LED fix). Builds **homelab** flavor. |
| `~/openwrt-mainline` | `main` | pristine `upstream/main`. Builds **mainline** flavor for comparison/testing. |

Remotes: `upstream` = openwrt/openwrt (fetch only), `fork` = IvanTheGeek/openwrt (PR topic branches).
`build/homelab` **self-cleans**: `sync.sh` rebases it onto upstream, so any commit that merges upstream
silently drops out — the branch shrinks toward zero as my PRs land.

## Build

```sh
./build.sh wr3000p-mule              # homelab flavor: my patches + overlays (incl. private)
./build.sh wr3000p-mule --mainline   # pristine upstream, seed only, no overlays (A/B comparison)
./build.sh neighbornet-node          # public-only profile: private overlay refused even if present
```
Images land in `~/builds/<profile>-<flavor>-<shorthash>/` with `SHA256SUMS`. The assembled `files/`
overlay is wiped after every build, so secrets never linger in the tree.

## Public / private split

Overlays are merged in this order (later wins), then discarded:

```
common/files/  →  profiles/<p>/files/  →  $OPENWRT_PRIVATE/<p>/files/
```

- **This repo (public):** seeds, `common/`, `profiles/*/files`, scripts. GitHub.
- **Private overlay repo** (`$OPENWRT_PRIVATE`, default `~/repos/openwrt-private`): per-profile
  `files/` holding `authorized_keys`, password hashes, WireGuard keys, PSKs. Lives on a private
  Forgejo, **never** on GitHub. WireGuard private keys are age-encrypted at rest.
- The private overlay is applied **only** to homelab-flavor builds of profiles that are *not*
  marked `public-only`. `--mainline`, `--no-private`, and the `public-only` marker each force it off.

**Rule:** an image built with the private overlay is itself secret-bearing — never publish that
`.bin`. Only `--mainline` / `public-only` images (no baked secrets) may be shared.

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

# Profile: wr3000h-base

The estate's **base image for the Cudy WR3000H v1**. One image, flashed to any unit; the
role (bridge AP or primary router) is applied as configuration *after* flashing, not baked
in.

- **Target:** mediatek / filogic, device `cudy_wr3000h-v1` (board code **R63** — the
  WR3000P is R57, and the two Cudy intermediates are both exactly 14,945,872 bytes and
  differ by one letter in the filename. Verify by MD5, never by size.)
- **`kmod-phy-motorcomm` is already in upstream `DEVICE_PACKAGES`** for this device and
  does not need to be in the seed. It is not optional: both estate H units carry the
  Motorcomm YT8821 WAN PHY despite Cudy documenting a Realtek, and without the driver the
  2.5 G WAN is dead.

## What the image carries

| | |
|---|---|
| SSH | **OpenSSH on :22** (key-only) + **dropbear on :2222** (key-only break-glass) |
| Root password | set from the private overlay — **must be changed at commissioning** |
| Time | UTC (whole estate since 2026-07-29) |
| Logging | syslog → the estate's central collector, udp/514; the address is set in the private overlay |
| LuCI | present; kept off WAN/transit by the **firewall zone**, not by a pinned address |
| Diagnostics | `iw` (per-antenna signal, station and link details) and `iperf3` (throughput); used for the per-unit Wi-Fi radio test |
| Mail | none — the estate relay is a Debian/systemd path and cannot run here |

### Why a root password is SET rather than locked

`openssh-server` here is a **non-PAM build**. A *locked* root password (`passwd -l root`,
which writes `!` to `/etc/shadow`) makes OpenSSH's `allowed_user()` treat the account as
disabled and refuse **all** authentication — including public key. A real password plus
`PasswordAuthentication no` + `PermitEmptyPasswords no` + `AuthenticationMethods publickey`
is the supported way to be key-only here.

### Why LuCI is firewalled rather than address-bound

uhttpd authenticates against the **same root password** as the shell account. With SSH
password auth off, HTTP is the remaining password surface, so it must never be reachable on
a WAN or transit interface.

It is kept off those interfaces by **fw4 zone policy** (`wan` zone `input REJECT`), *not* by
pinning `listen_http`. An earlier draft of this profile pinned it to `192.168.1.1`, which
would have silently stranded LuCI the moment the LAN was renumbered off the OpenWrt default.
**Whoever gives one of these boxes a transit or WAN interface must place it in a zone with
`input REJECT`**.

## Overlays

- **Public** (`files/`): `99-homelab-base` uci-defaults + the sshd hardening drop-in. No secrets.
- **Private** (`$OPENWRT_PRIVATE/wr3000h-base/files/`): the two base public keys,
  `90-homelab-rootpw` which sets the base root password hash, and `99-homelab-syslog` which
  points syslog at the estate's collector. Forgejo only, never GitHub.

Base keys (public halves live in the private overlay; private halves on the laptop):

| Key | Daemon / port | Fingerprint |
|---|---|---|
| `id_ed25519_openwrt_openssh` | OpenSSH :22 | `SHA256:DK60McUTZXB1HMrQLEUq2b4BsQdSzifj1EJzECiyf7w` |
| `id_ed25519_openwrt_breakglass` | dropbear :2222 | `SHA256:TMWZH0+nFD9w3KOxbo9oQcZ/4Epb621bjKrRtfRMSkY` |

These are **base** keys, shared by every unit built from this image, and are replaced by
per-unit keys at commissioning. Host keys are **generated on first boot** by the sshd init
script (`openssh-keygen`) — never baked, so units do not share one identity.

## Reproducibility

The estate tracks SNAPSHOT, so an image is only reproducible if its inputs are pinned.
The inputs for this profile at the time of writing:

    openwrt (build/homelab)  7b396007440c94f8e54fd2507c813571de170be6
    luci fork (theme-nopassword-warning-on-admin-page)
                             e00b7d9252f367bdeceb4ba5c4b0f085ae9276bb

`build.sh` stamps the output directory with the buildroot's short HEAD. Record the LuCI
commit alongside it when an image is deployed.

## Build

```sh
./build.sh wr3000h-base
```

Pure-upstream comparison (no patches, no overlays, no secrets):

```sh
./build.sh wr3000h-base --mainline
```

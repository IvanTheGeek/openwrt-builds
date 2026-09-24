# Profile: wr3000s-bench

A **bench-only** image for the Cudy WR3000S v1 (OEM flash layout, device `cudy_wr3000s-v1`):
[`wr3000s-base`](../wr3000s-base/README.md) plus the tools for measuring VPN and crypto
performance on the MT7981B. It is for units on a test bench, never for a unit in service.

## What it adds to wr3000s-base

| In the image (`=y`) | |
|---|---|
| WireGuard | `kmod-wireguard`, `wireguard-tools` |
| OpenVPN | `openvpn-openssl` with data channel offload (`kmod-ovpn-backports`), `kmod-tun`, `libnl-genl` |
| IPsec, kernel | `kmod-ipsec`, `kmod-ipsec4`, `kmod-ipsec6`, `kmod-xfrm-interface`, `kmod-crypto-chacha20poly1305`, and `ip-full` for manual SAs (`ip xfrm`) |
| IPsec, IKEv2 | strongSwan with `swanctl` (vici) and the plugins for PSK or certificate auth with AES-GCM, x25519 and ChaCha20-Poly1305: kernel-netlink, socket-default, openssl, kdf, pubkey, x509, pem, pkcs1, pkcs8, random, drbg, sha1, sha2, gcm, aes, hmac, curve25519, chapoly, constraints |
| Tools | `openssl-util`, `bridger`, `tc-full`, `ethtool-full`, `tcpdump-mini`, `conntrack` |

The EIP-97 crypto engine driver (`kmod-crypto-hw-safexcel`) is already in the base image: it is a
filogic default package.

**Built by the same build but not in the image (`=m`)**, so they carry the image's kernel hash and
install later with `apk add`, without reflashing: `openvpn-mbedtls`, `kmod-crypto-test` (tcrypt),
`kmod-crypto-user` and `crconf`, `libopenssl-afalg`, `kmod-cryptodev` and `libopenssl-devcrypto`,
`perf`, full `tcpdump`, `miniupnpc`, and the remaining strongSwan tools and plugins (pki, charon-cmd,
kernel-libipsec, updown, EAP/XAUTH, load-tester, test-vectors and others; the seed lists them).

- `tcpdump-mini` has no ESP or ISAKMP printers. For IPsec work, swap in the full build:
  `apk del tcpdump-mini && apk add tcpdump`.
- `devlink` is `=m` only to build `ip-full` and `tc-full` against libmnl (iproute2 enables it when
  devlink, rdma or dcb is selected). Without it they cannot print the kernel's extended netlink
  error messages, which matter when adding xfrm states by hand.
- `strongswan-mod-updown` is `=m` on purpose. It only runs a script that a swanctl child names, and
  as `=y` it would pull `iptables-nft` and the x_tables kernel modules into an nftables (fw4) image.

## Known build failures

- **`perf` does not build on Linux 6.18.52.** OpenWrt builds it with `NO_SLANG=1`, and in that
  configuration `tools/perf/util/hist.h` declares a stub `hist_entry__tui_annotate()` with four
  arguments while `builtin-annotate.c` calls it with three. That is a kernel `tools/perf` defect,
  not this profile's. Build with `IGNORE_ERRORS=m` so it cannot stop the image; every other `=m`
  package still builds.
- **`kmod-crypto-test` needs a buildroot fix on 6.16 and later.** Linux renamed tcrypt's symbol
  from `CONFIG_CRYPTO_TEST` to `CONFIG_CRYPTO_BENCHMARK`, and OpenWrt's package still names only the
  old one, so it builds an empty package. The buildroot this profile is built from adds
  `CONFIG_CRYPTO_BENCHMARK` to that package's `KCONFIG`.

## Differences from the base image beyond the added packages

- **Kernel:** `CONFIG_KERNEL_PERF_EVENTS=y` (perf events plus the ARM PMU drivers), because `perf`
  cannot be selected without it. It stays on while perf fails to build: `perf` does not depend on
  the kernel hash, so a fixed perf package can be added later without reflashing. The added modules also change the kernel's module hash, so
  packages from this build and from `wr3000s-base` builds do **not** mix.
- **bridger** starts at boot when installed and offloads bridged flows. Stop it
  (`service bridger stop`) to measure without it.

## Overlays

This profile ships **exactly** `wr3000s-base`'s overlays. It cannot use `overlay-from`, because
`build.sh` requires identical seeds for that. Instead:

- public: `files` is a symlink to `../wr3000s-base/files`;
- private: the build host needs `$OPENWRT_PRIVATE/wr3000s-bench` as a symlink to `wr3000s-base`.
  **Check that the symlink exists before every build.** Without it `build.sh` only prints a
  warning and builds an image with key-only SSH and no keys.

## Build

A buildroot with a host LLVM for BPF (`bridger`); the seed points at `/usr/lib/llvm-19`:

```sh
ls -l "${OPENWRT_PRIVATE:-$HOME/repos/openwrt-private}/wr3000s-bench"   # must point at wr3000s-base
IGNORE_ERRORS=m OPENWRT_HOMELAB=~/openwrt-bench-main ./build.sh wr3000s-bench
```

`IGNORE_ERRORS=m` ignores failures only in source packages whose every selected package is `=m`
(perf, today). A failure in anything that reaches the image still stops the build.

`build.sh` collects the sysupgrade image only. The `=m` packages are in the buildroot's
`bin/packages/` and `bin/targets/mediatek/filogic/packages/`, signed with that buildroot's apk key.
The image carries the private overlay, so it is secret-bearing: never publish it.

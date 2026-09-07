# Profile: be9300-flint3 — 🅿️ PARKED, NOT BUILDABLE

**GL.iNet GL-BE9300 "Flint 3"**, IPQ5332. A **placeholder with a reason**, not a build.
Measured 2026-09-07 against `upstream/main` = `7b39600744`.

## Why it cannot build

```
target/linux/qualcommax/  ->  ipq50xx  ipq60xx  ipq807x
target/linux/qualcommbe/  ->  ipq95xx
                              ^ no ipq53xx anywhere
```

There is **no IPQ5332 target in mainline OpenWrt**, so there is no device to select and no seed to
write. Everything else follows from that.

## What the running unit actually is

| | |
|---|---|
| Kernel | **5.4.213** (QSDK vintage — mainline `qualcommbe` is on 6.18) |
| Target string | `ipq53xx/generic`, board `qcom,ipq5332-ap-mi01.6` |
| Wi-Fi driver | **`qca_ol` / `umac` / `qdf` / `ipq_cnss2`** — Qualcomm out-of-tree qcawifi, **not** mac80211 |
| hostapd | `qca-hapd-supp` (Qualcomm fork, built **with `CONFIG_TESTING_OPTIONS`**) |
| Datapath | `qca_nss_ppe_*` + `ecm` hardware offload |
| Radio | PCIe endpoint `17cb:1109` (QCN9274) |
| Storage | eMMC `mmcblk0` ~7.6 GB (not NAND; single MTD partition `log`) |
| Packages | **721 installed, of which 117 are `gl-sdk4-*`** |

Captured from a running unit 2026-09-07.

## 🚨 Bit-for-bit recreation of stock is not achievable

| Layer | Public? | Where |
|---|---|---|
| OpenWrt base userspace | YES | `openwrt/openwrt` |
| Qualcomm QSDK — ipq53xx target, kernel 5.4, qcawifi, `qca-hapd-supp`, NSS/PPE | **NO** | licensee-only, not redistributable |
| GL support feed — 53-56 pkgs (nginx, lua*, mwan3, fullconenat ...) | YES | `gl-inet/gl-feeds` |
| GL application layer — `oui-httpd`, web UI, most `gl-sdk4-*` | **NO** | not published |

**GL publishes 3 of the 117 `gl-sdk4-*` packages** on this device (`edgerouter-status`, `fan`,
`hw-info`) — checked across branches `v4.9_be9300`, `common_v4.9` and `qsdk12.2`. That 97% gap is
also *why* the web-UI RPC handlers ship as stripped Lua 5.1 bytecode: there is no published source.

## The route that IS open

Not "mainline + GL's bits" — they cannot be mixed. qcawifi is an out-of-tree 5.4-era stack; mainline
uses **ath12k**, already in OpenWrt (`package/kernel/mac80211/patches/ath12k`). The real path is a
genuine mainline port, and the community is well into it — OpenWrt forum thread *"GL.iNet Flint 3
exploration (GL-BE9300, IPQ5332)"*, 68 posts, (snapshot read 2026-08-01, partial).

Their state at that snapshot: a `qualcommbe/ipq53xx` subtarget with **21 IPQ5332 patches**; boot,
flash, UART, USB, GPIO, LEDs, both radios and both Ethernet ports reaching *Link is Up 2.5Gbps/Full*.
Two blockers remained:

1. **No packet flow.** NSSCC branch CBCR `0x39b00580` reads `0x1` on mainline vs `0x501` on vendor —
   bits 8/10 (upstream SerDes clock domain alive) never light. Vendor's `qca-ssdk` performs a
   PPE/UNIPHY init step with no upstream equivalent.
2. **`ath12k` QCN9274 probe wedges a CPU** on an IPQ5332 host during MHI bringup.

Work goes on branch **`port/ipq53xx-be9300`** (worktree `~/openwrt-be9300`), based on `upstream/main`
so the series stays PR-shaped.

⚠️ Re-verify the thread before acting on any of this — our copy is a month old, and the
`qualcommax: qca_ppe:` commits landing on upstream/main right now touch adjacent code.

# Profile: ax1800-flint1

**GL.iNet GL-AX1800 "Flint"** — IPQ6000, MediaTek-free Qualcomm platform.

- **Target:** `qualcommax` / `ipq60xx`, device `glinet_gl-ax1800`
- **Upstream status:** ✅ **fully supported in mainline OpenWrt** —
  `target/linux/qualcommax/image/ipq60xx.mk:75` (`Device/glinet_gl-ax1800`),
  DTS `target/linux/qualcommax/dts/ipq6000-gl-ax1800.dts`.
  Seed validated against the real tree with `make defconfig` (2026-09-07):
  `CONFIG_TARGET_PROFILE` resolves to `DEVICE_glinet_gl-ax1800`.
- **Radios:** ath11k (in-tree mac80211). Nothing proprietary is needed to build a working image.

## 🚨 Bench units only

The AX1800 this profile was written for is **in production service with no out-of-band management**,
so a bad flash means physical recovery. **Do not build this for a live unit.**

There is also a known functional regression to be aware of before flashing any AX1800 that is doing
mesh work:

> **GL-AX1800: OpenWrt 24.10 breaks 802.11s** (works on 23.05)

A mainline image from this profile is therefore *expected* to break an 802.11s mesh. That is not a
defect in the profile — it is the bug below.

## Why the profile exists

That 802.11s regression is a **concrete, reproducible bug on a mainline-supported device**, which
makes it a genuine upstream contribution opportunity. Characterising it needs a build, a spare
AX1800, and a bisect between 23.05 and main.

```sh
./build.sh ax1800-flint1              # homelab flavor
./build.sh ax1800-flint1 --mainline   # pristine upstream, for the bisect
```

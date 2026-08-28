# Profile: wr3000p-mule

The Cudy **WR3000P v1** bench/test unit (the "mule", S/N …00800) used to develop and hardware-test
the WAN-LED work upstreamed as [openwrt/openwrt#24913](https://github.com/openwrt/openwrt/pull/24913).

- **Target:** mediatek / filogic, device `cudy_wr3000p-v1`
- **Packages:** full LuCI (see [`seed`](seed))
- **Public overlay:** none yet (`files/` empty)
- **Private overlay:** `$OPENWRT_PRIVATE/wr3000p-mule/files/` — carries the bench SSH key so a
  `sysupgrade` keeps agent access. Never committed to this public repo.

Build (homelab flavor, with the WR3000P fix + private overlay):
```sh
./build.sh wr3000p-mule
```
Pure-upstream comparison image (no patches, no overlay):
```sh
./build.sh wr3000p-mule --mainline
```

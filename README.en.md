# vermeer-gki-sukisu-susfs

Self-built **GKI 5.15.194** kernel for the **Redmi K70** (`vermeer` / SM8550) with
**SukiSU-Nova (built-in root) + SUSFS + KPM (KernelPatch)**. Only the kernel is
replaced — the stock `vendor_dlkm` modules keep working.

> Based on Google's AOSP ACK `kernel/common`, branch `android13-5.15`, commit
> `f4321180a397` — the very same commit the stock Redmi K70 `boot.img` was built from.
> The release string is kept identical to the vendor kernel:
> `5.15.194-android13-8-00019-gf4321180a397-ab15212794`

[中文说明](README.md) | English

---

## Features

| Item | Detail |
|---|---|
| Kernel | `5.15.194-android13-8-00019-gf4321180a397-ab15212794`, vermagic identical to stock |
| SukiSU-Nova | `builtin` branch, `CONFIG_KSU=y`, manager reports **GKI mode** |
| SUSFS v2.4.0 | `SUS_PATH` / `SUS_MOUNT` / `SUS_KSTAT` / `SUS_MAP` / `OPEN_REDIRECT` / `SPOOF_UNAME` / `SPOOF_CMDLINE_OR_BOOTCONFIG` / `HIDE_KSU_SUSFS_SYMBOLS` / `PRIORITY_UID_FILTER` / `ENABLE_LOG` all enabled |
| KPM | `CONFIG_KPM=y` plus a `kpimg` injection (`kptools -p -s 123`) |
| AVC log spoofing | enabled by default, freely toggleable in the manager (Settings → AVC log spoofing) |
| Vendor modules | kernel-only replacement: all 406 stock `vendor_dlkm` modules load unchanged |

Toolchain: official **Android clang 14.0.7 (`r450784e`)**, same as the vendor build.
Config: stock `gki_defconfig` plus `CONFIG_LTO_CLANG_THIN` (the vendor uses FullLTO;
the KMI/ABI is unaffected).

---

## Quick start

### Flash a prebuilt image (recommended)

```bat
:: only needed once, when coming from the stock ROM
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img

:: flash the kernel (active slot may differ; check `fastboot getvar current-slot`)
fastboot flash boot_b boot-vermeer-sukisu-susfs-kpm.img
fastboot reboot
```

> ⚠️ Always flash the `*-kpm.img` variant. KPM lives inside the boot image as a binary
> patch; flashing a plain kernel image makes the manager report "KPM not supported" again.

### Build from source

Requires Linux or WSL2 (Ubuntu 22.04+ is fine), ~30 GB free disk, ~12 GB RAM, network access.

```bash
git clone https://github.com/xzhaoran/vermeer-gki-sukisu-susfs.git
cd vermeer-gki-sukisu-susfs

./build/build.sh                                  # fetch sources + toolchain, patch, build Image
./build/package.sh /path/to/stock/boot.img        # repack boot.img + AnyKernel3 zip
./build/inject-kpm.sh release/boot-vermeer-sukisu-susfs.img /path/to/SukiSU-Nova.apk
```

Artifacts land in `.work/` and `release/`.

### Release artifacts (v1.0.0)

| File | SHA256 |
|---|---|
| `boot-vermeer-sukisu-susfs-kpm.img` | `eb4827903d2452079e5a10ad8e9259f81bf79a5d9cb485eb7beb93cc79d57791` |
| `boot-vermeer-sukisu-susfs.img` | `53e934f18f99b7f44b468cf58641769569f29410c0ecf2d9255bc70de7df0a97` |
| `AnyKernel3-vermeer-sukisu-susfs.zip` | `46ca81150cc74e49f62ba1ec45057eb06b5d3ae9147fe1b560f3e838fa528710` |
| `Image` | `640f87a501adbf56de27d5539fc0d385396428ba21d03571beec2b37f4a6eea0` |

Published images are built with `KBUILD_BUILD_USER=android` and `KBUILD_BUILD_HOST=build`,
so the kernel banner carries no personal identifiers.

---

## Repository layout

```
build/build.sh              one-shot build (download → patch → configure → compile)
build/package.sh            repack boot.img and produce the AnyKernel3 zip
build/inject-kpm.sh         inject kpimg on-device through adb + kptools
build/fragment.config       config fragment applied on top of gki_defconfig
build/patch_avc_compat.py   AVC-spoof feature compat shim (see "Design notes")
tools/repack_boot.py        boot.img repacker (preserves the AVB boot signature)
tools/extract_kpm.py        pull kptools / kpimg out of the SukiSU manager APK
anykernel3/anykernel.sh     AnyKernel3 config for vermeer
docs/FLASH.md               flashing, verification, rollback
docs/TROUBLESHOOTING.md     pitfalls we hit and how to diagnose them
docs/KPM.md                 how KPM injection works and how to redo it
```

---

## Design notes

### 1. Why the `builtin` branch and not `main`

SukiSU-Nova's **`main` branch has no `CONFIG_KSU_SUSFS`** — the native SUSFS
integration lives only on `builtin`. A kernel built from `main` (including the
`v3.0.0` tag) silently loses SUSFS.

The trade-off: `builtin` has no `KSU_FEATURE_AVC_SPOOF = 10003` that manager
v3.0.0 expects, so `build/patch_avc_compat.py` adds a small compat handler in
`kernel/policy/feature.c`.

### 2. Reading the AVC-spoof state (important pitfall)

`fs/susfs.c` defines `susfs_is_avc_log_spoofing_enabled` with
`DEFINE_STATIC_KEY_TRUE`, so always read the flag directly:

```c
/* correct */
*value = static_key_enabled(&susfs_is_avc_log_spoofing_enabled.key) ? 1 : 0;

/* wrong: static_branch_unlikely() is a jump-label site; with the opposite
   polarity it always reads 0, which shows up as "the switch does nothing" */
*value = static_branch_unlikely(&susfs_is_avc_log_spoofing_enabled) ? 1 : 0;
```

### 3. Why only the kernel

GKI 2.0 guarantees a stable ABI: a kernel built from the same `gki_defconfig`, with the
same toolchain and the same release string exports identical symbol CRCs, so the stock
`vendor_dlkm` modules keep loading (verified here: all 406 modules load).

### 4. KPM is not a compile-time switch

`CONFIG_KPM=y` only makes the kernel willing to service KPM requests; the actual
engine is **KernelPatch (`kpimg`)**, injected into the boot image as a binary patch.
Rebuilding the kernel therefore requires redoing the injection — see [docs/KPM.md](docs/KPM.md).

---

## Known limitations

- The AVB boot signature inside `boot.img` is stale (self-built kernels are unsigned), so
  **AVB verification must stay disabled**; OTA updates will fail — flash the stock boot/vbmeta first.
- An unlocked bootloader reports `ro.boot.verifiedbootstate=orange`; that is a system state a
  kernel cannot change. Hardware-backed Play Integrity needs PIF/TrickyStore-style tooling.
- Only the kernel is replaced; `vendor_dlkm` modules are untouched. If a specific module turns
  out to be CRC-sensitive, it has to be rebuilt and shipped as well.
- The KPM superkey uses KernelPatch's default `123` (see `docs/KPM.md` to change it).

---

## Credits & license

- [Google AOSP common kernel](https://android.googlesource.com/kernel/common) (GPL-2.0)
- [SukiSU-Nova](https://github.com/SukiSU-Nova/SukiSU-Nova) (GPL-3.0)
- [SUSFS / susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (GPL-2.0)
- [KernelPatch](https://github.com/bmax121/KernelPatch) (GPL-2.0)
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) (GPL-2.0)

Scripts and patches in this repository are released under **GPL-2.0**, see [LICENSE](LICENSE).

> Flashing is at your own risk.

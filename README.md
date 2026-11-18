# vermeer-gki-sukisu-susfs

中文 | [English](README.en.md)

Redmi K70（`vermeer` / SM8550）的 **GKI 5.15.194** 自编译内核：
**SukiSU-Nova（内置 root）+ SUSFS + KPM（KernelPatch）**，只替换内核、保留原厂 `vendor_dlkm` 模块。

> 本项目基于 Google AOSP ACK：`kernel/common` 分支 `android13-5.15`，提交 `f4321180a397`
> —— 与 Redmi K70 原厂 `boot.img` 内的内核是**同一个提交**。
> 内核版本字符串保持与官方一致：
> `5.15.194-android13-8-00019-gf4321180a397-ab15212794`

---

## 特性

| 功能 | 说明 |
|---|---|
| 内核版本 | `5.15.194-android13-8-00019-gf4321180a397-ab15212794`，vermagic 与原厂逐字一致 |
| SukiSU-Nova | `builtin` 分支，`CONFIG_KSU=y`，管理器显示 **GKI 模式** |
| SUSFS v2.4.0 | `SUS_PATH` / `SUS_MOUNT` / `SUS_KSTAT` / `SUS_MAP` / `OPEN_REDIRECT` / `SPOOF_UNAME` / `SPOOF_CMDLINE_OR_BOOTCONFIG` / `HIDE_KSU_SUSFS_SYMBOLS` / `PRIORITY_UID_FILTER` / `ENABLE_LOG` 全开 |
| KPM | `CONFIG_KPM=y` + `kpimg` 注入（`kptools -p -s 123`） |
| AVC 日志伪装 | 默认开启，且可在管理器「设置 → AVC 日志伪装」自由开关 |
| 原厂模块兼容 | 只替换 boot 里的 kernel，`vendor_dlkm` 的 406 个模块全部正常加载 |

编译参数：官方 `gki_defconfig` + `CONFIG_LTO_CLANG_THIN`（原厂为 FullLTO，KMI/ABI 不变），
工具链为 **Android clang 14.0.7 (r450784e)**，与原厂内核相同。

---

## 快速开始

### 只刷（推荐）

```bat
:: 首次从原厂系统过来：关闭 AVB 校验（只需一次）
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img

:: 刷内核（当前槽位是 b）
fastboot flash boot_b boot-vermeer-sukisu-susfs-kpm.img
fastboot reboot
```

> ⚠️ 必须刷 `*-kpm.img`：KPM 是二进制注入到 boot 镜像里的，普通内核镜像刷进去会让
> KPM 变回「内核不支持」。

### 从源码构建

需要 Linux 或 WSL2（Ubuntu 22.04+ 均可），约 30 GB 磁盘、12 GB 内存、联网。

```bash
git clone https://github.com/<you>/vermeer-gki-sukisu-susfs.git
cd vermeer-gki-sukisu-susfs

./build/build.sh                                  # 拉源码/工具链 → 打补丁 → 编译 Image
./build/package.sh /path/to/stock/boot.img        # 重打包 boot.img + AnyKernel3 zip
./build/inject-kpm.sh release/boot-vermeer-sukisu-susfs.img /path/to/SukiSU-Nova.apk
```

产物在 `.work/` 与 `release/`。

### 发布产物（v1.0.0）

| 文件 | SHA256 |
|---|---|
| `boot-vermeer-sukisu-susfs-kpm.img` | `eb4827903d2452079e5a10ad8e9259f81bf79a5d9cb485eb7beb93cc79d57791` |
| `boot-vermeer-sukisu-susfs.img` | `53e934f18f99b7f44b468cf58641769569f29410c0ecf2d9255bc70de7df0a97` |
| `AnyKernel3-vermeer-sukisu-susfs.zip` | `46ca81150cc74e49f62ba1ec45057eb06b5d3ae9147fe1b560f3e838fa528710` |
| `Image` | `640f87a501adbf56de27d5539fc0d385396428ba21d03571beec2b37f4a6eea0` |

发布镜像使用 `KBUILD_BUILD_USER=android`、`KBUILD_BUILD_HOST=build` 构建，内核字符串里不含构建者个人信息。

---

## 仓库结构

```
build/build.sh              一键编译（下载 → 打补丁 → 配置 → 编译）
build/package.sh            重打包 boot.img、生成 AnyKernel3 zip
build/inject-kpm.sh         通过 adb 在手机上用 kptools 注入 kpimg
build/fragment.config       在 gki_defconfig 之上追加的配置项
build/patch_avc_compat.py   AVC 日志伪装的 feature 兼容补丁（见「设计说明」）
tools/repack_boot.py        boot.img 重打包（内置自校验）
tools/extract_kpm.py        从 SukiSU 管理器 APK 提取 kptools / kpimg
anykernel3/anykernel.sh     AnyKernel3 配置（vermeer 适配）
docs/FLASH.md               刷机步骤与回滚
docs/TROUBLESHOOTING.md     踩过的坑与排查方法
docs/KPM.md                 KPM 的注入原理与重打流程
```

---

## 设计说明（为什么这么做）

### 1. 为什么用 `builtin` 分支而不是 `main`

SukiSU-Nova 的 **`main` 分支没有 `CONFIG_KSU_SUSFS`**，SUSFS 的原生集成只存在于
`builtin` 分支。用 `main`（含 v3.0.0 发布标签）编出来的内核会丢掉 SUSFS。

代价是 `builtin` 分支没有管理器 v3.0.0 使用的 `KSU_FEATURE_AVC_SPOOF = 10003`，
所以 `build/patch_avc_compat.py` 在 `kernel/policy/feature.c` 里补了一个兼容 handler。

### 2. AVC 日志伪装的读法（重要坑）

`fs/susfs.c` 里 `susfs_is_avc_log_spoofing_enabled` 用 `DEFINE_STATIC_KEY_TRUE` 定义，
**必须用 `static_key_enabled(&key.key)` 直接读标志位**：

```c
/* 正确 */
*value = static_key_enabled(&susfs_is_avc_log_spoofing_enabled.key) ? 1 : 0;

/* 错误：static_branch_unlikely() 是跳转标签站点，
   在极性与定义不一致时永远读到 0，表现为"能显示、点不动" */
*value = static_branch_unlikely(&susfs_is_avc_log_spoofing_enabled) ? 1 : 0;
```

### 3. 为什么只换 kernel

GKI 2.0 的 ABI 是稳定的：同 `gki_defconfig` + 同编译器 + 同版本字符串编译出的内核，
导出的符号 CRC 与原厂一致，`vendor_dlkm` 里的原厂模块可以直接继续用（本项目实测 406 个模块全部加载）。

### 4. KPM 不是编译开关

`CONFIG_KPM=y` 只是让内核愿意受理 KPM 请求；真正干活的是 **KernelPatch（kpimg）**，
由管理器把 `kpimg` 以二进制形式注入 boot 镜像。所以每次重编内核都要重打一次补丁，
详见 [docs/KPM.md](docs/KPM.md)。

---

## 已知限制

- `boot.img` 里的 AVB boot-signature 是旧的（自编译内核无厂商签名），**必须保持 AVB 校验关闭**；
  系统 OTA 会失败，升级前先刷回原厂 boot。
- 解锁 BL 后 `ro.boot.verifiedbootstate=orange`，这是系统级状态，内核改不了；
  Play Integrity 硬件级验证需要 PIF/TrickyStore 之类的方案。
- 只替换内核，未替换 `vendor_dlkm` 模块；若某机型的原厂模块对 CRC 敏感，需要一并替换。
- KPM 的 superkey 使用 KernelPatch 默认值 `123`（见 `docs/KPM.md`，可自行修改）。

---

## 致谢与许可

- [Google AOSP common kernel](https://android.googlesource.com/kernel/common)（GPL-2.0）
- [SukiSU-Nova](https://github.com/SukiSU-Nova/SukiSU-Nova)（GPL-3.0）
- [SUSFS / susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)（GPL-2.0）
- [KernelPatch](https://github.com/bmax121/KernelPatch)（GPL-2.0）
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3)（GPL-2.0）

本仓库的脚本与补丁以 **GPL-2.0** 发布，见 [LICENSE](LICENSE)。

> 刷机有风险，变砖自行负责。

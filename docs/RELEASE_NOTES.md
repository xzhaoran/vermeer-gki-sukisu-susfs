# v1.0.0 — vermeer GKI 5.15.194（SukiSU-Nova + SUSFS + KPM）

首个公开版本，面向 **Redmi K70（vermeer / SM8550）**，基于与官方同源的 GKI 内核构建。

## 内核

- 源码：AOSP ACK `android13-5.15`，提交 `f4321180a397`（与原厂 `boot.img` 内内核同一提交）
- 版本串：`5.15.194-android13-8-00019-gf4321180a397-ab15212794`，**vermagic 与原厂逐字一致**
- 工具链：Android clang 14.0.7（`r450784e`，与原厂相同）
- 配置：官方 `gki_defconfig` + `CONFIG_LTO_CLANG_THIN`（原厂 FullLTO，KMI/ABI 不变）
- 构建标识：`android@build`（中性）

## 功能

- **SukiSU-Nova**（`builtin` 分支 `4bec532`，GKI 内置模式）
- **SUSFS v2.4.0**：SUS_PATH / SUS_MOUNT / SUS_KSTAT / SUS_MAP / OPEN_REDIRECT / SPOOF_UNAME /
  SPOOF_CMDLINE_OR_BOOTCONFIG / HIDE_KSU_SUSFS_SYMBOLS / PRIORITY_UID_FILTER / ENABLE_LOG
- **KPM**：已注入 `kpimg`（superkey `123`）
- **AVC 日志伪装**：默认开启，可在管理器「设置 → AVC 日志伪装」自由开关
- 原厂 `vendor_dlkm` 模块无需替换（实测 406 个模块全部加载）

## 文件

| 文件 | 说明 | SHA256 |
|---|---|---|
| `boot-vermeer-sukisu-susfs-kpm.img` | **推荐**，含 KPM 注入，`fastboot flash boot_b` | `eb4827903d2452079e5a10ad8e9259f81bf79a5d9cb485eb7beb93cc79d57791` |
| `boot-vermeer-sukisu-susfs.img` | 不含 KPM 的干净镜像 | `53e934f18f99b7f44b468cf58641769569f29410c0ecf2d9255bc70de7df0a97` |
| `AnyKernel3-vermeer-sukisu-susfs.zip` | 卡刷包（内核同 Image，**不含** kpimg） | `46ca81150cc74e49f62ba1ec45057eb06b5d3ae9147fe1b560f3e838fa528710` |
| `Image` | 裸内核 | `640f87a501adbf56de27d5539fc0d385396428ba21d03571beec2b37f4a6eea0` |

## 刷入

```bat
fastboot --disable-verity --disable-verification flash vbmeta_b vbmeta.img   :: 仅首次
fastboot flash boot_b boot-vermeer-sukisu-susfs-kpm.img
fastboot reboot
```

回滚：

```bat
fastboot flash boot_b boot.img
fastboot flash vbmeta_b vbmeta.img
```

## 已知限制

- 只换内核，未换 `vendor_dlkm` 模块；
- AVB 校验必须保持关闭（自编译内核无厂商签名），OTA 会失败；
- 刷不带 kpimg 的镜像会让 KPM 变回「内核不支持」，需要重新 `./build/inject-kpm.sh`；
- 解锁 BL 的 `verifiedbootstate=orange` 无法通过内核改变。

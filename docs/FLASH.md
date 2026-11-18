# 刷机说明

## 前置条件

- Redmi K70（`vermeer`），bootloader 已解锁；
- Android platform-tools（`fastboot` / `adb`）；
- 同版本的原厂 `vbmeta.img` 和 `boot.img`（用于首刷关 AVB / 回滚）。

## 一、首次从原厂系统过来

```bat
fastboot devices
fastboot --disable-verity --disable-verification flash vbmeta_b vbmeta.img
fastboot flash boot_b boot-vermeer-sukisu-susfs-kpm.img
fastboot reboot
```

- 当前槽位不一定是 `b`，用 `fastboot getvar current-slot` 确认后把 `_b` 换成对应槽位；
  也可以直接写 `boot` / `vbmeta`，新版 fastboot 会自动带当前槽位。
- `--disable-verity --disable-verification` 只改 vbmeta 头里的标志，不动数据。
- 首次开机比平时慢（5–10 分钟），属正常。

## 二、后续更新内核

```bat
fastboot flash boot_<slot> boot-vermeer-sukisu-susfs-kpm.img
fastboot reboot
```

已经关过 AVB 的不需要再刷 vbmeta。

## 三、验证

1. 设置 → 关于手机 → 内核版本 应显示
   `5.15.194-android13-8-00019-gf4321180a397-ab15212794`
2. 安装 [SukiSU-Nova 管理器](https://github.com/SukiSU-Nova/SukiSU-Nova/releases)，
   打开应显示「已安装 / GKI 模式」；
3. KPM 页面应显示版本与模块列表（刷的是 `*-kpm.img` 时）；
4. 设置 → AVC 日志伪装 应可自由开关。

⚠️ **不要**使用管理器里的「安装 / 修补镜像」功能 —— 那是 LKM 模式，会覆盖本内核。

## 四、回滚

```bat
fastboot flash boot_<slot> boot.img        :: 原厂 boot
fastboot flash vbmeta_<slot> vbmeta.img    :: 原厂 vbmeta（恢复 AVB 校验）
```

## 五、注意事项

- **OTA 会失败**：系统升级前请先刷回原厂 boot + vbmeta。
- 只替换内核，`vendor_dlkm` 里的原厂模块保持不动（依赖 GKI 的 ABI 稳定性）。
- 刷普通内核（不带 kpimg）会让 KPM 变回「内核不支持」，需要重新执行
  `./build/inject-kpm.sh`。
- 解锁 BL 后 `ro.boot.verifiedbootstate=orange` 属系统状态，内核无法修改。

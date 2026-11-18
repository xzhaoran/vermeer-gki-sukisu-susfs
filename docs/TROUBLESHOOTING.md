# 踩坑记录 / 排查手册

这些都是本项目实际遇到的问题，按症状索引。

## 1. 管理器显示「内核不支持 KPM」

`CONFIG_KPM=y` 只是开关，真正的能力来自 KernelPatch（`kpimg`）。见 [KPM.md](KPM.md)。
刷了不带 kpimg 的镜像后必然回到这个状态，重新执行 `build/inject-kpm.sh` 即可。

## 2. 「AVC 日志伪装」能显示、点不动

先确认内核里是否有 `KSU_FEATURE_AVC_SPOOF`（id `10003`）。SukiSU-Nova 的 `builtin`
分支没有这个 feature（AVC 伪装走 SUSFS 命令），需要在 `kernel/policy/feature.c` 里补兼容
handler（本仓库 `build/patch_avc_compat.py`）。

补了 handler 之后如果仍然「点不动」，检查读状态的写法：

```c
/* 错：static_branch_unlikely 是跳转标签站点，极性不匹配时永远读到 0 */
*value = static_branch_unlikely(&susfs_is_avc_log_spoofing_enabled) ? 1 : 0;

/* 对：直接读 key.enabled */
*value = static_key_enabled(&susfs_is_avc_log_spoofing_enabled.key) ? 1 : 0;
```

排查命令（需要 root adb）：

```sh
adb root
adb shell /data/adb/ksud feature get avc_spoof      # 看内核侧真实值
adb shell /data/adb/ksud feature set avc_spoof 1
adb shell dmesg | grep -i 'avc_spoof'               # 看内核是否收到 SET
```

## 3. 用 SukiSU-Nova `main` / `v3.0.0` 标签编译，SUSFS 消失了

`main` 分支**没有** `CONFIG_KSU_SUSFS`，SUSFS 的原生集成只在 `builtin` 分支。
用 `main` 编出来的内核 `fs/Makefile` 里不会编 `susfs.o`。

判断方法：

```sh
grep -E '^CONFIG_(KSU|KSU_SUSFS|KPM)=' out/.config
```

`CONFIG_KSU_SUSFS` 缺失就说明选错分支了。

## 4. 内核版本字符串不对 / 模块加载失败

版本字符串必须与原厂完全一致（`5.15.194-android13-8-00019-gf4321180a397-ab15212794`），
否则 `vendor_dlkm` 的模块会因 vermagic 不匹配拒绝加载。

- 不要在有未提交改动、且带 `.git` 的树上构建，否则 `setlocalversion` 会追加 `-dirty`；
- 本项目通过 `make LOCALVERSION=...` 显式固定，构建脚本里有断言：

```sh
make -s O=out ARCH=arm64 LOCALVERSION="$LOCALVERSION" kernelrelease
```

## 5. SUSFS 补丁打不上

上游 `50_add_susfs_in_gki-android13-5.15.patch` 对这个提交通常只在两处失败，都是缺 include：

- `fs/namespace.c`：`<linux/susfs_def.h>` 与 `SUS_MOUNT` 的 extern 声明 + `CL_COPY_MNT_NS` 宏；
- `fs/proc/task_mmu.c`：`<linux/susfs_def.h>`。

`build/build.sh` 里已用 Python 自动补齐，并在最后检查没有残留 `.rej`。

## 6. 编译卡在某一步不动

`scripts/gcc-goto.sh` 之类的探测会读标准输入。用不继承终端的方式跑 make：

```sh
make ... < /dev/null
```

（本仓库脚本已在开头 `exec 0</dev/null`。）

## 7. kptools 报 `overload size of rest data`

这是正常提示：原 boot 镜像里 kernel 之后的 AVB boot-signature 区域比新内核需要的空间小，
kptools 会把剩余数据搬到新的页对齐位置。只要最后镜像大小不变、能正常开机即可。

## 8. 刷完 bootloop

按顺序回滚：

```bat
fastboot flash boot_<slot> boot.img
fastboot flash vbmeta_<slot> vbmeta.img
```

如果只是 AVB 校验失败（开机直接进 bootloader），先确认刷过
`fastboot --disable-verity --disable-verification flash vbmeta`。

## 9. 排查工具：root adb

内核里开了 `CONFIG_KSU_FEATURE_ADBROOT`，在管理器里启用「ADB Root」后：

```sh
adb root
adb shell id          # uid=0，SELinux 上下文 u:r:ksu:s0
adb shell dmesg | grep -iE 'kernelsu|susfs|feature'
```

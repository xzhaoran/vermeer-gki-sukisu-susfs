# KPM（Kernel Patch Module）说明

## KPM 不是编译开关

内核里 `CONFIG_KPM=y` 只是让 SukiSU 的后端愿意受理 KPM 请求；真正提供 KPM 能力的是
**KernelPatch** —— 一份以二进制形式注入内核镜像的代码（`kpimg`）。

内核侧的判断逻辑（`kernel/extension/kpm/kpm.c`）：

```c
fn = find_kernel_symbol_exact("__arm64_sys_truncate");
...
if (fn(&regs) != SUKISU_KPM_ABI_VERSION) return -EOPNOTSUPP;   /* 没有 KP 就是"不支持" */
```

所以：**只开 `CONFIG_KPM` 编出来的内核，管理器仍然显示「内核不支持 KPM」，必须再注入 kpimg。**

## 注入原理

管理器本身带了两样东西：

| 文件 | 来源 | 作用 |
|---|---|---|
| `libkptools.so` | APK 的 `lib/arm64-v8a/` | KernelPatch 的镜像补丁工具（aarch64 可执行） |
| `assets/kpm/kpimg` | APK 的 assets | 要注入的内核补丁负载 |

命令行（等价于管理器「KPM 补丁」按钮做的事）：

```sh
kptools -p -s <superkey> -i boot.img -k kpimg -o boot-kpm.img
```

- `-p` 打补丁（`-u` 撤销，`-r` 改 superkey）；
- `-s` 设置 superkey，KernelPatch 的超级调用凭据，默认 `123`；
- 输入是 Android boot 镜像（`ANDROID!` 魔数）时，kptools 会自动解包内核、打补丁、再打包。

补丁过程会给内核追加约 290 KB（kpimg），并把 kernel_size 更新到新的页对齐边界。

## 为什么每次重编内核都要重打

kpimg 是**写在 boot 镜像的内核代码里**的，不是独立分区。换了内核镜像（重新编译、
或者换成没打补丁的版本），kpimg 就没了，KPM 也随之失效。

本仓库的 `build/inject-kpm.sh` 就是把这个流程自动化（在手机上跑 kptools，再把
打好补丁的镜像拉回来）。

## 换 superkey

```sh
./build/inject-kpm.sh boot.img manager.apk      # 默认 123
SUPERKEY=你的密钥 ./build/inject-kpm.sh boot.img manager.apk
```

已注入的镜像可以只改 key：

```sh
kptools -r -s <新key> -i boot-kpm.img -o boot-kpm-new.img
```

## 不需要 KPM 的情况

日常 root、SUSFS 隐藏、模块挂载都不依赖 KPM，只有用到 `.kpm` 模块时才需要。

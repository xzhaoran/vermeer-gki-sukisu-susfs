#!/usr/bin/env bash
#
# Build the GKI 5.15.194 kernel for Redmi K70 (vermeer) with
# SukiSU-Nova (builtin) + SUSFS + KPM support.
#
# Everything is pinned: kernel commit, toolchain build, SukiSU commit.
# Run from the repository root or anywhere (paths are resolved from this file).
#
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-"$ROOT/.work"}
OUT=${OUT:-"$WORK/out"}
JOBS=${JOBS:-$(nproc)}

KERNEL_COMMIT=f4321180a3973d19b626b3eef51871199e4e1fac
KERNEL_URL="https://android.googlesource.com/kernel/common/+archive/${KERNEL_COMMIT}.tar.gz"

CLANG_DIR=clang-r450784e
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master-kernel-build-2022/${CLANG_DIR}.tar.gz"

SUSFS_BRANCH=gki-android13-5.15
SUSFS_URL="https://gitlab.com/simonpunk/susfs4ksu/-/archive/${SUSFS_BRANCH}/susfs4ksu-${SUSFS_BRANCH}.tar.gz"

SUKISU_URL=https://github.com/SukiSU-Nova/SukiSU-Nova
SUKISU_REF=4bec532d          # builtin 分支 2026-11-16，本项目验证过的提交

LOCALVERSION="-android13-8-00019-gf4321180a397-ab15212794"
KBUILD_USER=${KBUILD_USER:-android}
KBUILD_HOST=${KBUILD_HOST:-build}

KC="$WORK/kernel"            # kernel/common tree (repo root == common/)
KS="$WORK/KernelSU"
SUSFS="$WORK/susfs4ksu"
CLANG="$WORK/toolchains/$CLANG_DIR"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing host tool: $1"; }

# ---------------------------------------------------------------- 0. checks
log "checking host tools"
for t in curl tar git make bison flex bc rsync zip unzip python3 perl gcc; do need "$t"; done
df -Pk "$WORK" 2>/dev/null | awk 'NR==2 { if ($4 < 25*1024*1024) { print "warning: less than 25 GiB free under '"$WORK"'" } }'
mkdir -p "$WORK" "$OUT"

fetch() { # fetch <url> <outfile>
  local url=$1 out=$2
  [ -s "$out" ] && return 0
  log "download $(basename "$out")"
  curl -fL --retry 5 --retry-delay 5 --connect-timeout 30 -o "$out.part" "$url"
  mv "$out.part" "$out"
}

# ------------------------------------------------------- 1. source + tools
fetch "$KERNEL_URL" "$WORK/common.tar.gz"
if [ ! -f "$KC/Makefile" ]; then
  log "extract kernel source"
  rm -rf "$KC"; mkdir -p "$KC"
  tar xzf "$WORK/common.tar.gz" -C "$KC"
fi
grep -q '^SUBLEVEL = 194$' "$KC/Makefile" || die "unexpected kernel version in $KC/Makefile"

if [ ! -x "$CLANG/bin/clang" ]; then
  fetch "$CLANG_URL" "$WORK/$CLANG_DIR.tar.gz"
  log "extract toolchain"
  rm -rf "$CLANG"; mkdir -p "$CLANG"
  tar xzf "$WORK/$CLANG_DIR.tar.gz" -C "$CLANG"
  chmod +x "$CLANG/bin/"* 2>/dev/null || true
fi
"$CLANG/bin/clang" --version | grep -q '8508608' || log "warning: clang build id differs from the vendor kernel"

if [ ! -d "$SUSFS/kernel_patches" ]; then
  fetch "$SUSFS_URL" "$WORK/susfs.tar.gz"
  log "extract SUSFS"
  rm -rf "$SUSFS"; mkdir -p "$SUSFS"
  tar xzf "$WORK/susfs.tar.gz" -C "$SUSFS" --strip-components=1
fi

if [ ! -d "$KS/.git" ]; then
  log "clone SukiSU-Nova"
  git clone --quiet "$SUKISU_URL" "$KS"
fi
log "checkout SukiSU-Nova ${SUKISU_REF}"
git -C "$KS" fetch --quiet origin || true
git -C "$KS" checkout -q -f "$SUKISU_REF"

# --------------------------------------------------- 2. KernelSU into tree
log "hooking KernelSU into the kernel tree"
ln -sfn ../../KernelSU/kernel "$KC/drivers/kernelsu"
grep -q kernelsu "$KC/drivers/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KC/drivers/Makefile"
grep -q 'drivers/kernelsu/Kconfig' "$KC/drivers/Kconfig" || \
  sed -i '/^endmenu/i\source "drivers/kernelsu/Kconfig"' "$KC/drivers/Kconfig"

# --------------------------------------------------------- 3. SUSFS patch
log "applying SUSFS kernel patch (${SUSFS_BRANCH})"
cp -f "$SUSFS/kernel_patches/fs/susfs.c"              "$KC/fs/susfs.c"
cp -f "$SUSFS/kernel_patches/include/linux/susfs.h"   "$KC/include/linux/susfs.h"
cp -f "$SUSFS/kernel_patches/include/linux/susfs_def.h" "$KC/include/linux/susfs_def.h"

( cd "$KC" && patch -p1 --batch --forward -N --no-backup-if-mismatch \
    < "$SUSFS/kernel_patches/50_add_susfs_in_${SUSFS_BRANCH}.patch" ) || true

# The upstream patch expects a couple of include blocks this tree spells
# differently.  Add them by hand, then make sure nothing was left unapplied.
python3 - "$KC" <<'PY'
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(path, anchor, block, present):
    p = root / path
    s = p.read_text()
    if present in s:
        return False
    if anchor not in s:
        print(f"  warning: anchor missing in {path}, skipped")
        return False
    p.write_text(s.replace(anchor, anchor + block, 1))
    return True

changed = 0
changed += patch(
    "fs/namespace.c",
    "#include <linux/mnt_idmapping.h>\n",
    "#ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs_def.h>\n#endif // CONFIG_KSU_SUSFS\n",
    "susfs_def.h",
)
changed += patch(
    "fs/namespace.c",
    '#include "internal.h"\n',
    "\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n"
    "extern bool susfs_is_current_ksu_domain(void);\n"
    "extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n\n"
    "#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */\n"
    "#endif // CONFIG_KSU_SUSFS_SUS_MOUNT\n",
    "CL_COPY_MNT_NS BIT(25)",
)
changed += patch(
    "fs/proc/task_mmu.c",
    "#include <linux/pkeys.h>\n",
    "#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n"
    "#include <linux/susfs_def.h>\n#endif\n",
    "susfs_def.h",
)
print(f"  manual SUSFS include fixes applied: {changed}")
PY

if find "$KC" -name '*.rej' -print -quit | grep -q .; then
  find "$KC" -name '*.rej' -print
  die "SUSFS patch left rejects (upstream patch drifted, fix manually)"
fi
find "$KC" -name '*.rej' -delete
find "$KC" -name '*.orig' -delete
grep -q '^obj-$(CONFIG_KSU_SUSFS) += susfs.o' "$KC/fs/Makefile" || die "fs/Makefile has no susfs.o"

# --------------------------------------------------- 4. AVC spoof compat
log "applying AVC-spoof feature compat patch"
python3 "$ROOT/build/patch_avc_compat.py" "$KS" "$KC"

# ------------------------------------------------------------- 5. config
log "configuring (gki_defconfig + fragment)"
rm -rf "$OUT"
MK=(make O="$OUT" ARCH=arm64 LLVM=1 LOCALVERSION="$LOCALVERSION")
cd "$KC"
PATH="$CLANG/bin:$PATH" "${MK[@]}" gki_defconfig >/dev/null
while read -r line; do
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac
  # scripts/config is a POSIX shell script, not python
  "$KC/scripts/config" --file "$OUT/.config" $line
done < "$ROOT/build/fragment.config"
PATH="$CLANG/bin:$PATH" "${MK[@]}" olddefconfig >/dev/null

for opt in CONFIG_KSU CONFIG_KSU_SUSFS CONFIG_KPM CONFIG_LTO_CLANG_THIN; do
  grep -q "^$opt=y$" "$OUT/.config" || die "$opt did not survive olddefconfig"
done

# -------------------------------------------------------------- 6. build
REL=$(PATH="$CLANG/bin:$PATH" "${MK[@]}" -s kernelrelease)
[ "$REL" = "5.15.194${LOCALVERSION}" ] || die "unexpected kernelrelease: $REL"

log "building Image (jobs=$JOBS)"
PATH="$CLANG/bin:$PATH" "${MK[@]}" -j"$JOBS" \
  KBUILD_BUILD_USER="$KBUILD_USER" KBUILD_BUILD_HOST="$KBUILD_HOST" \
  Image > "$WORK/build.log" 2>&1 || {
    grep -nE 'error:|Error [0-9]|fatal error' "$WORK/build.log" | tail -30 || true
    tail -40 "$WORK/build.log"
    die "kernel build failed (full log: $WORK/build.log)"
  }

IMG="$OUT/arch/arm64/boot/Image"
[ -s "$IMG" ] || die "no Image produced"
cp -f "$IMG" "$WORK/Image"
log "done: $WORK/Image"
grep -m1 '^Linux version' <(strings "$IMG") || true

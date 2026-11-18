#!/usr/bin/env bash
#
# Inject the KernelPatch image (kpimg) into a boot image, which is what actually
# enables KPM.  Requires an Android device with USB debugging (root not needed
# for the patching itself; adb shell is enough).
#
#   ./build/inject-kpm.sh release/boot-vermeer-sukisu-susfs.img [manager.apk]
#
# The manager APK is only needed the first time, to extract kptools/kpimg.
#
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-"$ROOT/.work"}
ADB=${ADB:-adb}
BOOT=${1:-}
APK=${2:-}
SUPERKEY=${SUPERKEY:-123}

[ -n "$BOOT" ] || { echo "usage: $0 <boot.img> [SukiSU-Nova.apk]" >&2; exit 1; }
[ -f "$BOOT" ] || { echo "no such file: $BOOT" >&2; exit 1; }

TOOLS="$WORK/kpm-tools"
if [ ! -x "$TOOLS/kptools" ] || [ ! -f "$TOOLS/kpimg" ]; then
  [ -n "$APK" ] || {
    echo "kptools/kpimg not extracted yet; pass the SukiSU-Nova manager APK as 2nd argument" >&2
    exit 1
  }
  python3 "$ROOT/tools/extract_kpm.py" "$APK" "$TOOLS"
fi

command -v "$ADB" >/dev/null || { echo "adb not found (set ADB=/path/to/adb)" >&2; exit 1; }
"$ADB" get-state >/dev/null 2>&1 || { echo "no adb device" >&2; exit 1; }

TMP=/data/local/tmp/kpm
"$ADB" shell "mkdir -p $TMP"
"$ADB" push "$TOOLS/kptools" "$TMP/kptools" >/dev/null
"$ADB" push "$TOOLS/kpimg"   "$TMP/kpimg"   >/dev/null
"$ADB" push "$BOOT"          "$TMP/boot.img" >/dev/null

echo "==> kptools -p -s $SUPERKEY (on device)"
"$ADB" shell "chmod 755 $TMP/kptools && cd $TMP && rm -f boot-kpm.img && \
  ./kptools -p -s $SUPERKEY -i boot.img -k kpimg -o boot-kpm.img"

OUT="${BOOT%.img}-kpm.img"
[ "$OUT" = "$BOOT" ] && OUT="$BOOT.kpm.img"
"$ADB" pull "$TMP/boot-kpm.img" "$OUT" >/dev/null
"$ADB" shell "rm -rf $TMP"

echo
echo "patched image: $OUT"
sha256sum "$OUT"
echo "flash it with: fastboot flash boot_b $OUT"

#!/usr/bin/env bash
#
# Repack the stock boot.img with the freshly built Image and produce the
# AnyKernel3 flashable zip.
#
#   ./build/package.sh /path/to/stock/boot.img
#
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-"$ROOT/.work"}
STOCK_BOOT=${1:-}
[ -n "$STOCK_BOOT" ] || { echo "usage: $0 <stock boot.img>" >&2; exit 1; }
[ -f "$STOCK_BOOT" ] || { echo "no such file: $STOCK_BOOT" >&2; exit 1; }
[ -f "$WORK/Image" ] || { echo "build first: ./build/build.sh" >&2; exit 1; }

OUT_DIR=${OUT_DIR:-"$ROOT/release"}
mkdir -p "$OUT_DIR"

echo "==> repacking boot.img"
python3 "$ROOT/tools/repack_boot.py" "$STOCK_BOOT" "$WORK/Image" "$OUT_DIR/boot-vermeer-sukisu-susfs.img"

echo "==> staging AnyKernel3"
AK="$WORK/AnyKernel3"
if [ ! -d "$AK" ]; then
  git clone --depth 1 --quiet https://github.com/osm0sis/AnyKernel3 "$AK"
fi
rm -rf "$AK/.git" "$AK/.github" "$AK/README.md"
cp -f "$ROOT/anykernel3/anykernel.sh" "$AK/anykernel.sh"
cp -f "$WORK/Image" "$AK/Image"
chmod 755 "$AK/META-INF/com/google/android/update-binary" "$AK/tools/"*

ZIP="$OUT_DIR/AnyKernel3-vermeer-sukisu-susfs.zip"
rm -f "$ZIP"
( cd "$AK" && zip -r9 "$ZIP" . -x '.git*' >/dev/null )

echo
sha256sum "$OUT_DIR"/*.img "$ZIP"
echo
echo "note: neither artifact contains the KPM (kpimg) patch."
echo "      run ./build/inject-kpm.sh on the boot image if you want KPM support."

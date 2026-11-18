#!/usr/bin/env python3
"""Repack an Android boot image (header v4) with a new kernel Image.

    repack_boot.py <stock boot.img> <kernel Image> <output boot.img>

Only the kernel payload and the `kernel_size` field are rewritten; the header,
cmdline, page size and the trailing AVB "boot signature" blob are preserved at
their page-aligned offsets.  The output keeps the exact size of the input so it
can be flashed with `fastboot flash boot[_a|_b]`.

Layout assumed (matches the Redmi K70 stock image):

    0x0000            boot_img_hdr_v4 (1584 B, padded to one 4096 page)
    0x1000            kernel (kernel_size bytes)
    page-aligned end  AVB0 boot signature / footer / zero padding
"""
import hashlib
import pathlib
import struct
import sys

PAGE = 4096


def align_up(n: int) -> int:
    return (n + PAGE - 1) // PAGE * PAGE


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    src, img, dst = map(pathlib.Path, sys.argv[1:4])

    orig = src.read_bytes()
    if orig[:8] != b"ANDROID!":
        raise SystemExit(f"not an Android boot image: {src}")
    kernel_size, ramdisk_size, os_version, _ = struct.unpack("<IIII", orig[8:24])
    header_version = struct.unpack("<I", orig[40:44])[0]
    if header_version < 3:
        raise SystemExit(f"unsupported boot header version {header_version}")

    old_tail_off = align_up(PAGE + kernel_size)
    tail = orig[old_tail_off:]

    kernel = img.read_bytes()
    print(f"stock : hdr v{header_version} kernel={kernel_size} ramdisk={ramdisk_size} "
          f"total={len(orig)} tail@{old_tail_off:#x} ({len(tail)} B, {tail[:4]!r})")
    print(f"new   : {len(kernel)} bytes ({len(kernel)/1048576:.1f} MiB)")

    header = bytearray(orig[:PAGE])
    struct.pack_into("<I", header, 8, len(kernel))

    out = bytearray(header) + kernel
    out += b"\0" * (align_up(len(out)) - len(out))
    out += tail
    if len(out) < len(orig):
        out += b"\0" * (len(orig) - len(out))
    elif len(out) > len(orig):
        print(f"note  : image grew to {len(out)} bytes (boot partition is larger, fine)")

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(out)
    print(f"wrote : {dst} ({len(out)} B)")
    print("sha256:", hashlib.sha256(out).hexdigest())


if __name__ == "__main__":
    main()

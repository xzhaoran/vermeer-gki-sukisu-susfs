#!/usr/bin/env python3
"""Extract the KPM injection tools from a SukiSU-Nova manager APK.

    extract_kpm.py <SukiSU-Nova.apk> <output-dir>

Produces <output-dir>/kptools (aarch64 ELF, renamed from libkptools.so) and
<output-dir>/kpimg (the KernelPatch image bundled as assets/kpm/kpimg).
"""
import pathlib
import sys
import zipfile


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    apk, outdir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(apk) as z:
        libs = [n for n in z.namelist() if n.endswith("libkptools.so")]
        if not libs:
            raise SystemExit("libkptools.so not found in APK (wrong APK?)")
        kptools = z.read(libs[0])
        kpimg = z.read("assets/kpm/kpimg")

    (outdir / "kptools").write_bytes(kptools)
    (outdir / "kpimg").write_bytes(kpimg)
    print(f"kptools: {len(kptools)} bytes from {libs[0]}")
    print(f"kpimg  : {len(kpimg)} bytes")
    if kpimg[:2] != b"KP":
        print("warning: kpimg does not start with the KP magic")


if __name__ == "__main__":
    main()

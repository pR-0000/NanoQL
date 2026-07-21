#!/usr/bin/env python3
"""Download and verify the third-party QSoundZ music disk."""

from __future__ import annotations

import argparse
import hashlib
import shutil
import urllib.request
import zipfile
from pathlib import Path


DOWNLOAD_URL = "https://frummel.org/~weedz/atari/prods/ql/qsoundz.zip"
ARCHIVE_SHA256 = "DB40CBEDC46D1FDC538DC59D179A0846C48E90A98C59C6E57B51EBFA579B77EB"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Download the freeware QSoundZ music disk for Sinclair QL."
    )
    parser.add_argument(
        "--output", type=Path, default=Path("downloads/qsoundz"),
        help="local extraction folder (default: downloads/qsoundz)",
    )
    parser.add_argument(
        "--sd-root", type=Path,
        help="optionally copy QSoundZ.mdv to this microSD root",
    )
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / "qsoundz.zip"
    print(f"Downloading QSoundZ from {DOWNLOAD_URL}...")
    with urllib.request.urlopen(DOWNLOAD_URL, timeout=60) as response:
        archive.write_bytes(response.read())

    digest = hashlib.sha256(archive.read_bytes()).hexdigest().upper()
    if digest != ARCHIVE_SHA256:
        archive.unlink(missing_ok=True)
        raise RuntimeError(
            f"QSoundZ archive checksum mismatch: expected {ARCHIVE_SHA256}, got {digest}."
        )

    with zipfile.ZipFile(archive) as package:
        members = {Path(name).name.lower(): name for name in package.namelist()}
        for required in ("qsoundz.mdv", "qsoundz.txt"):
            if required not in members:
                raise RuntimeError(f"QSoundZ archive does not contain {required}.")
            destination = args.output / required
            with package.open(members[required]) as source, destination.open("wb") as target:
                shutil.copyfileobj(source, target)

    image = args.output / "qsoundz.mdv"
    if image.stat().st_size != 174_930:
        raise RuntimeError("QSoundZ Microdrive image has an unexpected size.")

    print(f"Verified QSoundZ image: {image.resolve()}")
    if args.sd_root is not None:
        if not args.sd_root.is_dir():
            raise RuntimeError(f"microSD root does not exist: {args.sd_root}")
        destination = args.sd_root / "QSoundZ.mdv"
        shutil.copyfile(image, destination)
        print(f"Copied to microSD: {destination}")

    print("Select QSoundZ.mdv as Microdrive 1 in the F12 overlay, then enter:")
    print("LRUN mdv1_boot")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

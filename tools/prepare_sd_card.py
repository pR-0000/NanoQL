#!/usr/bin/env python3
"""Prepare QL.rom and its FPGA Companion auto-mount file on microSD."""

from __future__ import annotations

import argparse
import hashlib
import shutil
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("rom", type=Path, help="48 KiB or 64 KiB QL ROM")
    parser.add_argument("destination", type=Path, help="mounted microSD root")
    args = parser.parse_args()

    if not args.rom.is_file():
        parser.error(f"ROM does not exist: {args.rom}")
    if not args.destination.is_dir():
        parser.error(f"destination is not a mounted directory: {args.destination}")
    if args.rom.stat().st_size not in (49152, 65536):
        parser.error("QL ROM must contain exactly 49,152 or 65,536 bytes")

    output = args.destination / "QL.rom"
    config = args.destination / "nanoql.ini"
    shutil.copyfile(args.rom, output)
    config.write_bytes(b"drive0 = /sd/QL.rom\n")
    digest = hashlib.sha256(output.read_bytes()).hexdigest().upper()
    print(f"Prepared: {output}")
    print(f"Prepared: {config}")
    print(f"Size: {output.stat().st_size} bytes")
    print(f"SHA-256: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

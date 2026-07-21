#!/usr/bin/env python3
"""Prepare QL.rom and its FPGA Companion auto-mount file on microSD."""

from __future__ import annotations

import argparse
import hashlib
import shutil
from pathlib import Path

from nanoql_drive import build_qlay_image, collect_drive_files


def update_defaults(config: Path, mount_mdv1: bool, mount_qsound: bool) -> None:
    lines = config.read_text(encoding="ascii").splitlines() if config.exists() else []
    replacements = {"drive0": "drive0 = /sd/QL.rom"}
    if mount_mdv1:
        replacements["drive2"] = "drive2 = /sd/NanoQL/Drive1/MDV1.mdv"
    if mount_qsound:
        replacements["drive3"] = "drive3 = /sd/QSound.rom"
    managed_keys = {"drive0", "drive2", "drive3"}
    updated: list[str] = []
    replaced: set[str] = set()
    for line in lines:
        key = line.lstrip().partition("=")[0].strip().lower()
        if key not in managed_keys:
            updated.append(line)
        elif key in replacements and key not in replaced:
            updated.append(replacements[key])
            replaced.add(key)
    for key, replacement in reversed(tuple(replacements.items())):
        if key not in replaced:
            updated.insert(0, replacement)
    config.write_text("\n".join(updated) + "\n", encoding="ascii")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("rom", type=Path, help="48 KiB or 64 KiB QL ROM")
    parser.add_argument("destination", type=Path, help="mounted microSD root")
    parser.add_argument(
        "--mdv-folder", type=Path,
        help="optional desktop folder to convert and auto-mount as MDV1",
    )
    parser.add_argument(
        "--mdv-name", default="NANOQL", help="QL Microdrive medium name"
    )
    parser.add_argument(
        "--qsound-rom", type=Path,
        help="optional 8 KiB QSound expansion ROM",
    )
    args = parser.parse_args()

    if not args.rom.is_file():
        parser.error(f"ROM does not exist: {args.rom}")
    if not args.destination.is_dir():
        parser.error(f"destination is not a mounted directory: {args.destination}")
    if args.rom.stat().st_size not in (49152, 65536):
        parser.error("QL ROM must contain exactly 49,152 or 65,536 bytes")
    if args.mdv_folder is not None and not args.mdv_folder.is_dir():
        parser.error(f"MDV1 source is not a directory: {args.mdv_folder}")
    if args.qsound_rom is not None:
        if not args.qsound_rom.is_file():
            parser.error(f"QSound ROM does not exist: {args.qsound_rom}")
        if args.qsound_rom.stat().st_size != 8192:
            parser.error("QSound ROM must contain exactly 8,192 bytes")

    output = args.destination / "QL.rom"
    config = args.destination / "nanoql.ini"
    drive1 = args.destination / "NanoQL" / "Drive1"
    microdrives = args.destination / "NanoQL" / "Microdrives"
    qsound_output = args.destination / "QSound.rom"
    shutil.copyfile(args.rom, output)
    if args.qsound_rom is not None:
        shutil.copyfile(args.qsound_rom, qsound_output)
    drive1.mkdir(parents=True, exist_ok=True)
    microdrives.mkdir(parents=True, exist_ok=True)
    mdv_image = drive1 / "MDV1.mdv"
    if args.mdv_folder is not None:
        files = collect_drive_files(args.mdv_folder, args.mdv_folder / "MDV1.mdv")
        mdv_image.write_bytes(build_qlay_image(files, args.mdv_name))
        print(f"Prepared: {mdv_image} ({len(files)} file(s))")
    update_defaults(config, mdv_image.is_file(), qsound_output.is_file())
    digest = hashlib.sha256(output.read_bytes()).hexdigest().upper()
    print(f"Prepared: {output}")
    print(f"Prepared: {config}")
    print(f"Prepared: {drive1}")
    print(f"Size: {output.stat().st_size} bytes")
    print(f"SHA-256: {digest}")
    if qsound_output.is_file():
        print(f"Prepared: {qsound_output} ({qsound_output.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

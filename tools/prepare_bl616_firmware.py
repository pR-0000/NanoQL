#!/usr/bin/env python3
"""Prepare the pinned NanoQL BL616 firmware package on any desktop OS."""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path


RELEASE_TAG = "v1.4.22"
RELEASE_BASE = (
    "https://github.com/MiSTle-Dev/FPGA-Companion/releases/download/"
    + RELEASE_TAG
)
FLASHCUBE_URL = (
    "https://github.com/MiSTle-Dev/.github/wiki/.assets/"
    "bouffalo_flash_cube-1.1.zip"
)
DOWNLOADS = (
    (
        "bl616_bootloader_0x20000_nano20k_signed.bin",
        RELEASE_BASE + "/bl616_bootloader_0x20000_nano20k_signed.bin",
        "1B5D0ED698A3F2BF0B9D4F72D242868DA993E737BBEA0C8288267B69B73FBC12",
    ),
    (
        "bl616_fpga_partner_nano20k.bin",
        RELEASE_BASE + "/bl616_fpga_partner_nano20k.bin",
        "BC5B1F733A13562C898FF66B540038C116C3D77CA202D0AFEBD1E7AF1C3B3203",
    ),
    (
        "fpga_companion_nano20k.bin",
        RELEASE_BASE + "/fpga_companion_nano20k.bin",
        "D8DEBB481F611C599AAE2877E1B92A3611250F23D0A0ACF36BB692A55FA89741",
    ),
    (
        "bl616_fpga_partner_nano20k_v3923.bin",
        RELEASE_BASE + "/bl616_fpga_partner_nano20k_v3923.bin",
        "BC5B1F733A13562C898FF66B540038C116C3D77CA202D0AFEBD1E7AF1C3B3203",
    ),
    (
        "fpga_companion_nano20k_v3923.bin",
        RELEASE_BASE + "/fpga_companion_nano20k_v3923.bin",
        "07AD01E6260BA6387F2215EDB7E20D630D50A32A03436CEF45A61A1DD1AB308A",
    ),
)
FLASHCUBE_SHA256 = (
    "2FD7EA7FBE4499CC1897145FDDE74E5551BDDCD27C68115BF6A065FDBD92B181"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def verified_download(url: str, destination: Path, expected: str, force: bool) -> None:
    if destination.exists() and not force and sha256(destination) == expected:
        print(f"Verified cached file: {destination}")
        return

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".download")
    temporary.unlink(missing_ok=True)
    print(f"Downloading {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "NanoQL"})
    with urllib.request.urlopen(request) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output)

    actual = sha256(temporary)
    if actual != expected:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(
            f"SHA-256 mismatch for {url}: expected {expected}, got {actual}"
        )
    os.replace(temporary, destination)
    print(f"Verified SHA-256: {actual}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--launch", action="store_true", help="launch FlashCube on Windows")
    parser.add_argument("--force-download", action="store_true")
    parser.add_argument(
        "--revision",
        choices=("both", "3921", "3923"),
        default="both",
        help="prepare firmware for one board revision or both",
    )
    parser.add_argument(
        "--with-flashcube",
        action="store_true",
        help="download the Windows FlashCube archive on non-Windows hosts",
    )
    parser.add_argument(
        "--link-3921",
        type=Path,
        help="locally built nanoql_link_nano20k.bin",
    )
    parser.add_argument(
        "--link-3923",
        type=Path,
        help="locally built nanoql_link_nano20k_v3923.bin",
    )
    parser.add_argument(
        "--unified-3921",
        type=Path,
        help="locally built nanoql_companion_nano20k.bin",
    )
    parser.add_argument(
        "--unified-3923",
        type=Path,
        help="locally built nanoql_companion_nano20k_v3923.bin",
    )
    args = parser.parse_args()

    repository = Path(__file__).resolve().parent.parent
    cache = repository / "private" / "bl616"
    package = cache / "flash-package"
    package.mkdir(parents=True, exist_ok=True)

    for name, url, expected in DOWNLOADS:
        verified_download(url, package / name, expected, args.force_download)

    configurations_by_revision = {
        "3921": (
            ("flash_nano20k_3921.ini", "1_NORMAL_3921_partner_auto.ini"),
            ("flash_nano20k_3921_companion_only.ini", "2_TEST_3921_companion_only.ini"),
        ),
        "3923": (
            ("flash_nano20k_3923.ini", "1_NORMAL_3923_partner_auto.ini"),
            ("flash_nano20k_3923_companion_only.ini", "2_TEST_3923_companion_only.ini"),
        ),
    }
    revisions = ("3921", "3923") if args.revision == "both" else (args.revision,)
    configurations = tuple(
        item for revision in revisions for item in configurations_by_revision[revision]
    )
    for stale_name in (
        "flash_nano20k.ini",
        "flash_nano20k_unconditional.ini",
        "flash_nano20k_companion_only.ini",
        "1_NORMAL_partner_auto.ini",
        "2_TEST_companion_only.ini",
        "1_NORMAL_3921_partner_auto.ini",
        "2_TEST_3921_companion_only.ini",
        "1_NORMAL_3923_partner_auto.ini",
        "2_TEST_3923_companion_only.ini",
        "3_LINK_3921_usb_cdc.ini",
        "3_LINK_3923_usb_cdc.ini",
        "4_NANOQL_3921_unified.ini",
        "4_NANOQL_3923_unified.ini",
        "nanoql_link_nano20k.bin",
        "nanoql_link_nano20k_v3923.bin",
        "nanoql_companion_nano20k.bin",
        "nanoql_companion_nano20k_v3923.bin",
    ):
        (package / stale_name).unlink(missing_ok=True)
    for source_name, destination_name in configurations:
        shutil.copy2(
            repository / "firmware" / "bl616" / source_name,
            package / destination_name,
        )

    link_firmware = {
        "3921": (
            args.link_3921,
            "nanoql_link_nano20k.bin",
            "flash_nano20k_3921_link.ini",
            "3_LINK_3921_usb_cdc.ini",
        ),
        "3923": (
            args.link_3923,
            "nanoql_link_nano20k_v3923.bin",
            "flash_nano20k_3923_link.ini",
            "3_LINK_3923_usb_cdc.ini",
        ),
    }
    for revision in revisions:
        source, firmware_name, config_source, config_name = link_firmware[revision]
        if source is None:
            continue
        if not source.is_file():
            raise FileNotFoundError(source)
        shutil.copy2(source, package / firmware_name)
        shutil.copy2(repository / "firmware" / "bl616" / config_source, package / config_name)

    unified_firmware = {
        "3921": (
            args.unified_3921,
            "nanoql_companion_nano20k.bin",
            "flash_nano20k_3921_unified.ini",
            "4_NANOQL_3921_unified.ini",
        ),
        "3923": (
            args.unified_3923,
            "nanoql_companion_nano20k_v3923.bin",
            "flash_nano20k_3923_unified.ini",
            "4_NANOQL_3923_unified.ini",
        ),
    }
    for revision in revisions:
        source, firmware_name, config_source, config_name = unified_firmware[revision]
        if source is None:
            continue
        if not source.is_file():
            raise FileNotFoundError(source)
        shutil.copy2(source, package / firmware_name)
        shutil.copy2(repository / "firmware" / "bl616" / config_source, package / config_name)

    flashcube_executable: Path | None = None
    is_windows = platform.system() == "Windows"
    if is_windows or args.with_flashcube:
        archive = cache / "bouffalo_flash_cube-1.1.zip"
        verified_download(
            FLASHCUBE_URL, archive, FLASHCUBE_SHA256, args.force_download
        )
        tool_root = cache / "flashcube"
        candidates = list(tool_root.rglob("BLFlashCube.exe"))
        if not candidates:
            print(f"Extracting BouffaloLabFlashCube to {tool_root}")
            tool_root.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(archive) as source:
                source.extractall(tool_root)
            candidates = list(tool_root.rglob("BLFlashCube.exe"))
        if not candidates:
            raise RuntimeError("BLFlashCube.exe was not found after extraction")
        flashcube_executable = candidates[0]

    print("\nBL616 package ready.")
    print(f"Release: {RELEASE_TAG}")
    for revision in revisions:
        print(f"Revision {revision} normal: {package / f'1_NORMAL_{revision}_partner_auto.ini'}")
        print(f"Revision {revision} test:   {package / f'2_TEST_{revision}_companion_only.ini'}")
        if link_firmware[revision][0] is not None:
            print(f"Revision {revision} link:   {package / f'3_LINK_{revision}_usb_cdc.ini'}")
        if unified_firmware[revision][0] is not None:
            print(f"Revision {revision} NanoQL: {package / f'4_NANOQL_{revision}_unified.ini'}")
    print("\nNORMAL keeps the Gowin programmer when USB data is connected.")
    print("To run Companion with NORMAL, boot the FPGA from its Flash and power")
    print("the board from USB without a data host. TEST disables the programmer")
    print("and runs Companion even while a PC is connected.")
    if flashcube_executable:
        print(f"FlashCube: {flashcube_executable}")
    else:
        print("FlashCube is Windows-only; the verified firmware package is ready.")

    if args.launch:
        if not is_windows or not flashcube_executable:
            raise RuntimeError("--launch is only supported on Windows")
        subprocess.Popen([str(flashcube_executable)], cwd=package)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1)

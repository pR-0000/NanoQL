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
NANOQL_RELEASE_TAG = "v0.3.1"
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
BFLB_MCU_TOOL_PACKAGE = "bflb-mcu-tool-uart"
BFLB_MCU_TOOL_VERSION = "1.10.1"
TELNETLIB_BACKPORT_PACKAGE = "standard-telnetlib==3.13.0"
BL616_APPLICATION_OFFSET = 0x20000


def install_python_packages(*packages: str) -> None:
    command = [sys.executable, "-m", "pip", "install", *packages]
    try:
        subprocess.check_call(command)
    except subprocess.CalledProcessError:
        if platform.system() != "Darwin":
            raise
        subprocess.check_call([
            sys.executable,
            "-m",
            "pip",
            "install",
            "--user",
            "--break-system-packages",
            *packages,
        ])


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


def ensure_bflb_mcu_tool() -> None:
    if sys.version_info >= (3, 13):
        try:
            import telnetlib  # noqa: F401
        except ImportError:
            install_python_packages(TELNETLIB_BACKPORT_PACKAGE)
            import telnetlib  # noqa: F401
    try:
        import bflb_mcu_tool  # noqa: F401
    except ImportError:
        install_python_packages(
            f"{BFLB_MCU_TOOL_PACKAGE}=={BFLB_MCU_TOOL_VERSION}"
        )
        import bflb_mcu_tool  # noqa: F401


def build_full_flash_image(
    segments: list[tuple[int, Path]], destination: Path
) -> None:
    end = max(address + path.stat().st_size for address, path in segments)
    image = bytearray([0xFF]) * end
    occupied: list[tuple[int, int]] = []
    for address, path in sorted(segments):
        data = path.read_bytes()
        segment_end = address + len(data)
        if any(address < prior_end and prior_address < segment_end
               for prior_address, prior_end in occupied):
            raise RuntimeError(f"Overlapping BL616 Flash segment: {path}")
        image[address:segment_end] = data
        occupied.append((address, segment_end))
    destination.write_bytes(image)
    print(
        f"Prepared complete BL616 Flash image: {destination} "
        f"({destination.stat().st_size} bytes)"
    )


def flash_bl616_once(image: Path, port: str, baudrate: int) -> tuple[bool, str]:
    runner = Path(__file__).with_name("bl616_flash_runner.py")
    command = [
        sys.executable,
        "-W",
        "ignore::RuntimeWarning",
        str(runner),
        "--chipname=bl616",
        "--interface=uart",
        "--write",
        "--flash",
        f"--port={port}",
        f"--baudrate={baudrate}",
        f"--file={image}",
        "--addr=0x0",
    ]
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    assert process.stdout is not None
    output: list[str] = []
    for line in process.stdout:
        print(line, end="")
        output.append(line)
    return_code = process.wait()
    transcript = "".join(output)
    return return_code == 0 and "[All Successful]" in transcript, transcript


def flash_bl616(image: Path, port: str, baudrate: int) -> None:
    ensure_bflb_mcu_tool()
    print("\nPut the Tang Nano 20K BL616 in boot mode:")
    print("1. Disconnect USB.")
    print("2. Hold UPDATE while reconnecting USB, then release UPDATE.")

    print(f"3. Flashing through {port} at {baudrate} baud.")
    successful, _ = flash_bl616_once(image, port, baudrate)
    if successful:
        print(
            "BL616 programming completed and the board was asked to restart "
            "from Flash. The serial port may briefly disconnect."
        )
        return

    raise RuntimeError(
        "Bouffalo Lab's tool did not confirm successful BL616 programming."
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--launch", action="store_true", help="launch FlashCube on Windows")
    parser.add_argument(
        "--install-tools",
        action="store_true",
        help="install and validate the cross-platform BL616 UART tool, then exit",
    )
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
        "--unified-3921",
        type=Path,
        help="override the packaged NanoQL firmware for revision 3921",
    )
    parser.add_argument(
        "--unified-3923",
        type=Path,
        help="override the packaged NanoQL firmware for revision 3923",
    )
    parser.add_argument(
        "--flash",
        action="store_true",
        help="program the BL616 with Bouffalo Lab's cross-platform command tool",
    )
    parser.add_argument(
        "--profile",
        choices=("nanoql", "original"),
        default="nanoql",
        help="firmware profile used with --flash",
    )
    parser.add_argument("--port", help="BL616 bootloader serial port")
    parser.add_argument(
        "--baudrate",
        type=int,
        default=(
            230_400 if platform.system() == "Darwin" else 2_000_000
        ),
        help="UART baud rate (default: 230400 on macOS, 2000000 elsewhere)",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="confirm the destructive BL616 Flash operation",
    )
    args = parser.parse_args()

    if args.install_tools:
        ensure_bflb_mcu_tool()
        print("The cross-platform BL616 UART flashing tool is ready.")
        return 0

    if args.flash:
        if args.revision == "both":
            parser.error("--flash requires --revision 3921 or --revision 3923")
        if not args.port:
            parser.error("--flash requires --port")
        if not args.yes:
            parser.error("--flash requires --yes")

    repository = Path(__file__).resolve().parent.parent
    cache = repository / "private" / "bl616"
    package = cache / "flash-package"
    package.mkdir(parents=True, exist_ok=True)

    for name, url, expected in DOWNLOADS:
        verified_download(url, package / name, expected, args.force_download)

    revisions = ("3921", "3923") if args.revision == "both" else (args.revision,)
    original_configs = {
        "3921": ("flash_nano20k_3921.ini", "1_ORIGINAL_3921_partner.ini"),
        "3923": ("flash_nano20k_3923.ini", "1_ORIGINAL_3923_partner.ini"),
    }
    for revision in revisions:
        source_name, destination_name = original_configs[revision]
        shutil.copy2(
            repository / "firmware" / "bl616" / source_name,
            package / destination_name,
        )

    unified_firmware = {
        "3921": (
            args.unified_3921 or repository / "firmware" / "bl616" / "package" /
                "nanoql_companion_nano20k.bin",
            "nanoql_companion_nano20k.bin",
            "flash_nano20k_3921_unified.ini",
            "2_NANOQL_3921.ini",
        ),
        "3923": (
            args.unified_3923 or repository / "firmware" / "bl616" / "package" /
                "nanoql_companion_nano20k_v3923.bin",
            "nanoql_companion_nano20k_v3923.bin",
            "flash_nano20k_3923_unified.ini",
            "2_NANOQL_3923.ini",
        ),
    }
    for revision in revisions:
        source, firmware_name, config_source, config_name = unified_firmware[revision]
        if not source.is_file():
            raise FileNotFoundError(source)
        shutil.copy2(source, package / firmware_name)
        print(
            f"NanoQL BL616 {revision} firmware: {source} "
            f"(SHA-256 {sha256(source)})"
        )
        shutil.copy2(repository / "firmware" / "bl616" / config_source, package / config_name)

    allowed_names = {name for name, _, _ in DOWNLOADS}
    for revision in revisions:
        allowed_names.update({
            original_configs[revision][1],
            unified_firmware[revision][1],
            unified_firmware[revision][3],
        })
    for path in package.iterdir():
        if path.is_file() and path.name not in allowed_names:
            path.unlink()

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
    print(f"NanoQL release: {NANOQL_RELEASE_TAG}")
    print(f"FPGA Companion base: {RELEASE_TAG}")
    for revision in revisions:
        print(f"Revision {revision} original: {package / original_configs[revision][1]}")
        print(f"Revision {revision} NanoQL:   {package / unified_firmware[revision][3]}")
    print("\nORIGINAL restores Sipeed's FPGA Partner and Companion firmware.")
    print("NANOQL installs the unified firmware used for normal operation and NanoQL Link.")
    if flashcube_executable:
        print(f"FlashCube: {flashcube_executable}")
    else:
        print(
            "FlashCube is Windows-only; native BL616 flashing is available "
            "with --flash on Windows, macOS, and Linux."
        )

    if args.flash:
        revision = args.revision
        suffix = "" if revision == "3921" else "_v3923"
        if args.profile == "nanoql":
            segments = [
                (0, package / "bl616_bootloader_0x20000_nano20k_signed.bin"),
                (BL616_APPLICATION_OFFSET, package / unified_firmware[revision][1]),
            ]
        else:
            segments = [
                (0, package / f"bl616_fpga_partner_nano20k{suffix}.bin"),
                (0x40000, package / f"fpga_companion_nano20k{suffix}.bin"),
            ]
        full_image = package / f"nanoql_bl616_{revision}_{args.profile}_full.bin"
        build_full_flash_image(segments, full_image)
        print(f"Flashing image SHA-256: {sha256(full_image)}")
        flash_bl616(full_image, args.port, args.baudrate)

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

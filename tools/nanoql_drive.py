#!/usr/bin/env python3
"""Build a QLAY Microdrive image from ordinary desktop files."""

from __future__ import annotations

import argparse
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path


QLAY_SECTOR_COUNT = 255
QLAY_SECTOR_SIZE = 686
QLAY_IMAGE_SIZE = QLAY_SECTOR_COUNT * QLAY_SECTOR_SIZE
QL_DATA_SIZE = 512
QL_HEADER_SIZE = 64
FREE_SECTOR = 0xFD
DAMAGED_SECTOR = 0xFF
MAP_FILE = 0xF8


@dataclass(frozen=True)
class DriveFile:
    name: str
    data: bytes
    executable: bool = False
    data_space: int = 0


def checksum(data: bytes) -> bytes:
    """Return the QL Microdrive additive checksum in tape byte order."""
    value = (0x0F0F + sum(data)) & 0xFFFF
    return value.to_bytes(2, "little")


def qdos_name(relative_path: Path) -> str:
    name = relative_path.as_posix().replace("/", "_").replace(".", "_")
    try:
        encoded = name.encode("ascii")
    except UnicodeEncodeError as error:
        raise ValueError(f"QL filename is not ASCII: {relative_path}") from error
    if not encoded or len(encoded) > 36:
        raise ValueError(
            f"QL filename must contain 1 to 36 characters: {relative_path}"
        )
    if any(byte < 0x20 or byte > 0x7E for byte in encoded):
        raise ValueError(f"QL filename is not printable: {relative_path}")
    return name


def qdos_header(file: DriveFile, total_length: int | None = None) -> bytes:
    header = bytearray(QL_HEADER_SIZE)
    length = total_length if total_length is not None else len(file.data) + 64
    struct.pack_into(">I", header, 0, length)
    header[5] = 1 if file.executable else 0
    struct.pack_into(">I", header, 6, file.data_space if file.executable else 0)
    encoded_name = file.name.encode("ascii")
    struct.pack_into(">H", header, 14, len(encoded_name))
    header[16 : 16 + len(encoded_name)] = encoded_name
    return bytes(header)


def collect_drive_files(source: Path, excluded: Path | None = None) -> list[DriveFile]:
    source = source.resolve()
    excluded = excluded.resolve() if excluded is not None else None
    files: list[DriveFile] = []
    for path in sorted(source.rglob("*"), key=lambda item: item.as_posix().lower()):
        if not path.is_file() or (excluded is not None and path.resolve() == excluded):
            continue
        data = path.read_bytes()
        executable = len(data) >= 8 and data[-8:-4] == b"XTcc"
        data_space = int.from_bytes(data[-4:], "big") if executable else 0
        files.append(
            DriveFile(
                name=qdos_name(path.relative_to(source)),
                data=data,
                executable=executable,
                data_space=data_space,
            )
        )
    names = [file.name.lower() for file in files]
    if len(names) != len(set(names)):
        raise ValueError("Two desktop paths produce the same QL filename.")
    if len(files) > 126:
        raise ValueError("A Microdrive image supports at most 126 user files.")
    return files


def empty_sector(medium_name: bytes, medium_id: int, sector_number: int) -> dict:
    return {
        "number": sector_number,
        "header_flag": 0xFF,
        "medium_name": medium_name,
        "medium_id": medium_id,
        "file": FREE_SECTOR,
        "block": 0,
        # Match a freshly formatted physical cartridge. QDOS ignores the
        # payload of free sectors, but real QL tools initialize it with the
        # alternating calibration pattern rather than zeroes.
        "data": bytes((0xAA, 0x55)) * (QL_DATA_SIZE // 2),
    }


def serialize_sector(sector: dict) -> bytes:
    header_data = bytes((sector["header_flag"], sector["number"]))
    header_data += sector["medium_name"]
    header_data += int(sector["medium_id"]).to_bytes(2, "big")

    block_data = bytes((sector["file"], sector["block"]))
    payload = bytes(sector["data"])
    if len(payload) != QL_DATA_SIZE:
        raise ValueError("A Microdrive data block must contain 512 bytes.")

    # The 612-byte decoded record ends with 84 calibration bytes and their
    # little-endian checksum. A QLAY sector then carries 34 padding bytes.
    record_tail = bytes((0xAA, 0x55)) * 42
    record_tail += (0x3B19).to_bytes(2, "little")

    return (
        bytes(10)
        + b"\xFF\xFF"
        + header_data
        + checksum(header_data)
        + bytes(10)
        + b"\xFF\xFF"
        + block_data
        + checksum(block_data)
        + bytes(6)
        + b"\xFF\xFF"
        + payload
        + checksum(payload)
        + record_tail
        + b"Z" * 34
    )


def build_qlay_image(files: list[DriveFile], medium: str = "NANOQL") -> bytes:
    medium_bytes = medium.encode("ascii")
    if not medium_bytes or len(medium_bytes) > 10:
        raise ValueError("The Microdrive name must contain 1 to 10 ASCII characters.")
    medium_bytes = medium_bytes.ljust(10, b" ")

    fingerprint = zlib.crc32(medium_bytes)
    for file in files:
        fingerprint = zlib.crc32(file.name.encode("ascii"), fingerprint)
        fingerprint = zlib.crc32(file.data, fingerprint)
    medium_id = fingerprint & 0xFFFF

    sectors = [
        empty_sector(medium_bytes, medium_id, number)
        for number in range(QLAY_SECTOR_COUNT)
    ]
    mapping = [(FREE_SECTOR, 0) for _ in range(QLAY_SECTOR_COUNT)]
    mapping[0] = (MAP_FILE, 0)
    mapping[254] = (DAMAGED_SECTOR, 0)

    file_headers = [qdos_header(file) for file in files]
    directory_length = (len(files) + 1) * QL_HEADER_SIZE
    directory_header = qdos_header(
        DriveFile(name="", data=b""), total_length=directory_length
    )
    streams = [directory_header + b"".join(file_headers)]
    streams.extend(header + file.data for header, file in zip(file_headers, files))

    current_sector = 245
    def allocate(after_sector: int) -> int:
        candidate = after_sector
        for _ in range(QLAY_SECTOR_COUNT):
            if mapping[candidate][0] == FREE_SECTOR:
                return candidate
            candidate = (candidate - 1) % QLAY_SECTOR_COUNT
        raise ValueError("The files do not fit on a single Microdrive image.")

    for file_number, stream in enumerate(streams):
        block_count = (len(stream) + QL_DATA_SIZE - 1) // QL_DATA_SIZE
        for block in range(block_count):
            sector_number = allocate(current_sector)
            payload = stream[
                block * QL_DATA_SIZE : (block + 1) * QL_DATA_SIZE
            ].ljust(QL_DATA_SIZE, b"\x00")
            sectors[sector_number]["file"] = file_number
            sectors[sector_number]["block"] = block
            sectors[sector_number]["data"] = payload
            mapping[sector_number] = (file_number, block)
            current_sector = allocate(
                (sector_number - 13) % QLAY_SECTOR_COUNT
            )

    map_data = bytearray(QL_DATA_SIZE)
    for sector_number, (file_number, block) in enumerate(mapping):
        map_data[sector_number * 2] = file_number
        map_data[sector_number * 2 + 1] = block
    # Byte 510 is the QDOS map-format marker. Byte 511 records the next free
    # allocation position, matching cartridges formatted by a physical QL.
    map_data[510] = 1
    map_data[511] = current_sector
    sectors[0]["file"] = 0x80
    sectors[0]["block"] = 0
    sectors[0]["data"] = bytes(map_data)

    physical_order = [0] + list(range(254, 0, -1))
    image = b"".join(serialize_sector(sectors[number]) for number in physical_order)
    validate_qlay_image(image)
    return image


def validate_qlay_image(image: bytes) -> None:
    if len(image) != QLAY_IMAGE_SIZE:
        raise ValueError(f"QLAY image has {len(image)} bytes instead of 174930.")
    sector_numbers: set[int] = set()
    for offset in range(0, len(image), QLAY_SECTOR_SIZE):
        sector = image[offset : offset + QLAY_SECTOR_SIZE]
        if sector[:10] != bytes(10) or sector[10:12] != b"\xFF\xFF":
            raise ValueError("Invalid QLAY sector header preamble.")
        if sector[12] == 0xFF:
            if sector[13] in sector_numbers:
                raise ValueError("QLAY image repeats a usable sector number.")
            sector_numbers.add(sector[13])
        if sector[26:28] != checksum(sector[12:26]):
            raise ValueError("Invalid QLAY sector header checksum.")
        if sector[28:38] != bytes(10) or sector[38:40] != b"\xFF\xFF":
            raise ValueError("Invalid QLAY block header preamble.")
        if sector[42:44] != checksum(sector[40:42]):
            raise ValueError("Invalid QLAY block header checksum.")
        if sector[44:50] != bytes(6) or sector[50:52] != b"\xFF\xFF":
            raise ValueError("Invalid QLAY data preamble.")
        if sector[564:566] != checksum(sector[52:564]):
            raise ValueError("Invalid QLAY data checksum.")
    # Real dumps can contain damaged sectors whose header number is not valid.
    # QDOS requires sector zero and at least 200 usable sectors.
    if 0 not in sector_numbers or len(sector_numbers) < 200:
        raise ValueError("QLAY image does not contain a usable cartridge map.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a QLAY MDV1 image from an ordinary folder."
    )
    parser.add_argument("source", type=Path, help="folder containing desktop files")
    parser.add_argument(
        "output", nargs="?", type=Path,
        help="output .mdv file (default: SOURCE/MDV1.mdv)",
    )
    parser.add_argument("--name", default="NANOQL", help="QL medium name")
    args = parser.parse_args()

    source = args.source.expanduser().resolve()
    if not source.is_dir():
        raise NotADirectoryError(source)
    output = (args.output or source / "MDV1.mdv").expanduser().resolve()
    files = collect_drive_files(source, excluded=output)
    image = build_qlay_image(files, args.name)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image)
    print(f"Created {output}")
    print(f"Files: {len(files)}; image size: {len(image)} bytes")
    for file in files:
        print(f"  {file.name}: {len(file.data)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

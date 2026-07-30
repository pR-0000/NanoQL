#!/usr/bin/env python3
"""Convert supported 8049 firmware representations to a 2 KiB raw image."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_intel_hex(source: Path) -> bytes:
    rom = bytearray([0xFF] * 2048)
    written = bytearray(2048)
    upper_address = 0
    eof_seen = False

    for raw_line in source.read_text(encoding="ascii").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise ValueError(f"Invalid Intel HEX line: {line}")
        record = bytes.fromhex(line[1:])
        if sum(record) & 0xFF:
            raise ValueError(f"Intel HEX checksum failure: {line}")
        count = record[0]
        if len(record) != count + 5:
            raise ValueError(f"Invalid Intel HEX record length: {line}")
        address = int.from_bytes(record[1:3], "big")
        record_type = record[3]

        if record_type == 0:
            absolute = upper_address + address
            for index, value in enumerate(record[4 : 4 + count]):
                target = absolute + index
                if not 0 <= target < len(rom):
                    raise ValueError(f"IPC data outside 2 KiB ROM at 0x{target:X}")
                rom[target] = value
                written[target] = 1
        elif record_type == 1:
            eof_seen = True
        elif record_type == 4:
            if count != 2:
                raise ValueError("Invalid extended linear address record")
            upper_address = int.from_bytes(record[4:6], "big") << 16

    if not eof_seen:
        raise ValueError("Intel HEX EOF record is missing")
    if not all(written):
        raise ValueError("IPC firmware does not define all 2048 ROM bytes")
    return bytes(rom)


def read_ipc_firmware(source: Path) -> bytes:
    if not source.is_file():
        raise ValueError(f"IPC firmware does not exist: {source}")
    raw = source.read_bytes()
    if raw.lstrip().startswith(b":"):
        return parse_intel_hex(source)
    if len(raw) == 2048:
        return raw
    try:
        tokens = raw.decode("ascii").split()
    except UnicodeDecodeError as error:
        raise ValueError(
            "IPC firmware must be raw binary, Intel HEX, or hexadecimal byte pairs"
        ) from error
    if len(tokens) != 2048 or any(
        len(token) != 2 or any(char not in "0123456789abcdefABCDEF" for char in token)
        for token in tokens
    ):
        raise ValueError(
            "Text IPC firmware must contain exactly 2,048 hexadecimal byte pairs"
        )
    return bytes(int(token, 16) for token in tokens)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument(
        "output", nargs="?", type=Path, default=Path("IPC.rom")
    )
    args = parser.parse_args()
    rom = read_ipc_firmware(args.input)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(rom)
    print(f"IPC ROM prepared: {args.output.resolve()}")
    print("Output size: 2048 bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

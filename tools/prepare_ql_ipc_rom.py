#!/usr/bin/env python3
"""Convert a complete Intel HEX dump to NanoQL's 2 KiB IPC ROM hex file."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    repository = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=repository / "src" / "ipc" / "ql_ipc_rom.hex",
    )
    args = parser.parse_args()

    rom = bytearray([0xFF] * 2048)
    written = bytearray(2048)
    upper_address = 0
    eof_seen = False

    for raw_line in args.input.read_text(encoding="ascii").splitlines():
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

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(f"{value:02X}\n" for value in rom), encoding="ascii")
    print(f"IPC ROM converted: {args.output.resolve()}")
    print("Output size: 2048 bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

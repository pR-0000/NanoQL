#!/usr/bin/env python3
"""Convert a user-supplied QL ROM dump to NanoQL's 16-bit hex format."""

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
        default=repository / "src" / "rom" / "ql_system_rom.hex",
    )
    args = parser.parse_args()

    data = args.input.read_bytes()
    if len(data) not in (49152, 65536):
        parser.error("QL ROM must contain exactly 49,152 or 65,536 bytes")
    padded = data + bytes([0xFF]) * (65536 - len(data))
    initial_sp = int.from_bytes(padded[0:4], "big")
    initial_pc = int.from_bytes(padded[4:8], "big")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    lines = (f"{padded[index]:02X}{padded[index + 1]:02X}" for index in range(0, 65536, 2))
    args.output.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"ROM converted: {args.output.resolve()}")
    print(f"Input size: {len(data)} bytes")
    print(f"Initial SP: 0x{initial_sp:08X}; initial PC: 0x{initial_pc:08X}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

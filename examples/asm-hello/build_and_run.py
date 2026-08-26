#!/usr/bin/env python3
"""Assemble and directly inject the NanoQL 68000 Hello World example."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys


EXAMPLE = Path(__file__).resolve().parent
REPOSITORY = EXAMPLE.parents[1]
SOURCE = EXAMPLE / "hello.asm"
OUTPUT = EXAMPLE / "build" / "hello.bin"


def find_assembler(explicit: str | None) -> str:
    if explicit:
        candidate = Path(explicit).expanduser().resolve()
        if candidate.is_file():
            return str(candidate)
        raise FileNotFoundError(f"vasmm68k_mot was not found at {candidate}")
    candidate = shutil.which("vasmm68k_mot") or shutil.which("vasmm68k_mot.exe")
    if candidate:
        return candidate
    raise FileNotFoundError(
        "vasmm68k_mot was not found. Add it to PATH or pass "
        "--assembler /path/to/vasmm68k_mot."
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build and inject the NanoQL bare-metal Hello World."
    )
    parser.add_argument("--port", help="NanoQL Link port, for example COM20")
    parser.add_argument("--assembler", help="path to vasmm68k_mot")
    parser.add_argument(
        "--build-only", action="store_true", help="assemble without injection"
    )
    args = parser.parse_args()

    assembler = find_assembler(args.assembler)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    compile_command = [
        assembler, "-m68000", "-Fbin", "-quiet", "-o", str(OUTPUT),
        str(SOURCE),
    ]
    print("Assembling:", " ".join(compile_command), flush=True)
    subprocess.run(compile_command, cwd=EXAMPLE, check=True)
    print(f"Built {OUTPUT} ({OUTPUT.stat().st_size} bytes).", flush=True)

    if args.build_only:
        return 0

    link_command = [sys.executable, str(REPOSITORY / "tools" / "nanoql_link.py")]
    if args.port:
        link_command.extend(["--port", args.port])
    link_command.extend([
        "load", str(OUTPUT), "--address", "0x30000",
        "--pc", "0x30000", "--stack", "0x3fff0",
    ])
    print("Injecting through NanoQL Link...", flush=True)
    subprocess.run(link_command, cwd=REPOSITORY, check=True)
    print("HELLO NANOQL should now be visible. Use 'qdos' to restart QDOS.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

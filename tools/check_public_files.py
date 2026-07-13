#!/usr/bin/env python3
"""Reject private or generated files that must never be published."""

from __future__ import annotations

import subprocess
import sys
from pathlib import PurePosixPath


BLOCKED_PARTS = {"private", "local", "roms", "downloads", "cache", ".cache"}
BLOCKED_SUFFIXES = {
    ".7z",
    ".bin",
    ".bit",
    ".dsk",
    ".elf",
    ".fs",
    ".gz",
    ".img",
    ".mdv",
    ".map",
    ".qxl",
    ".rom",
    ".tar",
    ".zip",
}
BLOCKED_EXACT = {"src/ipc/ql_ipc_rom.hex"}


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        check=True,
        stdout=subprocess.PIPE,
    )
    return [item.decode("utf-8") for item in result.stdout.split(b"\0") if item]


def reason_for(path_text: str) -> str | None:
    path = PurePosixPath(path_text)
    if path_text in BLOCKED_EXACT:
        return "private ROM initialization file"
    if path.name.lower().startswith("ipc") and path.suffix.lower() == ".hex":
        return "IPC firmware image"
    if path.name.lower().endswith("_rom.hex"):
        return "ROM initialization file"
    if BLOCKED_PARTS.intersection(path.parts):
        return "private, local, downloaded, or cached directory"
    if path.suffix.lower() in BLOCKED_SUFFIXES:
        return "generated bitstream, archive, ROM, or disk image"
    return None


def main() -> int:
    violations = [(path, reason) for path in tracked_files() if (reason := reason_for(path))]
    if not violations:
        print("Publication check passed: no blocked file is tracked.")
        return 0

    print("Publication check failed. Remove these files from Git before publishing:", file=sys.stderr)
    for path, reason in violations:
        print(f"  {path}: {reason}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

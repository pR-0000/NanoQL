#!/usr/bin/env python3
"""Upload and start bare-metal 68000 binaries through NanoQL Link."""

from __future__ import annotations

import argparse
import ctypes
import os
import queue
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unicodedata
import zlib
from pathlib import Path

from nanoql_drive import (
    build_qlay_image,
    collect_drive_files,
    extract_qlay_image,
)

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyserial"])
    import serial
    from serial.tools import list_ports


REQUEST_MAGIC = b"NQ"
RESPONSE_MAGIC = b"QN"
PROTOCOL_VERSION = 1
MAX_LINK_PAYLOAD = 245

FIRMWARE_ERRORS = {
    1: "unsupported protocol version",
    2: "invalid request CRC",
    3: "invalid request length",
    4: "invalid FPGA bitstream size",
    5: "unable to initialize FPGA JTAG programming",
    6: "FPGA transfer is not initialized or has an inconsistent length",
    7: "direct FPGA transfer failed",
    8: "invalid FPGA bitstream size or CRC",
    9: "FPGA JTAG programming failed",
    20: "microSD filesystem is not ready",
    21: "invalid Drive1 path",
    22: "another microSD file operation is active",
    23: "microSD I/O error",
    24: "uploaded file failed size or CRC verification",
    25: "file or directory not found in Drive1",
    26: "file or directory already exists",
    27: "Drive1 filename is too long",
    28: "microSD is write-protected",
    29: "microSD operation was denied",
}

FATFS_ERRORS = {
    1: "FR_DISK_ERR",
    2: "FR_INT_ERR",
    3: "FR_NOT_READY",
    4: "FR_NO_FILE",
    5: "FR_NO_PATH",
    6: "FR_INVALID_NAME",
    7: "FR_DENIED",
    8: "FR_EXIST",
    9: "FR_INVALID_OBJECT",
    10: "FR_WRITE_PROTECTED",
    11: "FR_INVALID_DRIVE",
    12: "FR_NOT_ENABLED",
    13: "FR_NO_FILESYSTEM",
    14: "FR_MKFS_ABORTED",
    15: "FR_TIMEOUT",
    16: "FR_LOCKED",
    17: "FR_NOT_ENOUGH_CORE",
    18: "FR_TOO_MANY_OPEN_FILES",
    19: "FR_INVALID_PARAMETER",
}

CMD_STATUS = 0x00
CMD_HOLD = 0x01
CMD_WRITE = 0x02
CMD_EXEC = 0x03
CMD_QDOS = 0x04
CMD_KEY = 0x05
KEY_DIRECT_MATRIX = 0x01
CMD_READ = 0x06
CMD_READ_RESULT = 0x07
CMD_QLSD_DIAG = 0x08
CMD_CPU_DIAG = 0x09
CMD_MDV_DIAG = 0x0A
CMD_MDV_TRACE = 0x0B
CMD_MDV_DATA_TRACE = 0x0C
CMD_FS_INFO = 0xE0
CMD_FS_LIST_BEGIN = 0xE1
CMD_FS_LIST_NEXT = 0xE2
CMD_FS_PUT_BEGIN = 0xE3
CMD_FS_PUT_DATA = 0xE4
CMD_FS_PUT_COMMIT = 0xE5
CMD_FS_GET_BEGIN = 0xE6
CMD_FS_GET_DATA = 0xE7
CMD_FS_GET_END = 0xE8
CMD_FS_DELETE = 0xE9
CMD_FS_MKDIR = 0xEA
CMD_FS_CANCEL = 0xEB
CMD_FS_MDV_CONTROL = 0xEC
CMD_FPGA_BEGIN = 0xF0
CMD_FPGA_DATA = 0xF1
CMD_FPGA_PROGRAM = 0xF2

MOD_LEFT_CTRL = 0x68
MOD_LEFT_SHIFT = 0x69
MOD_LEFT_ALT = 0x6A

# Direct QL matrix contacts used by NanoQL Link. A local USB keyboard still
# follows the raw HID command-1 path in the FPGA and is translated separately.
QL_USAGE_TO_MATRIX = {
    0x04: 36, 0x05: 20, 0x06: 19, 0x07: 38, 0x08: 52,
    0x09: 28, 0x0A: 30, 0x0B: 34, 0x0C: 42, 0x0D: 39,
    0x0E: 26, 0x0F: 32, 0x10: 22, 0x11: 62, 0x12: 47,
    0x13: 37, 0x14: 51, 0x15: 44, 0x16: 27, 0x17: 54,
    0x18: 55, 0x19: 60, 0x1A: 41, 0x1B: 59, 0x1C: 46,
    0x1D: 17, 0x1E: 35, 0x1F: 49, 0x20: 33, 0x21: 6,
    0x22: 2, 0x23: 50, 0x24: 7, 0x25: 48, 0x26: 40,
    0x27: 53, 0x28: 8, 0x29: 11, 0x2B: 43, 0x2C: 14,
    0x2D: 45, 0x2E: 29, 0x2F: 24, 0x30: 16, 0x31: 13,
    0x32: 21, 0x33: 31, 0x34: 23, 0x36: 63, 0x37: 18,
    0x38: 61, 0x39: 25, 0x3A: 1, 0x3B: 3, 0x3C: 4,
    0x3D: 0, 0x3E: 5, 0x4F: 12, 0x50: 9, 0x51: 15,
    0x52: 10, MOD_LEFT_CTRL: 57, MOD_LEFT_SHIFT: 56,
    MOD_LEFT_ALT: 58, 0x6C: 57, 0x6D: 56, 0x6E: 58,
}

# Keep overlay navigation as raw HID usages. The BL616 must see these codes
# before deciding whether to consume them for the OSD or forward them to QDOS.
REMOTE_MENU_USAGES = {
    0x28,  # Enter
    0x29,  # Escape
    0x2C,  # Space
    0x4B,  # Page Up
    0x4E,  # Page Down
    0x4F,  # Right
    0x50,  # Left
    0x51,  # Down
    0x52,  # Up
}

ASCII_KEYS = {
    "a": (0x04, False), "b": (0x05, False), "c": (0x06, False),
    "d": (0x07, False), "e": (0x08, False), "f": (0x09, False),
    "g": (0x0A, False), "h": (0x0B, False), "i": (0x0C, False),
    "j": (0x0D, False), "k": (0x0E, False), "l": (0x0F, False),
    "m": (0x10, False), "n": (0x11, False), "o": (0x12, False),
    "p": (0x13, False), "q": (0x14, False), "r": (0x15, False),
    "s": (0x16, False), "t": (0x17, False), "u": (0x18, False),
    "v": (0x19, False), "w": (0x1A, False), "x": (0x1B, False),
    "y": (0x1C, False), "z": (0x1D, False),
    "1": (0x1E, False), "2": (0x1F, False), "3": (0x20, False),
    "4": (0x21, False), "5": (0x22, False), "6": (0x23, False),
    "7": (0x24, False), "8": (0x25, False), "9": (0x26, False),
    "0": (0x27, False), "\n": (0x28, False), "\r": (0x28, False),
    "\x1b": (0x29, False), "\b": (0x2A, False), "\t": (0x2B, False),
    " ": (0x2C, False), "-": (0x2D, False), "_": (0x2D, True),
    "=": (0x2E, False), "+": (0x2E, True), "[": (0x2F, False),
    "{": (0x2F, True), "]": (0x30, False), "}": (0x30, True),
    "\\": (0x31, False), "|": (0x31, True), ";": (0x33, False),
    ":": (0x33, True), "'": (0x34, False), '"': (0x34, True),
    "`": (0x35, False), "~": (0x35, True), ",": (0x36, False),
    "<": (0x36, True), ".": (0x37, False), ">": (0x37, True),
    "/": (0x38, False), "?": (0x38, True), "!": (0x1E, True),
    "@": (0x1F, True), "#": (0x20, True), "$": (0x21, True),
    "%": (0x22, True), "^": (0x23, True), "&": (0x24, True),
    "*": (0x25, True), "(": (0x26, True), ")": (0x27, True),
}

# Character-to-contact mapping from the MGF French QDOS keyboard table. The
# values are USB usages for the corresponding original QL matrix contact, not
# positions on a PC AZERTY keyboard. This also makes macOS independent from
# pynput's occasionally US-oriented character names for punctuation keys.
QL_FRENCH_KEYS = {
    "a": (0x14, ()), "A": (0x14, (MOD_LEFT_SHIFT,)),
    "q": (0x04, ()), "Q": (0x04, (MOD_LEFT_SHIFT,)),
    "z": (0x1A, ()), "Z": (0x1A, (MOD_LEFT_SHIFT,)),
    "w": (0x1D, ()), "W": (0x1D, (MOD_LEFT_SHIFT,)),
    "m": (0x33, ()), "M": (0x33, (MOD_LEFT_SHIFT,)),
    ",": (0x10, ()), ".": (0x36, ()),
    ";": (0x37, ()), ":": (0x37, (MOD_LEFT_SHIFT,)),
    "<": (0x10, (MOD_LEFT_SHIFT,)),
    ">": (0x36, (MOD_LEFT_SHIFT,)),
    "'": (0x23, (MOD_LEFT_SHIFT,)),
    '"': (0x1F, (MOD_LEFT_SHIFT,)),
    "@": (0x23, (MOD_LEFT_CTRL,)),
    "[": (0x26, (MOD_LEFT_CTRL,)),
    "]": (0x27, (MOD_LEFT_CTRL,)),
    "{": (0x2D, (MOD_LEFT_CTRL,)),
    "}": (0x2E, (MOD_LEFT_CTRL,)),
    "^": (0x32, (MOD_LEFT_CTRL,)),
    "`": (0x38, (MOD_LEFT_ALT,)),
    "\\": (0x2F, (MOD_LEFT_SHIFT,)),
    "|": (0x25, (MOD_LEFT_CTRL,)),
    "~": (0x31, (MOD_LEFT_CTRL,)),
    "_": (0x2D, (MOD_LEFT_SHIFT,)),
    "é": (0x2F, ()), "è": (0x30, ()), "ù": (0x31, ()),
    "à": (0x34, ()), "ç": (0x38, ()),
    "§": (0x30, (MOD_LEFT_SHIFT,)),
    "£": (0x31, (MOD_LEFT_SHIFT,)),
    "°": (0x24, (MOD_LEFT_CTRL,)),
    "/": (0x34, (MOD_LEFT_SHIFT,)),
    "?": (0x38, (MOD_LEFT_SHIFT,)),
}

WINDOWS_EXTENDED_KEYS = {
    "H": 0x52, "P": 0x51, "K": 0x50, "M": 0x4F,
    "G": 0x4A, "O": 0x4D, "I": 0x4B, "Q": 0x4E,
    "S": 0x4C,
    ";": 0x3A, "<": 0x3B, "=": 0x3C, ">": 0x3D, "?": 0x3E,
    "@": 0x3F, "A": 0x40, "B": 0x41, "C": 0x42, "D": 0x43,
    "\x85": 0x44, "\x86": 0x45,
}

SCAN_TO_HID = {
    0x01: 0x29,
    0x02: 0x1E, 0x03: 0x1F, 0x04: 0x20, 0x05: 0x21, 0x06: 0x22,
    0x07: 0x23, 0x08: 0x24, 0x09: 0x25, 0x0A: 0x26, 0x0B: 0x27,
    0x0C: 0x2D, 0x0D: 0x2E, 0x0E: 0x2A, 0x0F: 0x2B,
    0x10: 0x14, 0x11: 0x1A, 0x12: 0x08, 0x13: 0x15, 0x14: 0x17,
    0x15: 0x1C, 0x16: 0x18, 0x17: 0x0C, 0x18: 0x12, 0x19: 0x13,
    0x1A: 0x2F, 0x1B: 0x30, 0x1C: 0x28,
    0x1E: 0x04, 0x1F: 0x16, 0x20: 0x07, 0x21: 0x09, 0x22: 0x0A,
    0x23: 0x0B, 0x24: 0x0D, 0x25: 0x0E, 0x26: 0x0F, 0x27: 0x33,
    0x28: 0x34, 0x29: 0x35, 0x2B: 0x31,
    0x2C: 0x1D, 0x2D: 0x1B, 0x2E: 0x06, 0x2F: 0x19, 0x30: 0x05,
    0x31: 0x11, 0x32: 0x10, 0x33: 0x36, 0x34: 0x37, 0x35: 0x38,
    0x39: 0x2C, 0x56: 0x64,
}

# macOS virtual key codes describe physical ANSI/ISO key positions. Preserve
# those positions for the live keyboard so the FPGA performs the AZERTY/QWERTY
# conversion exactly once, just as it does for a directly attached USB device.
MAC_VK_TO_HID = {
    0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0B, 5: 0x0A,
    6: 0x1D, 7: 0x1B, 8: 0x06, 9: 0x19, 11: 0x05,
    12: 0x14, 13: 0x1A, 14: 0x08, 15: 0x15, 16: 0x1C,
    17: 0x17, 18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21,
    22: 0x23, 23: 0x22, 24: 0x2E, 25: 0x26, 26: 0x24,
    27: 0x2D, 28: 0x25, 29: 0x27, 30: 0x30, 31: 0x12,
    32: 0x18, 33: 0x2F, 34: 0x0C, 35: 0x13, 37: 0x0F,
    38: 0x0D, 39: 0x34, 40: 0x0E, 41: 0x33, 42: 0x31,
    43: 0x36, 44: 0x38, 45: 0x11, 46: 0x10, 47: 0x37,
    50: 0x35,
}


def windows_keyboard_layout():
    """Return the layout of the foreground terminal, not Python's thread."""
    if os.name != "nt":
        return None
    user32 = ctypes.windll.user32
    user32.GetForegroundWindow.restype = ctypes.c_void_p
    user32.GetWindowThreadProcessId.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    user32.GetWindowThreadProcessId.restype = ctypes.c_uint
    user32.GetKeyboardLayout.argtypes = [ctypes.c_uint]
    user32.GetKeyboardLayout.restype = ctypes.c_void_p
    window = user32.GetForegroundWindow()
    thread_id = user32.GetWindowThreadProcessId(window, None) if window else 0
    return user32.GetKeyboardLayout(thread_id)


def windows_character_key(character: str) -> tuple[int, tuple[int, ...]] | None:
    if os.name != "nt" or len(character) != 1:
        return None

    import ctypes

    user32 = ctypes.windll.user32
    user32.GetKeyboardLayout.argtypes = [ctypes.c_uint]
    user32.GetKeyboardLayout.restype = ctypes.c_void_p
    user32.VkKeyScanExW.argtypes = [ctypes.c_wchar, ctypes.c_void_p]
    user32.VkKeyScanExW.restype = ctypes.c_short
    user32.MapVirtualKeyExW.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p]
    user32.MapVirtualKeyExW.restype = ctypes.c_uint
    layout = windows_keyboard_layout()
    packed = user32.VkKeyScanExW(character, layout)
    if packed == -1:
        return None
    virtual_key = packed & 0xFF
    modifier_bits = (packed >> 8) & 0x07
    scan_code = user32.MapVirtualKeyExW(virtual_key, 0, layout) & 0xFF
    usage = SCAN_TO_HID.get(scan_code)
    if usage is None:
        return None
    modifiers = tuple(
        modifier
        for bit, modifier in (
            (0x02, MOD_LEFT_CTRL),
            (0x01, MOD_LEFT_SHIFT),
            (0x04, MOD_LEFT_ALT),
        )
        if modifier_bits & bit
    )
    return usage, modifiers


def windows_realtime_keymap() -> dict[int, int]:
    """Map Windows logical keys back to physical USB HID positions."""
    if os.name != "nt":
        return {}

    user32 = ctypes.windll.user32
    user32.GetKeyboardLayout.restype = ctypes.c_void_p
    user32.MapVirtualKeyExW.argtypes = [ctypes.c_uint, ctypes.c_uint,
                                        ctypes.c_void_p]
    user32.MapVirtualKeyExW.restype = ctypes.c_uint
    layout = windows_keyboard_layout()

    # Modifiers are first so a simultaneous modifier/key press reaches the QL
    # matrix in the same order as a physical keyboard.
    keymap = {
        0xA2: 0x68, 0xA0: 0x69, 0xA4: 0x6A,
        0xA3: 0x6C, 0xA1: 0x6D, 0xA5: 0x6E,
    }
    printable_vks = (
        list(range(0x30, 0x3A)) + list(range(0x41, 0x5B)) +
        [0x08, 0x09, 0x0D, 0x1B, 0x20, 0x14] +
        [0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0,
         0xDB, 0xDC, 0xDD, 0xDE, 0xE2]
    )
    for virtual_key in printable_vks:
        scan_code = user32.MapVirtualKeyExW(
            virtual_key, 0, layout
        ) & 0xFF
        usage = SCAN_TO_HID.get(scan_code)
        if usage is not None:
            keymap[virtual_key] = usage

    keymap.update({
        0x24: 0x4A,  # Home
        0x21: 0x4B,  # Page Up
        0x2E: 0x4C,  # Delete
        0x23: 0x4D,  # End
        0x22: 0x4E,  # Page Down
        0x27: 0x4F,  # Right
        0x25: 0x50,  # Left
        0x28: 0x51,  # Down
        0x26: 0x52,  # Up
    })
    for virtual_key in range(0x70, 0x7C):
        if virtual_key != 0x75:  # F6 releases the terminal keyboard.
            keymap[virtual_key] = 0x3A + virtual_key - 0x70
    return keymap


def windows_virtual_key_character(virtual_key: int) -> str | None:
    """Translate one currently pressed Windows key without consuming it."""
    if os.name != "nt":
        return None

    user32 = ctypes.windll.user32
    user32.GetKeyboardLayout.restype = ctypes.c_void_p
    user32.MapVirtualKeyExW.argtypes = [ctypes.c_uint, ctypes.c_uint,
                                        ctypes.c_void_p]
    user32.MapVirtualKeyExW.restype = ctypes.c_uint
    user32.ToUnicodeEx.argtypes = [
        ctypes.c_uint, ctypes.c_uint,
        ctypes.POINTER(ctypes.c_ubyte), ctypes.c_wchar_p,
        ctypes.c_int, ctypes.c_uint, ctypes.c_void_p,
    ]
    user32.ToUnicodeEx.restype = ctypes.c_int

    get_async_key_state = user32.GetAsyncKeyState
    keyboard_state = (ctypes.c_ubyte * 256)()

    def down(key: int) -> bool:
        return bool(get_async_key_state(key) & 0x8000)

    left_shift, right_shift = down(0xA0), down(0xA1)
    left_ctrl, right_ctrl = down(0xA2), down(0xA3)
    left_alt, right_alt = down(0xA4), down(0xA5)
    if left_shift or right_shift:
        keyboard_state[0x10] = 0x80
    keyboard_state[0xA0] = 0x80 if left_shift else 0
    keyboard_state[0xA1] = 0x80 if right_shift else 0

    # Ordinary Ctrl is passed directly to the QL matrix and must not turn the
    # translated character into an ASCII control code. AltGr, however, needs
    # the Windows Ctrl+Alt state to identify its printable character.
    if right_alt:
        keyboard_state[0x11] = 0x80
        keyboard_state[0x12] = 0x80
        keyboard_state[0xA2] = 0x80 if left_ctrl else 0
        keyboard_state[0xA3] = 0x80 if right_ctrl else 0
        keyboard_state[0xA5] = 0x80
    elif left_alt:
        keyboard_state[0x12] = 0x80
        keyboard_state[0xA4] = 0x80

    keyboard_state[0x14] = user32.GetKeyState(0x14) & 1
    layout = windows_keyboard_layout()
    scan_code = user32.MapVirtualKeyExW(virtual_key, 0, layout)
    output = ctypes.create_unicode_buffer(8)
    count = user32.ToUnicodeEx(
        virtual_key, scan_code, keyboard_state, output, len(output),
        0x04, layout,
    )
    if count <= 0:
        return None
    return output[0]


def default_ql_layout() -> str:
    if os.name != "nt":
        return "uk"
    layout = windows_keyboard_layout()
    language_id = int(layout or 0) & 0xFFFF
    return "fr" if (language_id & 0x03FF) == 0x000C else "uk"


def crc8(data: bytes) -> int:
    value = 0
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = ((value << 1) ^ 0x07) & 0xFF if value & 0x80 else (value << 1) & 0xFF
    return value


def parse_number(value: str) -> int:
    return int(value, 0)


QDOS_SYSVARS_BASE = 0x028000
QDOS_SYSVARS = (
    ("SV_CHEAP", 0x04, "common heap start"),
    ("SV_CHPFR", 0x08, "first free common-heap block"),
    ("SV_FREE",  0x0C, "filing-system free-memory boundary"),
    ("SV_BASIC", 0x10, "SuperBASIC area"),
    ("SV_TRNSP", 0x14, "transient-program area"),
    ("SV_TRNFR", 0x18, "first free transient block"),
    ("SV_RESPR", 0x1C, "resident-procedure area"),
    ("SV_RAMT",  0x20, "end of RAM plus one"),
)


def decode_qdos_memory_map(data: bytes) -> dict[str, int]:
    if len(data) < 0x24:
        raise ValueError("The QDOS system-variable snapshot is incomplete.")
    ident = int.from_bytes(data[0:4], "big")
    if ident != 0xD2540000:
        raise RuntimeError(
            f"No standard QDOS system variables were found at "
            f"0x{QDOS_SYSVARS_BASE:06x} (identifier=0x{ident:08x})."
        )
    result = {"SV_IDENT": ident}
    for name, offset, _description in QDOS_SYSVARS:
        result[name] = int.from_bytes(data[offset:offset + 4], "big")
    return result


def kib(value: int) -> str:
    return f"{value} bytes ({value / 1024:.1f} KiB)"


def remote_path_bytes(value: str, *, allow_empty: bool = False) -> bytes:
    normalized = value.replace("\\", "/").strip("/")
    if not normalized:
        if allow_empty:
            return b""
        raise ValueError("A path inside NanoQL/Drive1 is required.")
    components = normalized.split("/")
    if any(component in ("", ".", "..") for component in components):
        raise ValueError("Drive1 paths cannot contain empty, '.' or '..' components.")
    try:
        encoded = normalized.encode("ascii")
    except UnicodeEncodeError as error:
        raise ValueError(
            "Drive1 paths currently support printable ASCII characters only."
        ) from error
    forbidden = set(b'\\:*?"<>|')
    if any(byte < 0x20 or byte > 0x7E or byte in forbidden for byte in encoded):
        raise ValueError("The Drive1 path contains a character unsupported by FAT.")
    if len(encoded) > 200:
        raise ValueError("The Drive1 path cannot exceed 200 characters.")
    return encoded


def file_crc32(path: Path) -> int:
    checksum = 0
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum = zlib.crc32(block, checksum)
    return checksum & 0xFFFFFFFF


def is_link_response_error(error: Exception) -> bool:
    message = str(error)
    return any(fragment in message for fragment in (
        "Missing or invalid response",
        "Incomplete NanoQL Link response",
        "Invalid NanoQL Link version or sequence",
        "Invalid NanoQL Link CRC",
    ))


def download_drive1_tree(
    link: "NanoQLLink",
    local_root: Path,
    remote_path: str = "",
    excluded_path: str = "MDV1.mdv",
) -> int:
    count = 0
    for name, _size, is_directory in link.filesystem_list(remote_path):
        child_remote = f"{remote_path}/{name}" if remote_path else name
        if child_remote.casefold() == excluded_path.casefold():
            continue
        child_local = local_root.joinpath(*child_remote.split("/"))
        if is_directory:
            child_local.mkdir(parents=True, exist_ok=True)
            count += download_drive1_tree(
                link, local_root, child_remote, excluded_path
            )
        else:
            print(f"Reading /NanoQL/Drive1/{child_remote}...")
            link.filesystem_get(child_remote, child_local)
            count += 1
    return count


def find_port(explicit: str | None) -> str:
    if explicit:
        return explicit
    candidates = []
    for port in list_ports.comports():
        description = f"{port.description} {port.manufacturer or ''}".lower()
        nanoql_id = port.vid == 0xFFFF and port.pid == 0x4E51
        if nanoql_id or "nanoql" in description or "bouffalo" in description or "bl616" in description:
            candidates.append(port.device)
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        raise RuntimeError("NanoQL Link was not detected. Specify --port COMx or /dev/ttyACMx.")
    raise RuntimeError("Multiple compatible ports were detected. Specify --port.")


class NanoQLLink:
    def __init__(self, port: str, timeout: float = 2.0,
                 keyboard_layout: str = "host", ql_layout: str = "uk"):
        self.port = port
        self.timeout = timeout
        self.serial = self._open_serial()
        self.sequence = 0
        self.reconnect_count = 0
        self.drive_firmware_build: str | None = None
        self.keyboard_layout = keyboard_layout
        self.ql_layout = ql_layout

    def _open_serial(self):
        return serial.Serial(
            self.port, 115200, timeout=self.timeout,
            write_timeout=self.timeout,
        )

    def _reconnect(self, deadline: float) -> None:
        try:
            self.serial.close()
        except Exception:
            pass
        print("\nNanoQL Link disconnected; waiting for the same serial port...", flush=True)
        last_error: Exception | None = None
        while time.monotonic() < deadline:
            try:
                self.serial = self._open_serial()
                time.sleep(0.15)
                self.serial.reset_input_buffer()
                self.reconnect_count += 1
                print("NanoQL Link reconnected; resuming the transfer.", flush=True)
                return
            except (serial.SerialException, PermissionError, OSError) as error:
                last_error = error
                time.sleep(0.25)
        raise RuntimeError(
            f"NanoQL Link did not return on {self.port} within 15 seconds."
        ) from last_error

    def close(self) -> None:
        if getattr(self, "abandon_serial_on_close", False):
            # The MDV7 completion acknowledgement is followed immediately by
            # an FPGA/Companion transition. On Windows, pyserial's CloseHandle
            # can then block forever on the vanished CDC device. Marking the
            # object closed lets the process exit; Windows releases the handle.
            try:
                self.serial.is_open = False
            except (AttributeError, serial.SerialException, OSError):
                pass
            return
        try:
            self.serial.close()
        except (serial.SerialException, PermissionError, OSError):
            # Commands such as FPGA programming and mdv-sync deliberately
            # reboot the BL616 after their response, so the port may already
            # have disappeared when the client closes it.
            pass

    def transact(self, spi_payload: bytes) -> bytes:
        if not 1 <= len(spi_payload) <= MAX_LINK_PAYLOAD:
            raise ValueError(
                f"A NanoQL Link transaction must contain between 1 and "
                f"{MAX_LINK_PAYLOAD} bytes."
            )
        self.sequence = (self.sequence + 1) & 0xFF
        body = bytes((PROTOCOL_VERSION, self.sequence, len(spi_payload))) + spi_payload
        frame = REQUEST_MAGIC + body + bytes((crc8(body),))
        reconnect_deadline = time.monotonic() + 15.0
        attempts = 0
        while True:
            try:
                self.serial.reset_input_buffer()
                self.serial.write(frame)
                self.serial.flush()

                header = self.serial.read(5)
                if len(header) != 5 or header[:2] != RESPONSE_MAGIC:
                    raise RuntimeError(
                        "Missing or invalid response from the NanoQL Link BL616 firmware."
                    )
                version, sequence, length = header[2], header[3], header[4]
                payload_and_crc = self.serial.read(length + 1)
                if len(payload_and_crc) != length + 1:
                    raise RuntimeError("Incomplete NanoQL Link response.")
                response_body = bytes((version, sequence, length)) + payload_and_crc[:-1]
                if version != PROTOCOL_VERSION or sequence != self.sequence:
                    raise RuntimeError("Invalid NanoQL Link version or sequence.")
                if crc8(response_body) != payload_and_crc[-1]:
                    raise RuntimeError("Invalid NanoQL Link CRC.")
                payload = payload_and_crc[:-1]
                if len(payload) == 2 and payload[0] == 0xFF:
                    error_code = payload[1]
                    if error_code == 3 and len(spi_payload) <= 17 and attempts < 3:
                        # Windows may briefly suspend CDC when the port opens.
                        # A frame already in flight can then be discarded; all
                        # NanoQL SPI commands are state-setting and safe to retry.
                        attempts += 1
                        time.sleep(0.05)
                        self.serial.reset_input_buffer()
                        continue
                    if 0x40 <= error_code <= 0x5F:
                        fatfs_code = error_code & 0x1F
                        fatfs_name = FATFS_ERRORS.get(
                            fatfs_code, f"unknown error {fatfs_code}"
                        )
                        detail = f"FatFs {fatfs_name}"
                    else:
                        detail = FIRMWARE_ERRORS.get(error_code, f"error {error_code}")
                    raise RuntimeError(
                        f"The BL616 firmware rejected the request: {detail}."
                    )
                return payload
            except (serial.SerialException, PermissionError, OSError):
                attempts += 1
                if attempts > 3 or time.monotonic() >= reconnect_deadline:
                    raise
                self._reconnect(reconnect_deadline)

    def status_payload(self) -> bytes:
        # SPI is full duplex: the byte selected by CMD_STATUS appears during
        # the following transfer, so 16 status bytes require 16 dummy bytes.
        rx = self.transact(bytes((CMD_STATUS,)) + bytes(16))
        signature_at = rx.find(b"NQL1")
        if signature_at < 0 or signature_at + 4 >= len(rx):
            raise RuntimeError("The bitstream did not respond as NanoQL Link v1.")
        return rx[signature_at:]

    def status(self) -> int:
        return self.status_payload()[4]

    def keyboard_report_count(self) -> int:
        payload = self.status_payload()
        if len(payload) < 6:
            raise RuntimeError(
                "This bitstream does not expose the keyboard-consumption counter."
            )
        return payload[5]

    def qlsd_status(self) -> tuple[int, int, bytes, int, int, bytes]:
        payload = self.status_payload()
        if len(payload) < 16:
            raise RuntimeError("This bitstream does not expose QL-SD diagnostics.")
        flags = payload[6]
        lba = int.from_bytes(payload[7:10], "big")
        header = bytes(payload[10:14])
        byte_count = int.from_bytes(payload[14:16], "big")
        detail_rx = self.transact(bytes((CMD_QLSD_DIAG,)) + bytes(16))
        detail_at = detail_rx.find(b"QSD1")
        if detail_at < 0 or detail_at + 16 > len(detail_rx):
            raise RuntimeError("This bitstream does not expose complete QL-SD diagnostics.")
        detail = detail_rx[detail_at:detail_at + 16]
        crc32 = int.from_bytes(detail[4:8], "big")
        sample = bytes(detail[8:16])
        return flags, lba, header, byte_count, crc32, sample

    def cpu_diagnostic(self) -> tuple[int, int]:
        rx = self.transact(bytes((CMD_CPU_DIAG,)) + bytes(16))
        detail_at = rx.find(b"CPU1")
        if detail_at < 0 or detail_at + 9 > len(rx):
            raise RuntimeError("This bitstream does not expose CPU diagnostics.")
        detail = rx[detail_at:detail_at + 9]
        return detail[4] & 0x03, int.from_bytes(detail[5:9], "big")

    def configured_ql_layout(self) -> str:
        rx = self.transact(bytes((CMD_CPU_DIAG,)) + bytes(16))
        detail_at = rx.find(b"CPU1")
        if detail_at < 0 or detail_at + 10 > len(rx):
            raise RuntimeError("This bitstream does not expose the ROM keyboard layout.")
        return "fr" if (rx[detail_at + 9] & 0x01) else "uk"

    def mdv_diagnostic(
        self,
    ) -> tuple[int, int, int, int, int, int, int]:
        rx = self.transact(bytes((CMD_MDV_DIAG,)) + bytes(16))
        detail_at = rx.find(b"MDV3")
        if detail_at < 0 or detail_at + 16 > len(rx):
            raise RuntimeError("This bitstream does not expose Microdrive diagnostics.")
        detail = rx[detail_at:detail_at + 16]
        flags = detail[4]
        byte_position = int.from_bytes(detail[5:8], "big")
        rx_count = int.from_bytes(detail[8:10], "big")
        read_count = int.from_bytes(detail[10:12], "big")
        missed_count = int.from_bytes(detail[12:14], "big")
        return (flags, byte_position, rx_count, read_count,
                missed_count, detail[14], detail[15])

    def mdv_header_trace(self) -> tuple[int, bytes]:
        rx = self.transact(bytes((CMD_MDV_TRACE,)) + bytes(16))
        detail_at = rx.find(b"MT")
        if detail_at < 0 or detail_at + 16 > len(rx):
            raise RuntimeError(
                "This bitstream does not expose the Microdrive CPU trace."
            )
        detail = rx[detail_at:detail_at + 16]
        count = min(detail[2], 16)
        return count, bytes(detail[3:3 + min(count, 13)])

    def mdv_data_trace(self) -> tuple[int, bytes]:
        rx = self.transact(bytes((CMD_MDV_DATA_TRACE,)) + bytes(16))
        detail_at = rx.find(b"MB")
        if detail_at < 0 or detail_at + 16 > len(rx):
            raise RuntimeError(
                "This bitstream does not expose the Microdrive data trace."
            )
        detail = rx[detail_at:detail_at + 16]
        count = ((detail[2] & 0x03) << 8) | detail[3]
        return count, bytes(detail[4:16])

    def measure_cpu_rate(self, interval: float = 0.25) -> tuple[int, float]:
        speed, first_count = self.cpu_diagnostic()
        started = time.monotonic()
        time.sleep(interval)
        current_speed, second_count = self.cpu_diagnostic()
        elapsed = time.monotonic() - started
        if current_speed != speed:
            raise RuntimeError("The FPGA CPU mode changed while it was being measured.")
        pulses = (second_count - first_count) & 0xFFFFFFFF
        return speed, pulses / elapsed

    def filesystem_info(self) -> tuple[int, int]:
        response = self.transact(bytes((CMD_FS_INFO,)))
        if len(response) < 7 or response[:4] != b"NFS1":
            raise RuntimeError(
                "The installed BL616 firmware does not support NanoQL Drive1."
            )
        version, capabilities, max_path = response[4], response[5], response[6]
        if version != 1:
            raise RuntimeError(f"Unsupported NanoQL Drive1 protocol {version}.")
        self.drive_firmware_build = (
            response[7:].decode("ascii", errors="replace")
            if len(response) > 7 else "legacy"
        )
        return capabilities, max_path

    def filesystem_cancel(self) -> None:
        self.transact(bytes((CMD_FS_CANCEL,)))

    def microdrive_sync_control(self, mount: bool) -> None:
        action = "mount" if mount else "unmount"
        print(f"[MDV control] Querying firmware before {action}...", flush=True)
        capabilities, _ = self.filesystem_info()
        firmware_build = getattr(self, "drive_firmware_build", None) or "legacy"
        print(
            f"[MDV control] Firmware build: {firmware_build}; "
            f"capabilities: 0x{capabilities:02x}.",
            flush=True,
        )
        if not capabilities & 0x20:
            raise RuntimeError(
                "The installed BL616 firmware does not support automatic MDV1 mounting."
            )
        previous_timeout = self.serial.timeout
        self.serial.timeout = 30.0
        try:
            if not mount:
                print("[MDV 1/1] Requesting unmount and Companion pause...", flush=True)
                response = self.transact(bytes((CMD_FS_MDV_CONTROL, 0)))
                print(f"[MDV 1/1] Unmount acknowledged: {response.hex(' ')}.", flush=True)
            elif firmware_build in ("MDV7", "MDV8", "MDV9", "MD10"):
                print("[MDV 1/2] Opening the uploaded MDV1 image...", flush=True)
                response = self.transact(bytes((CMD_FS_MDV_CONTROL, 3)))
                print(f"[MDV 1/2] Image open acknowledged: {response.hex(' ')}.", flush=True)
                completion = (
                    "Mounting MDV1 and returning SPI to Companion"
                    if firmware_build == "MD10"
                    else "Saving settings and returning SPI to Companion"
                    if firmware_build == "MDV9"
                    else "Saving settings, restarting QDOS, and returning SPI to Companion"
                )
                print(f"[MDV 2/2] {completion}...", flush=True)
                response = self.transact(bytes((CMD_FS_MDV_CONTROL, 4)))
                print(
                    f"[MDV 2/2] Completion acknowledged: {response.hex(' ')}.",
                    flush=True,
                )
                # The firmware now resets QDOS and changes ownership of the
                # shared SPI service. Do not ask pyserial to synchronously close
                # a Windows CDC handle while that USB transition is in flight.
                if firmware_build not in ("MDV9", "MD10"):
                    self.abandon_serial_on_close = True
                time.sleep(0.25)
            elif firmware_build in ("MDV5", "MDV6"):
                print("[MDV 1/5] Opening the uploaded MDV1 image...", flush=True)
                response = self.transact(bytes((CMD_FS_MDV_CONTROL, 3)))
                print(f"[MDV 1/5] Image open acknowledged: {response.hex(' ')}.", flush=True)
                print("[MDV 2/5] Saving nanoql.ini...", flush=True)
                response = self.transact(bytes((CMD_FS_MDV_CONTROL, 4)))
                print(f"[MDV 2/5] Settings save acknowledged: {response.hex(' ')}.", flush=True)
                # Let CherryUSB deliver the previous IN-completion callback
                # before the command that hands the SPI task back to Companion.
                time.sleep(0.1)
                print("[MDV 3/5] Returning the SPI service to Companion...", flush=True)
                response = self.transact(bytes((CMD_FS_MDV_CONTROL, 5)))
                print(f"[MDV 3/5] Resume acknowledged: {response.hex(' ')}.", flush=True)
                print("[MDV 4/5] Clearing stale reset state...", flush=True)
                response = self.transact(bytes((CMD_FS_MDV_CONTROL, 2)))
                print(f"[MDV 4/5] Reset state acknowledged: {response.hex(' ')}.", flush=True)
                print("[MDV 5/5] Requesting FPGA-local QDOS restart...", flush=True)
                self.qdos()
                print("[MDV 5/5] QDOS restart acknowledged.", flush=True)
            else:
                print("[MDV legacy] Mounting image and saving settings...", flush=True)
                self.transact(bytes((CMD_FS_MDV_CONTROL, 1)))
                # The mount acknowledgement precedes the FPGA-local QDOS
                # restart. Wait for that operation, then force the persistent
                # Companion reset low and request one final bounded restart.
                self.transact(bytes((CMD_FS_MDV_CONTROL, 2)))
                self.qdos()
        finally:
            self.serial.timeout = previous_timeout

    def filesystem_list(self, remote_path: str = "") -> list[tuple[str, int, bool]]:
        path = remote_path_bytes(remote_path, allow_empty=True)
        self.filesystem_info()
        self.transact(bytes((CMD_FS_LIST_BEGIN,)) + path)
        entries: list[tuple[str, int, bool]] = []
        try:
            while True:
                response = self.transact(bytes((CMD_FS_LIST_NEXT,)))
                if response == b"\x00":
                    break
                if len(response) < 6 or response[0] not in (1, 2):
                    raise RuntimeError("Invalid NanoQL Drive1 directory response.")
                name_length = response[5]
                if len(response) != 6 + name_length:
                    raise RuntimeError("Truncated NanoQL Drive1 directory entry.")
                name = response[6:].decode("ascii")
                size = int.from_bytes(response[1:5], "big")
                entries.append((name, size, response[0] == 2))
        except Exception:
            try:
                self.filesystem_cancel()
            except Exception:
                pass
            raise
        return entries

    def filesystem_mkdir(self, remote_path: str) -> None:
        path = remote_path_bytes(remote_path)
        self.filesystem_info()
        self.transact(bytes((CMD_FS_MKDIR,)) + path)

    def filesystem_delete(self, remote_path: str) -> None:
        path = remote_path_bytes(remote_path)
        self.filesystem_info()
        self.transact(bytes((CMD_FS_DELETE,)) + path)

    def filesystem_put(self, source: Path, remote_path: str) -> None:
        source = source.expanduser().resolve()
        if not source.is_file():
            raise FileNotFoundError(source)
        path = remote_path_bytes(remote_path)
        size = source.stat().st_size
        if size > 0xFFFFFFFF:
            raise ValueError("NanoQL Drive1 currently supports files up to 4 GiB.")
        checksum = file_crc32(source)
        self.filesystem_info()
        begin = (
            bytes((CMD_FS_PUT_BEGIN,))
            + size.to_bytes(4, "big")
            + checksum.to_bytes(4, "big")
            + path
        )
        # Some microSD cards pause for several seconds while allocating or
        # erasing an internal flash block. The normal two-second interactive
        # timeout is too short for filesystem writes, especially through the
        # macOS CDC driver. Reads still complete as soon as data is available.
        normal_timeout = self.serial.timeout
        self.serial.timeout = max(float(normal_timeout or 0), 15.0)
        try:
            print(
                f"[SD PUT 1/4] Opening /NanoQL/Drive1/{remote_path} "
                f"({size} bytes, CRC32 0x{checksum:08x})...",
                flush=True,
            )
            begin_response = self.transact(begin)
            print(
                f"[SD PUT 1/4] Open acknowledged: "
                f"{begin_response.hex(' ') or '(empty)' }.",
                flush=True,
            )
            if len(begin_response) >= 2 and begin_response[1] == 1:
                print(
                    "microSD mode: direct synchronized update "
                    "(no temporary rename/delete).",
                    flush=True,
                )
            sent = 0
            inline_verification = None
            try:
                print("[SD PUT 2/4] Sending file data...", flush=True)
                with source.open("rb") as stream:
                    while True:
                        block = stream.read(240)
                        if not block:
                            break
                        response = self.transact(
                            bytes((CMD_FS_PUT_DATA,))
                            + sent.to_bytes(4, "big")
                            + block
                        )
                        if len(response) not in (4, 12):
                            raise RuntimeError(
                                "NanoQL Drive1 returned an invalid data acknowledgement."
                            )
                        acknowledged = int.from_bytes(response[:4], "big")
                        sent += len(block)
                        if acknowledged != sent:
                            raise RuntimeError(
                                "NanoQL Drive1 acknowledged an invalid offset."
                            )
                        if len(response) == 12:
                            inline_verification = response[4:]
                            print(
                                "\n[SD PUT 2/4] Final packet includes "
                                f"verification: {inline_verification.hex(' ')}.",
                                flush=True,
                            )
                        percent = 100 if size == 0 else sent * 100 // size
                        print(
                            f"\rDrive1 upload: {percent:3d}%",
                            end="", flush=True,
                        )
                print("\n[SD PUT 3/4] Finalizing the file on microSD...", flush=True)
                # The firmware validates the accumulated size/CRC, closes the
                # FatFs file once, then atomically installs it.
                self.serial.timeout = max(self.serial.timeout, 30.0)
                if inline_verification is not None:
                    print(
                        "[SD PUT 3/4] Using verification cached in the final "
                        "data acknowledgement; no COMMIT command is sent.",
                        flush=True,
                    )
                    response = inline_verification
                else:
                    print(
                        "[SD PUT 3/4] Sending explicit COMMIT command...",
                        flush=True,
                    )
                    try:
                        response = self.transact(bytes((CMD_FS_PUT_COMMIT,)))
                    except RuntimeError as first_error:
                        if not is_link_response_error(first_error):
                            raise
                        # A slow card can complete f_sync/rename just as macOS
                        # resets the CDC read. Retrying COMMIT is safe while the
                        # upload session is still open. If the first request did
                        # complete, the second one reports an idle session and we
                        # validate the installed file directly instead.
                        time.sleep(0.25)
                        try:
                            response = self.transact(bytes((CMD_FS_PUT_COMMIT,)))
                        except RuntimeError:
                            remote_size, remote_crc = self.filesystem_crc32(remote_path)
                            if remote_size != size or remote_crc != checksum:
                                raise first_error
                            response = (
                                remote_size.to_bytes(4, "big")
                                + remote_crc.to_bytes(4, "big")
                            )
                commit_steps = {
                    1: "Preparing the existing destination...",
                    2: "Installing the uploaded file...",
                    3: "Removing the previous backup...",
                }
                while len(response) == 2 and response[0] == 0xFE:
                    phase = response[1]
                    print(
                        commit_steps.get(
                            phase, "Completing the microSD update..."
                        ),
                        flush=True,
                    )
                    response = self.transact(bytes((CMD_FS_PUT_COMMIT,)))
                if len(response) != 8:
                    raise RuntimeError(
                        "Invalid NanoQL Drive1 upload verification response."
                    )
                remote_size = int.from_bytes(response[:4], "big")
                remote_crc = int.from_bytes(response[4:8], "big")
                if remote_size != size or remote_crc != checksum:
                    raise RuntimeError(
                        "NanoQL Drive1 returned a different size or CRC32."
                    )
                if size == 0:
                    print("\rDrive1 upload: 100%", end="", flush=True)
                print("[SD PUT 4/4] Size and CRC32 verified.", flush=True)
            except Exception:
                try:
                    self.filesystem_cancel()
                except Exception:
                    pass
                raise
        finally:
            self.serial.timeout = normal_timeout

    def filesystem_crc32(self, remote_path: str) -> tuple[int, int]:
        """Read a Drive1 file without storing it and return size and CRC32."""
        path = remote_path_bytes(remote_path)
        response = self.transact(bytes((CMD_FS_GET_BEGIN,)) + path)
        if len(response) != 4:
            raise RuntimeError("Invalid NanoQL Drive1 file verification response.")
        size = int.from_bytes(response, "big")
        received = 0
        checksum = 0
        try:
            while received < size:
                requested = min(240, size - received)
                response = self.transact(
                    bytes((CMD_FS_GET_DATA,))
                    + received.to_bytes(4, "big")
                    + bytes((requested,))
                )
                if not response or response[0] != len(response) - 1:
                    raise RuntimeError("Invalid NanoQL Drive1 verification data.")
                block = response[1:]
                if not block or len(block) > requested:
                    raise RuntimeError("Invalid NanoQL Drive1 verification block.")
                checksum = zlib.crc32(block, checksum)
                received += len(block)
            self.transact(bytes((CMD_FS_GET_END,)))
        except Exception:
            try:
                self.filesystem_cancel()
            except Exception:
                pass
            raise
        return size, checksum & 0xFFFFFFFF

    def filesystem_get(self, remote_path: str, destination: Path) -> None:
        path = remote_path_bytes(remote_path)
        destination = destination.expanduser().resolve()
        temporary = destination.with_name(destination.name + ".nanoql-part")
        self.filesystem_info()
        response = self.transact(bytes((CMD_FS_GET_BEGIN,)) + path)
        if len(response) != 4:
            raise RuntimeError("Invalid NanoQL Drive1 download response.")
        size = int.from_bytes(response, "big")
        destination.parent.mkdir(parents=True, exist_ok=True)
        received = 0
        try:
            with temporary.open("wb") as stream:
                while received < size:
                    requested = min(240, size - received)
                    response = self.transact(
                        bytes((CMD_FS_GET_DATA,))
                        + received.to_bytes(4, "big")
                        + bytes((requested,))
                    )
                    if not response or response[0] != len(response) - 1:
                        raise RuntimeError("Invalid NanoQL Drive1 data block.")
                    block = response[1:]
                    if not block or len(block) > requested:
                        raise RuntimeError("NanoQL Drive1 returned an invalid data length.")
                    stream.write(block)
                    received += len(block)
                    print(
                        f"\rDrive1 download: {received * 100 // max(size, 1):3d}%",
                        end="", flush=True,
                    )
            self.transact(bytes((CMD_FS_GET_END,)))
            if temporary.stat().st_size != size:
                raise RuntimeError("Downloaded NanoQL Drive1 file has the wrong size.")
            os.replace(temporary, destination)
            if size == 0:
                print("\rDrive1 download: 100%", end="", flush=True)
            print()
        except Exception:
            temporary.unlink(missing_ok=True)
            try:
                self.filesystem_cancel()
            except Exception:
                pass
            raise

    def hold(self) -> None:
        self.transact(bytes((CMD_HOLD,)))
        self.wait_idle(expect_hold=True)

    def wait_idle(self, expect_hold: bool, timeout: float = 2.0) -> int:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            status = self.status()
            ready = bool(status & 0x01)
            busy = bool(status & 0x02)
            error = bool(status & 0x04)
            held = bool(status & 0x08)
            if error:
                raise RuntimeError(f"The FPGA rejected the command (status=0x{status:02x}).")
            if ready and not busy and held == expect_hold:
                return status
            time.sleep(0.005)
        raise TimeoutError("The FPGA did not become available before the timeout.")

    def write(self, address: int, data: bytes) -> None:
        if address < 0x020000 or address + len(data) > 0x040000:
            raise ValueError("The block must remain within QL RAM 0x020000-0x03ffff.")
        for offset in range(0, len(data), 8):
            block = data[offset : offset + 8]
            block_address = address + offset
            request = bytes((CMD_WRITE,)) + block_address.to_bytes(3, "big") + bytes((len(block),)) + block
            self.transact(request)
            self.wait_idle(expect_hold=True)

    def read(self, address: int, length: int, *, live: bool = False) -> bytes:
        if length < 0 or address < 0x020000 or address + length > 0x040000:
            raise ValueError("The block must remain within QL RAM 0x020000-0x03ffff.")
        result = bytearray()
        for offset in range(0, length, 8):
            block_length = min(8, length - offset)
            block_address = address + offset
            request = (bytes((CMD_READ,)) + block_address.to_bytes(3, "big") +
                       bytes((block_length,)))
            self.transact(request)
            self.wait_idle(expect_hold=not live)
            response = self.transact(bytes((CMD_READ_RESULT,)) + bytes(8))
            if len(response) < block_length:
                raise RuntimeError("Incomplete RAM read response.")
            result.extend(response[-8:][:block_length])
        return bytes(result)

    def qdos_memory_map(self) -> dict[str, int]:
        # A live host read is arbitrated between normal CPU SDRAM cycles. Read
        # twice so that moving QDOS boundaries cannot produce a torn snapshot.
        previous = self.read(QDOS_SYSVARS_BASE, 0x24, live=True)
        for _attempt in range(4):
            current = self.read(QDOS_SYSVARS_BASE, 0x24, live=True)
            if current == previous:
                return decode_qdos_memory_map(current)
            previous = current
        raise RuntimeError(
            "QDOS memory boundaries changed throughout the snapshot; "
            "retry at an idle SuperBASIC prompt."
        )

    def execute(self, stack_pointer: int, program_counter: int) -> int:
        payload = bytes((CMD_EXEC,)) + struct.pack(">II", stack_pointer, program_counter)
        self.transact(payload)
        self.wait_idle(expect_hold=False)
        time.sleep(0.25)
        return self.status()

    def qdos(self) -> None:
        self.transact(bytes((CMD_QDOS,)))

    def program_fpga(self, bitstream: bytes) -> None:
        if not bitstream or len(bitstream) > 2 * 1024 * 1024:
            raise ValueError("The FPGA bitstream must be between 1 byte and 2 MiB.")
        checksum = zlib.crc32(bitstream) & 0xFFFFFFFF
        previous_timeout = self.serial.timeout
        try:
            self.transact(
                bytes((CMD_FPGA_BEGIN,)) +
                struct.pack(">II", len(bitstream), checksum)
            )
            sent = 0
            for offset in range(0, len(bitstream), MAX_LINK_PAYLOAD - 1):
                block = bitstream[offset:offset + MAX_LINK_PAYLOAD - 1]
                self.transact(bytes((CMD_FPGA_DATA,)) + block)
                sent += len(block)
                percent = sent * 100 // len(bitstream)
                print(f"\rFPGA transfer: {percent:3d}%", end="", flush=True)
            print()

            self.serial.timeout = 120
            self.transact(bytes((CMD_FPGA_PROGRAM,)))
        finally:
            self.serial.timeout = previous_timeout

    def key_event(self, usage: int, pressed: bool) -> None:
        if not 0 <= usage <= 0x7F:
            raise ValueError("HID key code is out of range.")
        matrix_contact = (None if usage in REMOTE_MENU_USAGES
                          else QL_USAGE_TO_MATRIX.get(usage))
        event_code = matrix_contact if matrix_contact is not None else usage
        event = event_code if pressed else event_code | 0x80
        request = (bytes((CMD_KEY, KEY_DIRECT_MATRIX, event))
                   if matrix_contact is not None else bytes((CMD_KEY, event)))
        try:
            self.transact(request)
        except RuntimeError as error:
            if not is_link_response_error(error):
                raise
            # Keyboard reports set an absolute pressed/released state, so a
            # single retry cannot duplicate text even if only the reply was
            # lost by the host CDC driver.
            time.sleep(0.02)
            self.transact(request)

    def tap_key(self, usage: int, hold_time: float = 0.05,
                release_time: float = 0.03, wait_consumed: bool = False,
                consume_timeout: float = 5.0) -> None:
        report_before = self.keyboard_report_count() if wait_consumed else 0
        self.key_event(usage, True)
        try:
            time.sleep(hold_time)
            if wait_consumed:
                deadline = time.monotonic() + consume_timeout
                while self.keyboard_report_count() == report_before:
                    if time.monotonic() >= deadline:
                        raise TimeoutError(
                            f"QL IPC did not consume HID key 0x{usage:02x}."
                        )
                    time.sleep(0.02)
        finally:
            self.key_event(usage, False)
        time.sleep(release_time)

    def character_key(self, character: str) -> tuple[int, tuple[int, ...]]:
        if self.ql_layout == "fr" and character in QL_FRENCH_KEYS:
            return QL_FRENCH_KEYS[character]
        if self.ql_layout != "fr" and len(character) == 1:
            # English QL ROMs do not provide accented Latin letters. Preserve
            # the letter rather than interpreting the PC key's physical number
            # row position (for example AZERTY e-acute becoming "2").
            folded = "".join(
                value for value in unicodedata.normalize("NFKD", character)
                if not unicodedata.combining(value)
            )
            folded = {"ø": "o", "Ø": "O", "ł": "l", "Ł": "L",
                      "đ": "d", "Đ": "D", "ð": "d", "Ð": "D",
                      "þ": "t", "Þ": "T"}.get(folded, folded)
            if len(folded) == 1 and folded.isascii() and folded.isalpha():
                character = folded
        if "A" <= character <= "Z":
            return ASCII_KEYS[character.lower()][0], (MOD_LEFT_SHIFT,)
        if character in ASCII_KEYS:
            usage, shifted = ASCII_KEYS[character]
            return usage, (MOD_LEFT_SHIFT,) if shifted else ()
        if self.keyboard_layout == "host":
            host_key = windows_character_key(character)
            if host_key is not None:
                return host_key
        raise ValueError(f"Unsupported character: {character!r}")

    def type_character(self, character: str, hold_time: float = 0.05,
                       release_time: float = 0.03,
                       wait_consumed: bool = False,
                       modifier_release_time: float = 0.005) -> None:
        control_usage = {
            "\n": 0x28, "\r": 0x28, "\x1b": 0x29, "\t": 0x2B,
        }.get(character)
        if control_usage is not None:
            self.tap_key(
                control_usage,
                hold_time=max(0.15, hold_time),
                release_time=max(0.12, release_time),
                wait_consumed=wait_consumed,
            )
            return
        if character == "\b":
            # The original QL has no Backspace key. MiST/MiSTer implement it
            # as the native QL combination CTRL+LEFT.
            self.key_event(MOD_LEFT_CTRL, True)
            time.sleep(0.08)
            self.tap_key(0x50, hold_time=0.15)
            time.sleep(0.05)
            self.key_event(MOD_LEFT_CTRL, False)
            time.sleep(0.03)
            return

        usage, modifiers = self.character_key(character)
        for modifier in modifiers:
            self.key_event(modifier, True)
        if modifiers:
            time.sleep(0.008)
        self.tap_key(
            usage,
            hold_time=hold_time,
            release_time=release_time,
            wait_consumed=wait_consumed,
        )
        if modifiers:
            time.sleep(0.005)
        for modifier in reversed(modifiers):
            self.key_event(modifier, False)
        if modifiers:
            time.sleep(modifier_release_time)

    def type_text(self, value: str, hold_time: float = 0.05,
                  release_time: float = 0.03,
                  wait_consumed: bool = False,
                  modifier_release_time: float = 0.005) -> None:
        for character in value:
            self.type_character(
                character, hold_time, release_time, wait_consumed,
                modifier_release_time
            )


def stop_requested(stop_file: Path | None) -> bool:
    return stop_file is not None and stop_file.exists()


def interactive_keyboard_windows(link: NanoQLLink,
                                 stop_file: Path | None = None) -> None:
    import msvcrt

    print(f"NanoQL keyboard active (QL {link.ql_layout.upper()} profile). "
          "Keys are held in real time; press F6 to return to the terminal.")
    get_async_key_state = ctypes.windll.user32.GetAsyncKeyState
    keymap = windows_realtime_keymap()
    modifier_vks = {0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5}
    ordinary_keymap = {
        virtual_key: usage for virtual_key, usage in keymap.items()
        if virtual_key not in modifier_vks
    }

    def host_modifiers() -> tuple[bool, bool, bool, bool, bool, bool]:
        return tuple(
            bool(get_async_key_state(virtual_key) & 0x8000)
            for virtual_key in (0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5)
        )

    previous_keys = {
        virtual_key for virtual_key in ordinary_keymap
        if get_async_key_state(virtual_key) & 0x8000
    }
    previous_modifiers = host_modifiers()
    active_bindings: dict[int, tuple[set[int], bool]] = {}
    remote_pressed: set[int] = set()
    f6_previous = bool(get_async_key_state(0x75) & 0x8000)

    try:
        while True:
            if stop_requested(stop_file):
                break
            f6_pressed = bool(get_async_key_state(0x75) & 0x8000)
            if f6_pressed and not f6_previous:
                break
            f6_previous = f6_pressed

            current_keys = {
                virtual_key for virtual_key in ordinary_keymap
                if get_async_key_state(virtual_key) & 0x8000
            }
            current_modifiers = host_modifiers()
            if (current_keys != previous_keys or
                    current_modifiers != previous_modifiers):
                previous_keys = current_keys
                previous_modifiers = current_modifiers
                active_bindings.clear()
                for virtual_key in current_keys:
                    fallback_usage = ordinary_keymap[virtual_key]
                    character = windows_virtual_key_character(virtual_key)
                    if character:
                        try:
                            usage, target_modifiers = link.character_key(character)
                            active_bindings[virtual_key] = (
                                {usage, *target_modifiers}, True
                            )
                            continue
                        except ValueError:
                            pass
                    active_bindings[virtual_key] = ({fallback_usage}, False)

                desired: set[int] = set()
                translated_active = False
                for usages, translated in active_bindings.values():
                    desired.update(usages)
                    translated_active |= translated

                left_shift, right_shift, left_ctrl, right_ctrl, \
                    left_alt, right_alt = current_modifiers
                if left_ctrl and not right_alt:
                    desired.add(0x68)
                if right_ctrl and not right_alt:
                    desired.add(0x6C)
                if not translated_active:
                    if left_shift:
                        desired.add(0x69)
                    if right_shift:
                        desired.add(0x6D)
                    if left_alt:
                        desired.add(0x6A)
                    if right_alt:
                        desired.add(0x6E)

                modifier_usages = {0x68, 0x69, 0x6A, 0x6C, 0x6D, 0x6E}
                releases = sorted(
                    remote_pressed - desired,
                    key=lambda usage: usage in modifier_usages,
                )
                presses = sorted(
                    desired - remote_pressed,
                    key=lambda usage: usage not in modifier_usages,
                )
                ordinary_releases = [
                    usage for usage in releases if usage not in modifier_usages
                ]
                modifier_releases = [
                    usage for usage in releases if usage in modifier_usages
                ]
                modifier_presses = [
                    usage for usage in presses if usage in modifier_usages
                ]
                ordinary_presses = [
                    usage for usage in presses if usage not in modifier_usages
                ]

                for usage in ordinary_releases:
                    link.key_event(usage, False)
                if ordinary_releases and modifier_releases:
                    time.sleep(0.005)
                for usage in modifier_releases:
                    link.key_event(usage, False)
                for usage in modifier_presses:
                    link.key_event(usage, True)
                # The original QL keyboard requires the modifier contact to
                # settle before the main key. This also prevents short host
                # taps from turning shifted punctuation into number keys.
                if modifier_presses and ordinary_presses:
                    time.sleep(0.010)
                for usage in ordinary_presses:
                    link.key_event(usage, True)
                remote_pressed = desired

            # Drain console events so they are not replayed by PowerShell
            # after F6. Key state itself comes from GetAsyncKeyState above.
            while msvcrt.kbhit():
                msvcrt.getwch()
            time.sleep(0.002)
    finally:
        for usage in tuple(remote_pressed):
            link.key_event(usage, False)


def interactive_keyboard_pynput(link: NanoQLLink,
                                stop_file: Path | None = None) -> None:
    try:
        from pynput import keyboard
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pynput"])
        from pynput import keyboard

    if sys.platform == "darwin":
        try:
            from Quartz import (
                AXIsProcessTrusted,
                CGEventSourceKeyState,
                kCGEventSourceStateCombinedSessionState,
            )
            trusted = bool(AXIsProcessTrusted())
        except ImportError:
            trusted = True
            AXIsProcessTrusted = lambda: True
            CGEventSourceKeyState = None
            kCGEventSourceStateCombinedSessionState = None
        if not trusted:
            raise RuntimeError(
                "macOS has not authorized keyboard monitoring for this process. "
                "Allow Terminal and, if listed separately, the Python executable "
                f"{sys.executable!r} in System Settings > Privacy & Security > "
                "Input Monitoring and Accessibility, then restart Terminal."
            )

    def key_named(name: str):
        return getattr(keyboard.Key, name, None)

    special_usages = {}
    for name, usage in (
        ("backspace", 0x2A), ("tab", 0x2B), ("enter", 0x28),
        ("esc", 0x29), ("space", 0x2C), ("caps_lock", 0x39),
        ("home", 0x4A), ("page_up", 0x4B), ("delete", 0x4C),
        ("end", 0x4D), ("page_down", 0x4E), ("right", 0x4F),
        ("left", 0x50), ("down", 0x51), ("up", 0x52),
    ):
        key = key_named(name)
        if key is not None:
            special_usages[key] = usage
    for index in range(1, 13):
        key = key_named(f"f{index}")
        if key is not None and index != 6:
            special_usages[key] = 0x39 + index

    modifier_usages = {}
    for name, usage in (
        ("ctrl", 0x68), ("ctrl_l", 0x68), ("ctrl_r", 0x6C),
        ("shift", 0x69), ("shift_l", 0x69), ("shift_r", 0x6D),
        ("alt", 0x6A), ("alt_l", 0x6A), ("alt_r", 0x6E),
        ("alt_gr", 0x6E),
    ):
        key = key_named(name)
        if key is not None:
            modifier_usages[key] = usage

    input_events: queue.Queue[tuple[bool, object]] = queue.Queue()
    active_keys: dict[object, tuple[set[int], bool, float]] = {}
    active_modifiers: dict[object, tuple[int, float]] = {}
    pending_releases: dict[object, float] = {}
    remote_pressed: set[int] = set()
    stopping = False
    f6_key = key_named("f6")
    minimum_hold_time = 0.085

    terminal_fd: int | None = None
    terminal_attributes = None
    terminal_module = None
    terminal_echo_changed = False
    if sys.stdin.isatty():
        try:
            import termios

            terminal_fd = sys.stdin.fileno()
            terminal_module = termios
            terminal_attributes = termios.tcgetattr(terminal_fd)
            termios.tcflush(terminal_fd, termios.TCIFLUSH)
            if sys.platform != "darwin":
                quiet_attributes = list(terminal_attributes)
                quiet_attributes[3] &= ~(termios.ECHO | termios.ECHONL)
                termios.tcsetattr(terminal_fd, termios.TCSANOW, quiet_attributes)
                terminal_echo_changed = True
        except (ImportError, OSError):
            terminal_fd = None
            terminal_attributes = None
            terminal_module = None

    def on_press(key) -> bool | None:
        nonlocal stopping
        if key == f6_key:
            stopping = True
            return False
        input_events.put((True, key))
        return None

    def on_release(key) -> None:
        input_events.put((False, key))

    def reconcile() -> None:
        nonlocal remote_pressed
        desired: set[int] = set()
        translated_active = False
        for usages, translated, _pressed_at in active_keys.values():
            desired.update(usages)
            translated_active |= translated
        if not translated_active:
            desired.update(usage for usage, _pressed_at in active_modifiers.values())

        ql_modifiers = {0x68, 0x69, 0x6A, 0x6C, 0x6D, 0x6E}
        releases = remote_pressed - desired
        presses = desired - remote_pressed
        ordinary_releases = sorted(releases - ql_modifiers)
        modifier_releases = sorted(releases & ql_modifiers)
        modifier_presses = sorted(presses & ql_modifiers)
        ordinary_presses = sorted(presses - ql_modifiers)
        for usage in ordinary_releases:
            link.key_event(usage, False)
        if ordinary_releases and modifier_releases:
            time.sleep(0.005)
        for usage in modifier_releases:
            link.key_event(usage, False)
        # On AZERTY, typing a number can mean releasing the physical host
        # Shift while pressing an unshifted QL digit. Let the IPC matrix see
        # that modifier transition before the ordinary key arrives.
        if modifier_releases and ordinary_presses:
            time.sleep(0.012)
        for usage in modifier_presses:
            link.key_event(usage, True)
        if modifier_presses and ordinary_presses:
            time.sleep(0.012)
        for usage in ordinary_presses:
            link.key_event(usage, True)
        remote_pressed = desired

    def finish_due_releases() -> bool:
        now = time.monotonic()
        due = [key for key, deadline in pending_releases.items()
               if deadline <= now]
        for key in due:
            pending_releases.pop(key, None)
            active_keys.pop(key, None)
        if due:
            reconcile()
            return True
        return False

    def mac_virtual_key(key) -> int | None:
        value = getattr(key, "value", key)
        virtual_key = getattr(value, "vk", None)
        return virtual_key if isinstance(virtual_key, int) else None

    def release_lost_macos_keys() -> bool:
        if sys.platform != "darwin" or CGEventSourceKeyState is None:
            return False
        now = time.monotonic()
        changed = False
        for key, (_usages, _translated, pressed_at) in tuple(active_keys.items()):
            virtual_key = mac_virtual_key(key)
            if virtual_key is None or now - pressed_at < 0.15:
                continue
            try:
                physically_pressed = bool(CGEventSourceKeyState(
                    kCGEventSourceStateCombinedSessionState, virtual_key
                ))
            except Exception:
                return False
            if not physically_pressed:
                pending_releases.pop(key, None)
                active_keys.pop(key, None)
                changed = True
        for key, (_usage, pressed_at) in tuple(active_modifiers.items()):
            virtual_key = mac_virtual_key(key)
            if virtual_key is None or now - pressed_at < 0.15:
                continue
            try:
                physically_pressed = bool(CGEventSourceKeyState(
                    kCGEventSourceStateCombinedSessionState, virtual_key
                ))
            except Exception:
                return False
            if not physically_pressed:
                active_modifiers.pop(key, None)
                changed = True
        if changed:
            reconcile()
        return changed

    print(f"NanoQL keyboard active (QL {link.ql_layout.upper()} profile). "
          "Keys are held in real time; press F6 to return to the terminal.")
    listener = None
    try:
        listener = keyboard.Listener(
            on_press=on_press,
            on_release=on_release,
            # On macOS this uses the authorized Quartz event tap. It prevents
            # Terminal from receiving escape sequences without changing tty
            # echo, which would enable Secure Keyboard Entry and block pynput.
            suppress=sys.platform == "darwin",
        )
        listener.start()
        while listener.is_alive() or not input_events.empty() or pending_releases:
            if stop_requested(stop_file):
                break
            finish_due_releases()
            release_lost_macos_keys()
            try:
                pressed, key = input_events.get(timeout=0.005)
            except queue.Empty:
                if stopping and not pending_releases:
                    break
                continue

            modifier = modifier_usages.get(key)
            if modifier is not None:
                if pressed:
                    active_modifiers[key] = (modifier, time.monotonic())
                else:
                    active_modifiers.pop(key, None)
            elif pressed:
                pending_releases.pop(key, None)
                if key in active_keys:
                    continue
                usages: set[int] = set()
                translated = False
                character = getattr(key, "char", None)
                if character:
                    try:
                        usage, target_modifiers = link.character_key(character)
                        usages = {usage, *target_modifiers}
                        translated = True
                    except ValueError:
                        pass
                if not usages and key in special_usages:
                    usages = {special_usages[key]}
                if usages:
                    active_keys[key] = (usages, translated, time.monotonic())
            else:
                binding = active_keys.get(key)
                if binding is not None:
                    deadline = binding[2] + minimum_hold_time
                    if deadline > time.monotonic():
                        pending_releases[key] = deadline
                    else:
                        active_keys.pop(key, None)
            reconcile()
        listener.stop()
        listener.join(timeout=1.0)
    except Exception as error:
        if sys.platform == "darwin" and not bool(AXIsProcessTrusted()):
            raise RuntimeError(
                "macOS could not capture the keyboard. Allow Terminal or Python "
                "in System Settings > Privacy & Security > Input Monitoring and "
                "Accessibility, then restart the command."
            ) from error
        raise
    finally:
        if listener is not None and listener.is_alive():
            listener.stop()
            listener.join(timeout=1.0)
        if terminal_fd is not None and terminal_attributes is not None:
            try:
                terminal_module.tcflush(terminal_fd, terminal_module.TCIFLUSH)
                if terminal_echo_changed:
                    terminal_module.tcsetattr(
                        terminal_fd, terminal_module.TCSANOW, terminal_attributes
                    )
            except (OSError, terminal_module.error):
                pass
        for usage in tuple(remote_pressed):
            try:
                link.key_event(usage, False)
            except (OSError, RuntimeError, TimeoutError):
                break


def interactive_keyboard(link: NanoQLLink,
                         stop_file: Path | None = None) -> None:
    if os.name == "nt":
        interactive_keyboard_windows(link, stop_file)
    else:
        interactive_keyboard_pynput(link, stop_file)


DEMO_CODE = bytes.fromhex(
    "13fc000000018063"  # MOVE.B #$00,$00018063 (mode 4, screen $20000)
    "207c00024000"  # MOVEA.L #$00024000,A0 (QL line 128)
    "303c0800"      # MOVE.W  #$0800,D0 (32 complete QL lines)
    "30fcff00"      # loop: MOVE.W #$ff00,(A0)+ (solid green in mode 4)
    "5340"          # SUBQ.W #1,D0
    "66f8"          # BNE.S loop
    "60fe"          # forever: BRA.S forever
)


def load_binary(link: NanoQLLink, data: bytes, address: int, pc: int, stack: int) -> None:
    if pc & 1 or stack & 1:
        raise ValueError("The 68000 PC and stack pointer must be even.")
    print(f"Stopping the 68000 and loading {len(data)} bytes at 0x{address:06x}...")
    link.hold()
    link.write(address, data)
    readback = link.read(address, len(data))
    if readback != data:
        mismatch = next(index for index, pair in enumerate(zip(data, readback))
                        if pair[0] != pair[1])
        raise RuntimeError(
            f"RAM verification failed at 0x{address + mismatch:06x}: "
            f"wrote 0x{data[mismatch]:02x}, read 0x{readback[mismatch]:02x}."
        )
    print("RAM verification completed successfully.")
    print(f"Executing with SSP=0x{stack:08x}, PC=0x{pc:08x}.")
    status = link.execute(stack, pc)
    print(f"Execution accepted by the FPGA (status=0x{status:02x}).")
    print(
        "68000 trace: injected code reached = " +
        ("yes" if status & 0x80 else "no") +
        ", video write = " + ("yes" if status & 0x40 else "no") + "."
    )


def run_demo(link: NanoQLLink) -> None:
    video_start = 0x024000
    sample_addresses = (video_start, video_start + 0x0800, video_start + 0x0FF8)

    load_binary(link, DEMO_CODE, 0x030000, 0x030000, 0x03FFF0)
    time.sleep(1.0)
    link.hold()

    samples = [(address, link.read(address, 8)) for address in sample_addresses]
    print("VRAM verification after execution:")
    all_valid = True
    for address, data in samples:
        valid = data == bytes.fromhex("ff00" * 4)
        all_valid &= valid
        print(f"  0x{address:06x}: {data.hex(' ')} " + ("OK" if valid else "ERROR"))

    if not all_valid:
        raise RuntimeError(
            "The 68000 did not fill VRAM correctly; report these values for diagnostics."
        )
    print("VRAM is correct. A central green band should remain visible on screen.")


def run_link_stress(link: NanoQLLink, duration: float) -> None:
    if duration <= 0:
        raise ValueError("Stress-test duration must be positive.")
    deadline = time.monotonic() + duration
    transactions = 0
    print(f"Running NanoQL Link USB stress test for {duration:g} seconds...")
    while time.monotonic() < deadline:
        link.status()
        transactions += 1
        if transactions % 100 == 0:
            print(f"\rUSB transactions: {transactions}", end="", flush=True)
    print()
    print(f"USB stress test completed: {transactions} transactions, "
          f"{link.reconnect_count} reconnect(s).")


def basic_source_lines(path: Path, skip_comments: bool = False) -> list[str]:
    text = path.read_text(encoding="utf-8-sig")
    lines = []
    for source_line in text.splitlines():
        line = source_line.strip()
        if not line:
            continue
        if not re.match(r"^[0-9]+(?:\s|$)", line):
            raise ValueError(
                f"{path}: every non-empty SuperBASIC line must start with a line number: {line!r}"
            )
        if skip_comments and re.match(r"^[0-9]+\s+rem(?:ark)?(?:\s|$)", line,
                                      flags=re.IGNORECASE):
            continue
        lines.append(line)
    if not lines:
        raise ValueError(f"{path}: no numbered SuperBASIC lines were found.")
    return lines


def load_basic_program(link: NanoQLLink, path: Path, run: bool,
                       skip_comments: bool = False,
                       line_delay: float = 0.75) -> None:
    lines = basic_source_lines(path, skip_comments=skip_comments)
    transmitted_lines = [line.lower() for line in lines]
    for line in transmitted_lines:
        for character in line:
            link.character_key(character)

    print(f"Loading {len(lines)} SuperBASIC lines from {path} into QDOS RAM...")
    print("Keep the QL at the SuperBASIC prompt until the transfer completes.")
    cpu_speed, cpu_rate = link.measure_cpu_rate()
    cpu_labels = {0: "QL", 1: "16 MHz", 2: "24 MHz"}
    cpu_label = cpu_labels.get(cpu_speed, f"mode {cpu_speed}")
    print(f"FPGA CPU mode: {cpu_label}; measured phase rate: {cpu_rate / 1_000_000:.2f} MHz.")

    # Lowercase keeps the transfer independent of host Shift/AZERTY handling.
    # SuperBASIC tokenizes keywords without regard to case.
    # The physical 8049 keyboard scanner consumes events much more slowly
    # than the USB link accepts them. Keep each key down across several scans
    # and leave a real key-up interval so no character or Enter is swallowed.
    def submit_line(value: str, confirm_enter: bool = False) -> None:
        link.type_text(
            value, hold_time=0.08, release_time=0.05,
            wait_consumed=True,
            modifier_release_time=0.10,
        )
        link.type_character(
            "\r", hold_time=0.15, release_time=0.15,
            wait_consumed=True,
        )
        if confirm_enter:
            # A second Enter at an empty prompt is harmless. It ensures a
            # costly SuperBASIC tokenization cannot merge the following line.
            time.sleep(0.25)
            link.type_character(
                "\r", hold_time=0.15, release_time=0.15,
                wait_consumed=True,
            )

    submit_line("new")
    time.sleep(1.0)
    for index, line in enumerate(transmitted_lines, start=1):
        submit_line(line, confirm_enter=True)
        # QDOS edits and tokenizes the complete line after Enter. Sending the
        # next line immediately can overrun that work, especially at QL speed.
        time.sleep(line_delay)
        print(f"\rSuperBASIC transfer: {index * 100 // len(lines):3d}%", end="", flush=True)
    print()

    if run:
        print("Starting the SuperBASIC program...")
        submit_line("run")
    else:
        print("Program loaded. Type RUN on the QL when ready.")


def find_native_programmer(explicit: Path | None) -> tuple[str, Path]:
    if explicit is not None:
        tool = explicit.expanduser().resolve()
        if not tool.is_file():
            raise FileNotFoundError(tool)
        backend = "openfpgaloader" if "openfpgaloader" in tool.name.lower() else "gowin"
        return backend, tool

    openfpga = shutil.which("openFPGALoader") or shutil.which("openfpgaloader")
    openfpga_candidates = (
        Path("C:/msys64/ucrt64/bin/openFPGALoader.exe"),
        Path("C:/Program Files/openFPGALoader/bin/openFPGALoader.exe"),
        Path("C:/Program Files/openFPGALoader/openFPGALoader.exe"),
        Path("C:/msys64/mingw64/bin/openFPGALoader.exe"),
        Path("C:/ProgramData/chocolatey/bin/openFPGALoader.exe"),
        Path.home() / "scoop/apps/openfpgaloader/current/bin/openFPGALoader.exe",
        Path.home() / "scoop/apps/openfpgaloader/current/openFPGALoader.exe",
    )
    if openfpga:
        return "openfpgaloader", Path(openfpga)
    for candidate in openfpga_candidates:
        if candidate.is_file():
            return "openfpgaloader", candidate

    gowin = shutil.which("programmer_cli") or shutil.which("programmer_cli.exe")
    if gowin:
        return "gowin", Path(gowin)

    candidates: list[Path] = []
    for root in (Path("C:/Gowin"), Path("C:/Program Files/Gowin"),
                 Path("C:/Program Files (x86)/Gowin")):
        if root.is_dir():
            candidates.extend(root.glob("Gowin_*/Programmer/bin/programmer_cli.exe"))
    if candidates:
        return "gowin", sorted(candidates, reverse=True)[0]

    raise RuntimeError(
        "No native FPGA programmer was found. Install Gowin Programmer or "
        "openFPGALoader, or specify --tool."
    )


def native_openfpgaloader_version(executable: Path) -> tuple[int, int, int]:
    try:
        completed = subprocess.run(
            [str(executable), "-V"], check=False, capture_output=True,
            text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return (0, 0, 0)
    match = re.search(
        r"openFPGALoader\s+v(\d+)\.(\d+)\.(\d+)",
        completed.stdout + completed.stderr,
        flags=re.IGNORECASE,
    )
    return tuple(map(int, match.groups())) if match else (0, 0, 0)


def detect_gowin_location(executable: Path, channel: int) -> int | None:
    for scan_mode in ("L", "F"):
        try:
            completed = subprocess.run(
                [str(executable), "--scan-cables", scan_mode],
                check=False, capture_output=True, text=True, timeout=10,
            )
        except subprocess.TimeoutExpired:
            continue
        output = completed.stdout + "\n" + completed.stderr
        match = re.search(
            rf"USB Debugger A[^\r\n]*?[/\s]{channel}[/\s]+(\d+)[/\s]",
            output,
            flags=re.IGNORECASE,
        )
        if match:
            return int(match.group(1))
    return None


def program_fpga_flash_native(bitstream: Path, tool: Path | None,
                              frequency: str, channel: int,
                              location: int | None) -> None:
    bitstream = bitstream.expanduser().resolve()
    if not bitstream.is_file():
        raise FileNotFoundError(bitstream)
    if bitstream.suffix.lower() != ".fs":
        raise ValueError("Native persistent programming requires Gowin's .fs file.")

    backend, executable = find_native_programmer(tool)
    if backend == "gowin":
        raise RuntimeError(
            "Gowin's command-line tools cannot program USB Debugger A reliably. "
            "Select openFPGALoader v1.1.1 or newer, or use the Gowin Programmer "
            "graphical application manually."
        )

    version = native_openfpgaloader_version(executable)
    if version < (1, 1, 1):
        raise RuntimeError(
            "Tang Nano 20K BL616 programming requires openFPGALoader v1.1.1 "
            f"or newer; detected {'.'.join(map(str, version))}."
        )
    command = [
        str(executable), "-b", "tangnano20k", "-f",
        "--external-flash", str(bitstream),
    ]

    print(f"Native programmer: {executable}")
    print(f"Programming {bitstream.name}...")
    completed = subprocess.run(command, check=False)
    if completed.returncode:
        raise RuntimeError(
            "Native FPGA programming failed. Ensure that the BL616 is running "
            "the official FPGA Partner firmware and that no other programmer is open."
        )
    print("Persistent FPGA programming completed successfully.")


def main() -> int:
    parser = argparse.ArgumentParser(description="NanoQL Link - direct 68000 code loading")
    parser.add_argument("--port", help="serial port, for example COM6 or /dev/ttyACM0")
    parser.add_argument(
        "--keyboard-layout", choices=("host", "us"), default="host",
        help="PC layout used as a fallback for otherwise unknown characters",
    )
    parser.add_argument(
        "--ql-layout", choices=("auto", "uk", "fr"), default="auto",
        help=("QL ROM character table override; auto reads 'QL ROM keyboard' "
              "from the FPGA overlay (recommended)"),
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status", help="read the link status")
    subparsers.add_parser("cpu-status", help="measure the active FPGA CPU rate")
    subparsers.add_parser(
        "qdos-memory",
        help="snapshot the live QDOS memory map without resetting the QL",
    )
    subparsers.add_parser("qlsd-status", help="read the last QL-SD sector diagnostic")
    subparsers.add_parser("mdv-status", help="read the live Microdrive diagnostic")
    subparsers.add_parser("qdos", help="leave the injected program and restart QDOS")
    subparsers.add_parser("demo", help="inject a bare-metal 68000 test pattern")
    subparsers.add_parser(
        "benchmark", help="load and run the included Sinclair QL Basic benchmark"
    )
    keyboard_parser = subparsers.add_parser(
        "keyboard", help="use the computer keyboard in real time"
    )
    keyboard_parser.add_argument(
        "--stop-file", type=Path,
        help=argparse.SUPPRESS,
    )

    subparsers.add_parser(
        "sd-info", help="check USB access to the NanoQL/Drive1 microSD folder"
    )
    sd_list_parser = subparsers.add_parser(
        "sd-list", help="list files in the NanoQL/Drive1 microSD folder"
    )
    sd_list_parser.add_argument("path", nargs="?", default="")

    sd_put_parser = subparsers.add_parser(
        "sd-put", help="upload a PC file to NanoQL/Drive1"
    )
    sd_put_parser.add_argument("source", type=Path)
    sd_put_parser.add_argument(
        "destination", nargs="?",
        help="relative Drive1 path (default: source filename)",
    )

    sd_get_parser = subparsers.add_parser(
        "sd-get", help="download a file from NanoQL/Drive1"
    )
    sd_get_parser.add_argument("source")
    sd_get_parser.add_argument(
        "destination", nargs="?", type=Path,
        help="local path (default: remote filename)",
    )

    sd_delete_parser = subparsers.add_parser(
        "sd-delete", help="delete a file or empty directory from NanoQL/Drive1"
    )
    sd_delete_parser.add_argument("path")
    sd_delete_parser.add_argument(
        "--yes", action="store_true", help="confirm permanent deletion"
    )

    sd_mkdir_parser = subparsers.add_parser(
        "sd-mkdir", help="create a directory in NanoQL/Drive1"
    )
    sd_mkdir_parser.add_argument("path")

    sd_build_mdv_parser = subparsers.add_parser(
        "sd-build-mdv",
        help="build MDV1.mdv from the loose files in NanoQL/Drive1",
    )
    sd_build_mdv_parser.add_argument(
        "--destination", default="MDV1.mdv",
        help="relative Drive1 image path (default: MDV1.mdv)",
    )
    sd_build_mdv_parser.add_argument(
        "--name", default="NANOQL", help="QL Microdrive medium name"
    )

    mdv_sync_parser = subparsers.add_parser(
        "mdv-sync",
        help="synchronize a PC folder with MDV1 and mount it",
    )
    mdv_sync_parser.add_argument("source", type=Path, help="PC folder exposed as MDV1")
    mdv_sync_parser.add_argument(
        "--name", default="NANOQL", help="QL Microdrive medium name"
    )

    mdv_extract_parser = subparsers.add_parser(
        "mdv-extract",
        help="extract ordinary files from a local or Drive1 QLAY image",
    )
    mdv_extract_parser.add_argument(
        "source", help="local image path, or relative Drive1 path with --remote"
    )
    mdv_extract_parser.add_argument(
        "destination", nargs="?", type=Path,
        help="output folder (default: IMAGE_files)",
    )
    mdv_extract_parser.add_argument(
        "--remote", action="store_true",
        help="download SOURCE from NanoQL/Drive1 before extracting it",
    )

    stress_parser = subparsers.add_parser(
        "link-stress", help="run a non-destructive NanoQL Link USB stress test"
    )
    stress_parser.add_argument(
        "--seconds", type=float, default=30.0,
        help="test duration in seconds (default: 30)",
    )

    type_parser = subparsers.add_parser("type", help="send text as keyboard input")
    type_parser.add_argument("text")
    type_parser.add_argument("--enter", action="store_true", help="press Enter after the text")

    load_parser = subparsers.add_parser("load", help="load and execute a 68000 binary")
    load_parser.add_argument("binary", type=Path)
    load_parser.add_argument("--address", type=parse_number, default=0x030000)
    load_parser.add_argument("--pc", type=parse_number)
    load_parser.add_argument("--stack", type=parse_number, default=0x03FFF0)

    basic_parser = subparsers.add_parser(
        "basic", help="enter a numbered SuperBASIC source file into QDOS RAM"
    )
    basic_parser.add_argument("source", type=Path)
    basic_parser.add_argument(
        "--no-run", action="store_true", help="load the program without typing RUN"
    )

    fpga_parser = subparsers.add_parser(
        "fpga", help="load a Gowin .bin bitstream into FPGA SRAM"
    )
    fpga_parser.add_argument("bitstream", type=Path)

    native_flash_parser = subparsers.add_parser(
        "fpga-flash-native",
        help="program SPI Flash with Gowin Programmer or openFPGALoader",
    )
    native_flash_parser.add_argument("bitstream", type=Path)
    native_flash_parser.add_argument(
        "--tool", type=Path,
        help="path to programmer_cli.exe or openFPGALoader",
    )
    native_flash_parser.add_argument(
        "--frequency", default="2.5MHz",
        help="Gowin JTAG frequency (default: 2.5MHz)",
    )
    native_flash_parser.add_argument(
        "--channel", type=int, choices=(0, 1), default=1,
        help="Gowin USB Debugger A channel (default: 1)",
    )
    native_flash_parser.add_argument(
        "--location", type=int,
        help="Gowin cable location; detected automatically when possible",
    )
    native_flash_parser.add_argument(
        "--yes", action="store_true",
        help="confirm replacement of the previous persistent bitstream",
    )
    args = parser.parse_args()
    if args.command == "fpga-flash-native":
        if not args.yes:
            raise RuntimeError(
                "Add --yes to confirm replacement of the persistent bitstream."
            )
        program_fpga_flash_native(
            args.bitstream, args.tool, args.frequency,
            args.channel, args.location
        )
        return 0

    if args.command == "mdv-extract" and not args.remote:
        source = Path(args.source).expanduser().resolve()
        destination = args.destination or source.with_name(source.stem + "_files")
        written = extract_qlay_image(source.read_bytes(), destination)
        print(f"Extracted {len(written)} file(s) to {destination.resolve()}.")
        for path in written:
            print(f"  {path.name}: {path.stat().st_size} bytes")
        return 0

    port = find_port(args.port)
    ql_layout = "uk" if args.ql_layout == "auto" else args.ql_layout
    link = NanoQLLink(port, keyboard_layout=args.keyboard_layout, ql_layout=ql_layout)
    try:
        if args.ql_layout == "auto":
            try:
                link.ql_layout = link.configured_ql_layout()
            except RuntimeError:
                # Compatibility with older bitstreams which inferred the QL
                # profile from the active Windows keyboard layout.
                link.ql_layout = default_ql_layout()
        if args.command == "status":
            print(f"NanoQL Link status: 0x{link.status():02x}")
        elif args.command == "cpu-status":
            cpu_speed, cpu_rate = link.measure_cpu_rate()
            cpu_labels = {0: "QL", 1: "16 MHz", 2: "24 MHz"}
            cpu_label = cpu_labels.get(cpu_speed, f"mode {cpu_speed}")
            print(f"FPGA CPU mode: {cpu_label}")
            print(f"Measured phase rate: {cpu_rate / 1_000_000:.3f} MHz")
            print(f"QL ROM keyboard: {'French' if link.ql_layout == 'fr' else 'English'}")
        elif args.command == "qdos-memory":
            memory = link.qdos_memory_map()
            print("QDOS memory map (live, non-resetting snapshot):")
            print(f"  SV_IDENT = 0x{memory['SV_IDENT']:08x} (QDOS)")
            descriptions = {name: description for name, _offset, description
                            in QDOS_SYSVARS}
            for name, _offset, _description in QDOS_SYSVARS:
                print(
                    f"  {name:8s} = 0x{memory[name]:06x}  "
                    f"{descriptions[name]}"
                )

            ordered = ("SV_CHEAP", "SV_FREE", "SV_BASIC",
                       "SV_TRNSP", "SV_RESPR", "SV_RAMT")
            monotonic = all(
                memory[left] <= memory[right]
                for left, right in zip(ordered, ordered[1:])
            )
            print("Derived regions:")
            print(f"  Physical QL RAM:       {kib(memory['SV_RAMT'] - 0x020000)}")
            print(
                f"  Common heap span:      "
                f"{kib(max(0, memory['SV_FREE'] - memory['SV_CHEAP']))}"
            )
            print(
                f"  Free/slave-block span: "
                f"{kib(max(0, memory['SV_BASIC'] - memory['SV_FREE']))}"
            )
            print(
                f"  SuperBASIC span:       "
                f"{kib(max(0, memory['SV_TRNSP'] - memory['SV_BASIC']))}"
            )
            print(
                f"  Transient span:        "
                f"{kib(max(0, memory['SV_RESPR'] - memory['SV_TRNSP']))}"
            )
            print(
                f"  Resident space used:   "
                f"{kib(max(0, memory['SV_RAMT'] - memory['SV_RESPR']))}"
            )
            print(
                "  Boundary order:         "
                + ("valid" if monotonic else "UNUSUAL - report these values")
            )
        elif args.command == "qlsd-status":
            flags, lba, header, byte_count, crc32, sample = link.qlsd_status()
            print(f"QL-SD flags: 0x{flags:02x}")
            print(f"Last requested LBA: {lba}")
            print(f"First bytes: {header.hex(' ')} ({header.decode('ascii', errors='replace')})")
            print(f"Bytes received: {byte_count}")
            print(f"Sector 0 CRC32: 0x{crc32:08x}")
            print(f"Bytes 4-11: {sample.hex(' ')}")
        elif args.command == "mdv-status":
            flags, position, rx_count, read_count, missed_count, \
                stream_last, read_last = link.mdv_diagnostic()
            print(f"Microdrive flags: 0x{flags:02x}")
            print(
                "Image valid/ready, selected, running, available, GAP, RX, SD read: "
                + " ".join(
                    "yes" if flags & (1 << bit) else "no"
                    for bit in (0, 1, 2, 3, 4, 5, 6, 7)
                )
            )
            print(f"Tape byte position: {position}; RX windows={rx_count}")
            print(f"68000 data reads: {read_count}")
            print(
                f"RX pulses not sampled: {missed_count}; "
                f"last stream/read byte: {stream_last:02x}/{read_last:02x}"
            )
            trace_count, trace = link.mdv_header_trace()
            print(
                f"Last header CPU reads: {trace_count}; "
                f"first bytes: {trace.hex(' ') if trace else '(none)'}"
            )
            data_count, data_trace = link.mdv_data_trace()
            print(
                f"Last data block CPU reads: {data_count}; "
                f"first bytes: {data_trace.hex(' ') if data_trace else '(none)'}"
            )
        elif args.command == "qdos":
            link.qdos()
            print("QDOS restart requested.")
        elif args.command == "demo":
            run_demo(link)
        elif args.command == "benchmark":
            benchmark = Path(__file__).resolve().parent.parent / "examples" / \
                        "basic-benchmark" / "bench_ql_bas"
            load_basic_program(link, benchmark, run=True, skip_comments=True)
        elif args.command == "basic":
            load_basic_program(link, args.source, run=not args.no_run)
        elif args.command == "keyboard":
            if args.stop_file:
                args.stop_file.unlink(missing_ok=True)
            interactive_keyboard(link, args.stop_file)
        elif args.command == "link-stress":
            run_link_stress(link, args.seconds)
        elif args.command == "sd-info":
            capabilities, max_path = link.filesystem_info()
            print("NanoQL Drive1 is ready.")
            print(f"Capabilities: 0x{capabilities:02x}; maximum path: {max_path}")
            print("microSD folder: /NanoQL/Drive1")
        elif args.command == "sd-list":
            entries = link.filesystem_list(args.path)
            location = "/NanoQL/Drive1"
            if args.path:
                location += "/" + args.path.replace("\\", "/").strip("/")
            print(location)
            for name, size, is_directory in entries:
                print(f"{'<DIR>' if is_directory else f'{size:10d}'}  {name}")
            if not entries:
                print("(empty)")
        elif args.command == "sd-put":
            destination = args.destination or args.source.name
            print(
                f"Uploading {args.source} to /NanoQL/Drive1/{destination}..."
            )
            link.filesystem_put(args.source, destination)
            print("Upload verified by size and CRC32.")
        elif args.command == "sd-get":
            destination = args.destination or Path(
                args.source.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]
            )
            print(
                f"Downloading /NanoQL/Drive1/{args.source} to {destination}..."
            )
            link.filesystem_get(args.source, destination)
            print("Download completed.")
        elif args.command == "sd-delete":
            if not args.yes:
                raise RuntimeError("Add --yes to confirm permanent deletion.")
            link.filesystem_delete(args.path)
            print(f"Deleted /NanoQL/Drive1/{args.path}.")
        elif args.command == "sd-mkdir":
            link.filesystem_mkdir(args.path)
            print(f"Created /NanoQL/Drive1/{args.path}.")
        elif args.command == "sd-build-mdv":
            destination = args.destination.replace("\\", "/").strip("/")
            remote_path_bytes(destination)
            with tempfile.TemporaryDirectory(prefix="nanoql-drive1-") as directory:
                source = Path(directory) / "Drive1"
                source.mkdir()
                print("Reading the loose Drive1 files from the microSD...")
                count = download_drive1_tree(
                    link, source, excluded_path=destination
                )
                files = collect_drive_files(source)
                image = build_qlay_image(files, args.name)
                output = Path(directory) / "MDV1.mdv"
                output.write_bytes(image)
                print(
                    f"Built a {len(image)}-byte QLAY image from {count} file(s)."
                )
                print(
                    f"Uploading the cartridge to /NanoQL/Drive1/{destination}..."
                )
                link.filesystem_put(output, destination)
            print("MDV1.mdv is ready; mount it from the Microdrive 1 menu entry.")
        elif args.command == "mdv-sync":
            source = args.source.expanduser().resolve()
            if not source.is_dir():
                raise NotADirectoryError(source)
            files = collect_drive_files(source, source / "MDV1.mdv")
            image = build_qlay_image(files, args.name)
            with tempfile.TemporaryDirectory(prefix="nanoql-mdv1-") as directory:
                output = Path(directory) / "MDV1.mdv"
                output.write_bytes(image)
                print(
                    f"Built a {len(image)}-byte MDV1 image from "
                    f"{len(files)} file(s) in {source}."
                )
                link.microdrive_sync_control(False)
                try:
                    print("Uploading and verifying MDV1.mdv...")
                    link.filesystem_put(output, "MDV1.mdv")
                except Exception:
                    try:
                        link.microdrive_sync_control(True)
                    except Exception:
                        pass
                    raise
                print("Upload verified; mounting MDV1...")
                link.microdrive_sync_control(True)
            print(
                "MDV1 synchronized and mounted. NanoQL Link remains active; "
                "use DIR mdv1_ from QDOS.",
                flush=True,
            )
        elif args.command == "mdv-extract":
            remote_path_bytes(args.source)
            source_name = args.source.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]
            destination = args.destination or Path(source_name).with_suffix("").with_name(
                Path(source_name).stem + "_files"
            )
            with tempfile.TemporaryDirectory(prefix="nanoql-mdv-extract-") as directory:
                local_image = Path(directory) / source_name
                print(f"Downloading /NanoQL/Drive1/{args.source}...")
                link.filesystem_get(args.source, local_image)
                written = extract_qlay_image(local_image.read_bytes(), destination)
            print(f"Extracted {len(written)} file(s) to {destination.resolve()}.")
            for path in written:
                print(f"  {path.name}: {path.stat().st_size} bytes")
        elif args.command == "type":
            link.type_text(args.text)
            if args.enter:
                link.tap_key(0x28, hold_time=0.15)
        elif args.command == "fpga":
            if args.bitstream.suffix.lower() != ".bin":
                raise ValueError(
                    "Use the .bin file generated by Gowin, not the .fs file."
                )
            data = args.bitstream.read_bytes()
            destination = "SRAM"
            print(f"Sending {len(data)} bytes to FPGA {destination} through the BL616...")
            link.program_fpga(data)
            print(
                f"FPGA programmed in {destination}. The BL616 automatically "
                "returns to Companion mode; the serial port disappearing is normal."
            )
        else:
            data = args.binary.read_bytes()
            pc = args.address if args.pc is None else args.pc
            load_binary(link, data, args.address, pc, args.stack)
    finally:
        link.close()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, TimeoutError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1)

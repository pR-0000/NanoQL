#!/usr/bin/env python3
"""Upload and start bare-metal 68000 binaries through NanoQL Link."""

from __future__ import annotations

import argparse
import ctypes
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib
from pathlib import Path

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
}

CMD_STATUS = 0x00
CMD_HOLD = 0x01
CMD_WRITE = 0x02
CMD_EXEC = 0x03
CMD_QDOS = 0x04
CMD_KEY = 0x05
CMD_READ = 0x06
CMD_READ_RESULT = 0x07
CMD_QLSD_DIAG = 0x08
CMD_CPU_DIAG = 0x09
CMD_FPGA_BEGIN = 0xF0
CMD_FPGA_DATA = 0xF1
CMD_FPGA_PROGRAM = 0xF2

MOD_LEFT_CTRL = 0x68
MOD_LEFT_SHIFT = 0x69
MOD_LEFT_ALT = 0x6A

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

# Windows has already converted AZERTY scan codes to logical characters by
# the time msvcrt returns them. Only characters absent from the UK QL matrix
# need a French-profile override; ordinary ASCII must not be remapped twice.
QL_FRENCH_KEYS = {
    "é": (0x2F, ()), "\\": (0x2F, (MOD_LEFT_SHIFT,)),
    "è": (0x30, ()), "ù": (0x31, ()), "`": (0x31, (MOD_LEFT_SHIFT,)),
    "à": (0x34, ()), "/": (0x34, (MOD_LEFT_SHIFT,)),
    "ç": (0x38, ()), "?": (0x38, (MOD_LEFT_SHIFT,)),
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
    layout = user32.GetKeyboardLayout(0)
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


def default_ql_layout() -> str:
    if os.name != "nt":
        return "uk"
    layout = ctypes.windll.user32.GetKeyboardLayout(0)
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
        self.serial.close()

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

    def read(self, address: int, length: int) -> bytes:
        if length < 0 or address < 0x020000 or address + length > 0x040000:
            raise ValueError("The block must remain within QL RAM 0x020000-0x03ffff.")
        result = bytearray()
        for offset in range(0, length, 8):
            block_length = min(8, length - offset)
            block_address = address + offset
            request = (bytes((CMD_READ,)) + block_address.to_bytes(3, "big") +
                       bytes((block_length,)))
            self.transact(request)
            self.wait_idle(expect_hold=True)
            response = self.transact(bytes((CMD_READ_RESULT,)) + bytes(8))
            if len(response) < block_length:
                raise RuntimeError("Incomplete RAM read response.")
            result.extend(response[-8:][:block_length])
        return bytes(result)

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
        event = usage if pressed else usage | 0x80
        self.transact(bytes((CMD_KEY, event)))

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


def interactive_keyboard(link: NanoQLLink) -> None:
    if os.name != "nt":
        raise RuntimeError("The interactive keyboard terminal is currently available on Windows only.")

    import msvcrt

    print(f"NanoQL keyboard active (QL {link.ql_layout.upper()} profile). "
          "Press F6 to return the keyboard to the terminal.")
    remote_shift = False
    get_async_key_state = ctypes.windll.user32.GetAsyncKeyState
    try:
        while True:
            host_shift = bool(get_async_key_state(0x10) & 0x8000)
            if remote_shift and not host_shift:
                link.key_event(MOD_LEFT_SHIFT, False)
                remote_shift = False

            if not msvcrt.kbhit():
                time.sleep(0.005)
                continue

            character = msvcrt.getwch()
            if character == "\x1d":
                break
            if character in ("\x00", "\xe0"):
                extended = msvcrt.getwch()
                if extended == "@":  # F6
                    break
                usage = WINDOWS_EXTENDED_KEYS.get(extended)
                if usage is not None:
                    link.tap_key(usage)
                continue
            if character == "\x03":
                raise KeyboardInterrupt
            if character in ("\r", "\n", "\b", "\t", "\x1b"):
                link.type_character(character)
                continue
            if "\x01" <= character <= "\x1a":
                letter = chr(ord("a") + ord(character) - 1)
                usage, _ = link.character_key(letter)
                link.key_event(MOD_LEFT_CTRL, True)
                link.tap_key(usage)
                link.key_event(MOD_LEFT_CTRL, False)
                continue

            try:
                usage, modifiers = link.character_key(character)
            except ValueError:
                usage, modifiers = 0, ()
            if host_shift and usage:
                if MOD_LEFT_SHIFT in modifiers:
                    if not remote_shift:
                        link.key_event(MOD_LEFT_SHIFT, True)
                        time.sleep(0.008)
                        remote_shift = True
                    for modifier in modifiers:
                        if modifier != MOD_LEFT_SHIFT:
                            link.key_event(modifier, True)
                    link.tap_key(usage)
                    for modifier in reversed(modifiers):
                        if modifier != MOD_LEFT_SHIFT:
                            link.key_event(modifier, False)
                    continue

            if remote_shift:
                link.key_event(MOD_LEFT_SHIFT, False)
                remote_shift = False
            link.type_character(character)
    finally:
        if remote_shift:
            link.key_event(MOD_LEFT_SHIFT, False)


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
    cpu_label = "QL" if cpu_speed == 0 else "16 MHz" if cpu_speed == 1 else f"mode {cpu_speed}"
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

    openfpga = shutil.which("openFPGALoader") or shutil.which("openfpgaloader")
    if openfpga:
        return "openfpgaloader", Path(openfpga)

    openfpga_candidates = (
        Path("C:/Program Files/openFPGALoader/bin/openFPGALoader.exe"),
        Path("C:/Program Files/openFPGALoader/openFPGALoader.exe"),
        Path("C:/msys64/mingw64/bin/openFPGALoader.exe"),
        Path("C:/ProgramData/chocolatey/bin/openFPGALoader.exe"),
        Path.home() / "scoop/apps/openfpgaloader/current/bin/openFPGALoader.exe",
        Path.home() / "scoop/apps/openfpgaloader/current/openFPGALoader.exe",
    )
    for candidate in openfpga_candidates:
        if candidate.is_file():
            return "openfpgaloader", candidate

    raise RuntimeError(
        "No native FPGA programmer was found. Install Gowin Programmer or "
        "openFPGALoader, or specify --tool."
    )


def detect_gowin_location(executable: Path, channel: int) -> int | None:
    for scan_mode in ("L", "F"):
        completed = subprocess.run(
            [str(executable), "--scan-cables", scan_mode],
            check=False, capture_output=True, text=True,
        )
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
    output_file: Path | None = None
    if backend == "gowin":
        if location is None:
            location = detect_gowin_location(executable, channel)
        if location is None:
            raise RuntimeError(
                "The USB Debugger A location could not be detected. Close Gowin "
                "Programmer and specify the value shown by its cable selector with "
                "--location, for example --location 82977."
            )
        output_file = Path(tempfile.gettempdir()) / "nanoql_gowin_programmer.txt"
        command = [
            str(executable),
            "--device", "GW2AR-18C",
            "--operation_index", "8",
            "--fsFile", str(bitstream),
            "--frequency", frequency,
            "--cable-index", "4",
            "--channel", str(channel),
            "--location", str(location),
            "--output", str(output_file),
        ]
    else:
        command = [
            str(executable), "-b", "tangnano20k", "-f",
            "--external-flash", str(bitstream),
        ]

    print(f"Native programmer: {executable}")
    if backend == "gowin":
        print(f"Target cable: USB Debugger A/{channel}/{location}/null")
    print(f"Programming {bitstream.name}...")
    completed = subprocess.run(command, check=False)
    if completed.returncode:
        if output_file is not None and output_file.is_file():
            print(output_file.read_text(encoding="utf-8", errors="replace"))
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
        help="QL logical layout; auto selects FR for a French Windows keyboard",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status", help="read the link status")
    subparsers.add_parser("cpu-status", help="measure the active FPGA CPU rate")
    subparsers.add_parser("qlsd-status", help="read the last QL-SD sector diagnostic")
    subparsers.add_parser("qdos", help="leave the injected program and restart QDOS")
    subparsers.add_parser("demo", help="inject a bare-metal 68000 test pattern")
    subparsers.add_parser(
        "benchmark", help="load and run the included Sinclair QL Basic benchmark"
    )
    subparsers.add_parser("keyboard", help="use the Windows terminal keyboard")

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

    port = find_port(args.port)
    ql_layout = default_ql_layout() if args.ql_layout == "auto" else args.ql_layout
    link = NanoQLLink(port, keyboard_layout=args.keyboard_layout, ql_layout=ql_layout)
    try:
        if args.command == "status":
            print(f"NanoQL Link status: 0x{link.status():02x}")
        elif args.command == "cpu-status":
            cpu_speed, cpu_rate = link.measure_cpu_rate()
            cpu_label = "QL" if cpu_speed == 0 else "16 MHz" if cpu_speed == 1 else f"mode {cpu_speed}"
            print(f"FPGA CPU mode: {cpu_label}")
            print(f"Measured phase rate: {cpu_rate / 1_000_000:.3f} MHz")
        elif args.command == "qlsd-status":
            flags, lba, header, byte_count, crc32, sample = link.qlsd_status()
            print(f"QL-SD flags: 0x{flags:02x}")
            print(f"Last requested LBA: {lba}")
            print(f"First bytes: {header.hex(' ')} ({header.decode('ascii', errors='replace')})")
            print(f"Bytes received: {byte_count}")
            print(f"Sector 0 CRC32: 0x{crc32:08x}")
            print(f"Bytes 4-11: {sample.hex(' ')}")
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
            interactive_keyboard(link)
        elif args.command == "link-stress":
            run_link_stress(link, args.seconds)
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

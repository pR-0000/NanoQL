#!/usr/bin/env python3
"""Upload and start bare-metal 68000 binaries through NanoQL Link."""

from __future__ import annotations

import argparse
import ctypes
import os
import struct
import subprocess
import sys
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
    1: "version de protocole non prise en charge",
    2: "CRC de la requete incorrect",
    3: "longueur de requete incorrecte",
    4: "taille du bitstream FPGA incorrecte",
    5: "impossible d'initialiser la programmation JTAG du FPGA",
    6: "transfert FPGA non initialise ou longueur incoherente",
    7: "echec du transfert direct vers le FPGA",
    8: "taille ou CRC du bitstream FPGA incorrect",
    9: "echec de la programmation JTAG du FPGA",
    13: "programmation persistante temporairement desactivee par securite",
}

CMD_STATUS = 0x00
CMD_HOLD = 0x01
CMD_WRITE = 0x02
CMD_EXEC = 0x03
CMD_QDOS = 0x04
CMD_KEY = 0x05
CMD_READ = 0x06
CMD_READ_RESULT = 0x07
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

# Logical characters produced by the original French MGF keyboard table.
# Values are physical USB usages followed by the QL modifiers to hold.
QL_FRENCH_KEYS = {
    letter: (ASCII_KEYS[letter][0], ()) for letter in "abcdefghijklmnopqrstuvwxyz"
}
QL_FRENCH_KEYS.update({
    "a": (0x14, ()), "q": (0x04, ()),
    "z": (0x1A, ()), "w": (0x1D, ()), "m": (0x33, ()),
    "1": (0x1E, ()), "2": (0x1F, ()), "3": (0x20, ()),
    "4": (0x21, ()), "5": (0x22, ()), "6": (0x23, ()),
    "7": (0x24, ()), "8": (0x25, ()), "9": (0x26, ()),
    "0": (0x27, ()),
    "!": (0x1E, (MOD_LEFT_SHIFT,)),
    '"': (0x1F, (MOD_LEFT_SHIFT,)),
    "#": (0x20, (MOD_LEFT_SHIFT,)),
    "$": (0x21, (MOD_LEFT_SHIFT,)),
    "%": (0x22, (MOD_LEFT_SHIFT,)),
    "'": (0x23, (MOD_LEFT_SHIFT,)),
    "&": (0x24, (MOD_LEFT_SHIFT,)),
    "*": (0x25, (MOD_LEFT_SHIFT,)),
    "(": (0x26, (MOD_LEFT_SHIFT,)),
    ")": (0x27, (MOD_LEFT_SHIFT,)),
    "-": (0x2D, ()), "_": (0x2D, (MOD_LEFT_SHIFT,)),
    "=": (0x2E, ()), "+": (0x2E, (MOD_LEFT_SHIFT,)),
    "é": (0x2F, ()), "\\": (0x2F, (MOD_LEFT_SHIFT,)),
    "è": (0x30, ()), "ù": (0x31, ()), "`": (0x31, (MOD_LEFT_SHIFT,)),
    "à": (0x34, ()), "/": (0x34, (MOD_LEFT_SHIFT,)),
    ",": (0x10, ()), "<": (0x10, (MOD_LEFT_SHIFT,)),
    ".": (0x36, ()), ">": (0x36, (MOD_LEFT_SHIFT,)),
    ";": (0x37, ()), ":": (0x37, (MOD_LEFT_SHIFT,)),
    "ç": (0x38, ()), "?": (0x38, (MOD_LEFT_SHIFT,)),
    " ": (0x2C, ()),
})
for _letter in "abcdefghijklmnopqrstuvwxyz":
    _usage, _modifiers = QL_FRENCH_KEYS[_letter]
    QL_FRENCH_KEYS[_letter.upper()] = (_usage, (MOD_LEFT_SHIFT,))

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
        raise RuntimeError("NanoQL Link n'a pas ete detecte. Precisez --port COMx ou /dev/ttyACMx.")
    raise RuntimeError("Plusieurs ports compatibles ont ete detectes. Precisez --port.")


class NanoQLLink:
    def __init__(self, port: str, timeout: float = 2.0,
                 keyboard_layout: str = "host", ql_layout: str = "uk"):
        self.serial = serial.Serial(port, 115200, timeout=timeout, write_timeout=timeout)
        self.sequence = 0
        self.keyboard_layout = keyboard_layout
        self.ql_layout = ql_layout

    def close(self) -> None:
        self.serial.close()

    def transact(self, spi_payload: bytes) -> bytes:
        if not 1 <= len(spi_payload) <= MAX_LINK_PAYLOAD:
            raise ValueError(
                f"Une transaction NanoQL Link doit contenir de 1 a "
                f"{MAX_LINK_PAYLOAD} octets."
            )
        self.sequence = (self.sequence + 1) & 0xFF
        body = bytes((PROTOCOL_VERSION, self.sequence, len(spi_payload))) + spi_payload
        frame = REQUEST_MAGIC + body + bytes((crc8(body),))
        self.serial.reset_input_buffer()
        self.serial.write(frame)
        self.serial.flush()

        header = self.serial.read(5)
        if len(header) != 5 or header[:2] != RESPONSE_MAGIC:
            raise RuntimeError("Reponse absente ou invalide du firmware BL616 NanoQL Link.")
        version, sequence, length = header[2], header[3], header[4]
        payload_and_crc = self.serial.read(length + 1)
        if len(payload_and_crc) != length + 1:
            raise RuntimeError("Reponse NanoQL Link incomplete.")
        response_body = bytes((version, sequence, length)) + payload_and_crc[:-1]
        if version != PROTOCOL_VERSION or sequence != self.sequence:
            raise RuntimeError("Version ou sequence NanoQL Link incorrecte.")
        if crc8(response_body) != payload_and_crc[-1]:
            raise RuntimeError("CRC NanoQL Link incorrect.")
        payload = payload_and_crc[:-1]
        if len(payload) == 2 and payload[0] == 0xFF:
            detail = FIRMWARE_ERRORS.get(payload[1], f"erreur {payload[1]}")
            raise RuntimeError(f"Le firmware BL616 a refuse la requete : {detail}.")
        return payload

    def status(self) -> int:
        rx = self.transact(bytes((CMD_STATUS, 0, 0, 0, 0, 0, 0)))
        signature_at = rx.find(b"NQL1")
        if signature_at < 0 or signature_at + 4 >= len(rx):
            raise RuntimeError("Le bitstream ne repond pas comme NanoQL Link v1.")
        return rx[signature_at + 4]

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
                raise RuntimeError(f"Le FPGA a refuse la commande (status=0x{status:02x}).")
            if ready and not busy and held == expect_hold:
                return status
            time.sleep(0.005)
        raise TimeoutError("Le FPGA n'est pas devenu disponible dans le delai imparti.")

    def write(self, address: int, data: bytes) -> None:
        if address < 0x020000 or address + len(data) > 0x040000:
            raise ValueError("Le bloc doit rester dans la RAM QL 0x020000-0x03ffff.")
        for offset in range(0, len(data), 8):
            block = data[offset : offset + 8]
            block_address = address + offset
            request = bytes((CMD_WRITE,)) + block_address.to_bytes(3, "big") + bytes((len(block),)) + block
            self.transact(request)
            self.wait_idle(expect_hold=True)

    def read(self, address: int, length: int) -> bytes:
        if length < 0 or address < 0x020000 or address + length > 0x040000:
            raise ValueError("Le bloc doit rester dans la RAM QL 0x020000-0x03ffff.")
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
                raise RuntimeError("Reponse de lecture RAM incomplete.")
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
            raise ValueError("Le bitstream FPGA doit faire entre 1 octet et 2 Mio.")
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
                print(f"\rTransfert FPGA : {percent:3d}%", end="", flush=True)
            print()

            self.serial.timeout = 120
            self.transact(bytes((CMD_FPGA_PROGRAM,)))
        finally:
            self.serial.timeout = previous_timeout

    def key_event(self, usage: int, pressed: bool) -> None:
        if not 0 <= usage <= 0x7F:
            raise ValueError("Code de touche HID hors plage.")
        event = usage if pressed else usage | 0x80
        self.transact(bytes((CMD_KEY, event)))

    def tap_key(self, usage: int, hold_time: float = 0.05) -> None:
        self.key_event(usage, True)
        time.sleep(hold_time)
        self.key_event(usage, False)
        time.sleep(0.03)

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
        raise ValueError(f"Caractere non pris en charge : {character!r}")

    def type_character(self, character: str) -> None:
        control_usage = {
            "\n": 0x28, "\r": 0x28, "\x1b": 0x29, "\t": 0x2B,
        }.get(character)
        if control_usage is not None:
            self.tap_key(control_usage, hold_time=0.15)
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
        self.tap_key(usage)
        if modifiers:
            time.sleep(0.005)
        for modifier in reversed(modifiers):
            self.key_event(modifier, False)

    def type_text(self, value: str) -> None:
        for character in value:
            self.type_character(character)


def interactive_keyboard(link: NanoQLLink) -> None:
    if os.name != "nt":
        raise RuntimeError("Le terminal clavier interactif est actuellement disponible sous Windows.")

    import msvcrt

    print(f"Clavier NanoQL actif (profil QL {link.ql_layout.upper()}). "
          "F6 rend le clavier a PowerShell.")
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
        raise ValueError("Le PC et le pointeur de pile 68000 doivent etre pairs.")
    print(f"Arret du 68000, chargement de {len(data)} octets a 0x{address:06x}...")
    link.hold()
    link.write(address, data)
    readback = link.read(address, len(data))
    if readback != data:
        mismatch = next(index for index, pair in enumerate(zip(data, readback))
                        if pair[0] != pair[1])
        raise RuntimeError(
            f"Verification RAM echouee a 0x{address + mismatch:06x}: "
            f"ecrit 0x{data[mismatch]:02x}, relu 0x{readback[mismatch]:02x}."
        )
    print("Verification RAM terminee sans erreur.")
    print(f"Execution avec SSP=0x{stack:08x}, PC=0x{pc:08x}.")
    status = link.execute(stack, pc)
    print(f"Execution acceptee par le FPGA (status=0x{status:02x}).")
    print(
        "Trace 68000 : code injecte atteint = " +
        ("oui" if status & 0x80 else "non") +
        ", ecriture video = " + ("oui" if status & 0x40 else "non") + "."
    )


def run_demo(link: NanoQLLink) -> None:
    video_start = 0x024000
    sample_addresses = (video_start, video_start + 0x0800, video_start + 0x0FF8)

    load_binary(link, DEMO_CODE, 0x030000, 0x030000, 0x03FFF0)
    time.sleep(1.0)
    link.hold()

    samples = [(address, link.read(address, 8)) for address in sample_addresses]
    print("Verification de la VRAM apres execution :")
    all_valid = True
    for address, data in samples:
        valid = data == bytes.fromhex("ff00" * 4)
        all_valid &= valid
        print(f"  0x{address:06x}: {data.hex(' ')} " + ("OK" if valid else "ERREUR"))

    if not all_valid:
        raise RuntimeError(
            "Le 68000 n'a pas rempli correctement la VRAM; transmettez ces valeurs pour diagnostic."
        )
    print("VRAM correcte. Une bande verte centrale doit rester visible a l'ecran.")


def main() -> int:
    parser = argparse.ArgumentParser(description="NanoQL Link - chargement direct de code 68000")
    parser.add_argument("--port", help="port serie, par exemple COM6 ou /dev/ttyACM0")
    parser.add_argument(
        "--keyboard-layout", choices=("host", "us"), default="host",
        help="disposition PC utilisee en dernier recours pour les caracteres inconnus",
    )
    parser.add_argument(
        "--ql-layout", choices=("auto", "uk", "fr"), default="auto",
        help="table logique du QL; auto choisit FR avec un clavier Windows francais",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status", help="lire l'etat du lien")
    subparsers.add_parser("qdos", help="quitter le programme injecte et redemarrer QDOS")
    subparsers.add_parser("demo", help="injecter une mire bare-metal 68000")
    subparsers.add_parser("keyboard", help="utiliser le clavier du terminal sous Windows")

    type_parser = subparsers.add_parser("type", help="envoyer du texte comme des frappes clavier")
    type_parser.add_argument("text")
    type_parser.add_argument("--enter", action="store_true", help="appuyer sur Entree apres le texte")

    load_parser = subparsers.add_parser("load", help="charger et executer un binaire 68000")
    load_parser.add_argument("binary", type=Path)
    load_parser.add_argument("--address", type=parse_number, default=0x030000)
    load_parser.add_argument("--pc", type=parse_number)
    load_parser.add_argument("--stack", type=parse_number, default=0x03FFF0)

    fpga_parser = subparsers.add_parser(
        "fpga", help="charger un bitstream Gowin .bin dans la SRAM du FPGA"
    )
    fpga_parser.add_argument("bitstream", type=Path)

    fpga_flash_parser = subparsers.add_parser(
        "fpga-flash",
        help="programmer durablement un bitstream Gowin .bin dans la Flash SPI",
    )
    fpga_flash_parser.add_argument("bitstream", type=Path)
    fpga_flash_parser.add_argument(
        "--yes", action="store_true",
        help="confirmer l'effacement de l'ancien bitstream permanent",
    )

    args = parser.parse_args()
    port = find_port(args.port)
    ql_layout = default_ql_layout() if args.ql_layout == "auto" else args.ql_layout
    link = NanoQLLink(port, keyboard_layout=args.keyboard_layout, ql_layout=ql_layout)
    try:
        if args.command == "status":
            print(f"NanoQL Link status: 0x{link.status():02x}")
        elif args.command == "qdos":
            link.qdos()
            print("Redemarrage QDOS demande.")
        elif args.command == "demo":
            run_demo(link)
        elif args.command == "keyboard":
            interactive_keyboard(link)
        elif args.command == "type":
            link.type_text(args.text)
            if args.enter:
                link.tap_key(0x28, hold_time=0.15)
        elif args.command == "fpga-flash":
            raise RuntimeError(
                "La programmation persistante est temporairement desactivee "
                "apres un echec de restauration materielle. Utilisez la "
                "commande fpga pour les essais en SRAM et Gowin Programmer "
                "pour la Flash de configuration."
            )
        elif args.command == "fpga":
            if args.bitstream.suffix.lower() != ".bin":
                raise ValueError(
                    "Utilisez le fichier .bin genere par Gowin, pas le .fs."
                )
            data = args.bitstream.read_bytes()
            destination = "la SRAM"
            print(f"Envoi de {len(data)} octets vers {destination} via le BL616...")
            link.program_fpga(data)
            print(
                f"FPGA programme dans {destination}. Le BL616 revient "
                "automatiquement en mode Companion ; la disparition du port "
                "COM est normale."
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
        print(f"Erreur : {error}", file=sys.stderr)
        raise SystemExit(1)

#!/usr/bin/env python3
"""Upload and start bare-metal 68000 binaries through NanoQL Link."""

from __future__ import annotations

import argparse
import struct
import subprocess
import sys
import time
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
MAX_SPI_PAYLOAD = 13

CMD_STATUS = 0x00
CMD_HOLD = 0x01
CMD_WRITE = 0x02
CMD_EXEC = 0x03
CMD_QDOS = 0x04


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
        if "nanoql" in description or "bouffalo" in description or "bl616" in description:
            candidates.append(port.device)
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        raise RuntimeError("NanoQL Link n'a pas ete detecte. Precisez --port COMx ou /dev/ttyACMx.")
    raise RuntimeError("Plusieurs ports compatibles ont ete detectes. Precisez --port.")


class NanoQLLink:
    def __init__(self, port: str, timeout: float = 2.0):
        self.serial = serial.Serial(port, 115200, timeout=timeout, write_timeout=timeout)
        self.sequence = 0

    def close(self) -> None:
        self.serial.close()

    def transact(self, spi_payload: bytes) -> bytes:
        if not 1 <= len(spi_payload) <= MAX_SPI_PAYLOAD:
            raise ValueError("Une transaction NanoQL Link doit contenir de 1 a 13 octets.")
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
        return payload_and_crc[:-1]

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

    def execute(self, stack_pointer: int, program_counter: int) -> None:
        payload = bytes((CMD_EXEC,)) + struct.pack(">II", stack_pointer, program_counter)
        self.transact(payload)

    def qdos(self) -> None:
        self.transact(bytes((CMD_QDOS,)))


DEMO_CODE = bytes.fromhex(
    "207c00020000"  # MOVEA.L #$00020000,A0
    "303c3fff"      # MOVE.W  #$3fff,D0
    "30fcaaaa"      # loop: MOVE.W #$aaaa,(A0)+
    "51c8fff8"      # DBRA D0,loop
    "60fe"          # forever: BRA.S forever
)


def load_binary(link: NanoQLLink, data: bytes, address: int, pc: int, stack: int) -> None:
    if pc & 1 or stack & 1:
        raise ValueError("Le PC et le pointeur de pile 68000 doivent etre pairs.")
    print(f"Arret du 68000, chargement de {len(data)} octets a 0x{address:06x}...")
    link.hold()
    link.write(address, data)
    print(f"Execution avec SSP=0x{stack:08x}, PC=0x{pc:08x}.")
    link.execute(stack, pc)


def main() -> int:
    parser = argparse.ArgumentParser(description="NanoQL Link - chargement direct de code 68000")
    parser.add_argument("--port", help="port serie, par exemple COM6 ou /dev/ttyACM0")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status", help="lire l'etat du lien")
    subparsers.add_parser("qdos", help="quitter le programme injecte et redemarrer QDOS")
    subparsers.add_parser("demo", help="injecter une mire bare-metal 68000")

    load_parser = subparsers.add_parser("load", help="charger et executer un binaire 68000")
    load_parser.add_argument("binary", type=Path)
    load_parser.add_argument("--address", type=parse_number, default=0x030000)
    load_parser.add_argument("--pc", type=parse_number)
    load_parser.add_argument("--stack", type=parse_number, default=0x03FFF0)

    args = parser.parse_args()
    port = find_port(args.port)
    link = NanoQLLink(port)
    try:
        if args.command == "status":
            print(f"NanoQL Link status: 0x{link.status():02x}")
        elif args.command == "qdos":
            link.qdos()
            print("Redemarrage QDOS demande.")
        elif args.command == "demo":
            load_binary(link, DEMO_CODE, 0x030000, 0x030000, 0x03FFF0)
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

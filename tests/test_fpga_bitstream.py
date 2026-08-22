from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


TOOLS = Path(__file__).resolve().parents[1] / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import nanoql_link


def sample_gowin_binary() -> bytes:
    data = bytearray(64)
    data[:24] = nanoql_link.GOWIN_PREAMBLE
    data[30:32] = nanoql_link.GOWIN_GW2AR18_DEVICE_ID
    return bytes(data)


def sample_gowin_fs(data: bytes, checksum: int = 0xBB84) -> str:
    bits = "".join(f"{byte:08b}" for byte in data)
    return (
        "//File Title: Bitstream file\n"
        "//Device: GW2AR-18\n"
        f"//CheckSum: 0x{checksum:04X}\n"
        f"{bits}\n"
    )


class FpgaBitstreamTests(unittest.TestCase):
    def test_release_folder_selects_and_decodes_fpga_fs(self) -> None:
        data = sample_gowin_binary()
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / "NanoQL-v0.3.1-BL616-3923.bin").write_bytes(b"BFNP")
            fs_path = folder / "NanoQL-v0.3.1-FPGA.fs"
            fs_path.write_text(sample_gowin_fs(data), encoding="ascii")
            (folder / "NanoQL-v0.3.1-FPGA-SRAM.bin").write_bytes(data)
            with patch.object(nanoql_link, "GOWIN_BITSTREAM_MIN_SIZE", 32):
                source, decoded, checksum = nanoql_link.load_gowin_bitstream(folder)
        self.assertEqual(source, fs_path.resolve())
        self.assertEqual(decoded, data)
        self.assertEqual(checksum, 0xBB84)

    def test_bl616_firmware_is_rejected_before_programming(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            firmware = Path(directory) / "NanoQL-v0.3.1-BL616-3923.bin"
            firmware.write_bytes(b"BFNP" + bytes(64))
            with self.assertRaisesRegex(ValueError, "BL616 firmware"):
                nanoql_link.load_gowin_bitstream(firmware)

    def test_release_binary_finds_differently_named_fs_checksum(self) -> None:
        data = sample_gowin_binary()
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            binary = folder / "NanoQL-v0.3.1-FPGA-SRAM.bin"
            binary.write_bytes(data)
            (folder / "NanoQL-v0.3.1-FPGA.fs").write_text(
                sample_gowin_fs(data, checksum=0x1234), encoding="ascii"
            )
            with patch.object(nanoql_link, "GOWIN_BITSTREAM_MIN_SIZE", 32):
                source, loaded, checksum = nanoql_link.load_gowin_bitstream(
                    binary, require_checksum=True
                )
        self.assertEqual(source, binary.resolve())
        self.assertEqual(loaded, data)
        self.assertEqual(checksum, 0x1234)

    def test_non_gowin_binary_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "wrong.bin"
            binary.write_bytes(bytes(64))
            with patch.object(nanoql_link, "GOWIN_BITSTREAM_MIN_SIZE", 32):
                with self.assertRaisesRegex(ValueError, "missing preamble"):
                    nanoql_link.load_gowin_bitstream(binary)


if __name__ == "__main__":
    unittest.main()

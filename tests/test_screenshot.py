import contextlib
import io
import struct
import sys
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from nanoql_link import NanoQLLink, SCREENSHOT_ADDRESS, ql_screen_png


def png_rows(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    offset = 8
    compressed = bytearray()
    while offset < len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + size]
        crc = struct.unpack_from(">I", data, offset + 8 + size)[0]
        assert crc == zlib.crc32(kind + body) & 0xFFFFFFFF
        if kind == b"IHDR":
            assert struct.unpack(">IIBBBBB", body) == (512, 256, 8, 2, 0, 0, 0)
        if kind == b"IDAT":
            compressed.extend(body)
        offset += size + 12
    return zlib.decompress(compressed)


class ScreenshotTests(unittest.TestCase):
    def test_mode4_colors_and_png_crc(self):
        # First four pixels are black, red, green, white.
        frame = bytes.fromhex("3050") + bytes(32766)
        rows = png_rows(ql_screen_png(frame, 0))
        self.assertEqual(len(rows), 256 * (1 + 512 * 3))
        self.assertEqual(rows[:13], bytes.fromhex("00 000000 d02020 20b040 ffffff"))

    def test_mode8_colors_are_doubled_horizontally(self):
        rows = png_rows(ql_screen_png(bytes.fromhex("0a13") + bytes(32766), 1))
        self.assertEqual(rows[1:25], bytes.fromhex(
            "000000 000000 2040d0 2040d0 20b040 20b040 ffffff ffffff"
        ))

    def test_blank_and_flash_latch_reset_at_each_line(self):
        frame = bytes.fromhex("5000") + bytes(32766)
        self.assertEqual(set(png_rows(ql_screen_png(frame, 3))), {0})
        rows = png_rows(ql_screen_png(frame, 5))
        self.assertEqual(set(rows), {0})
        # Red first pixel with F=1 makes the next black pixel flash red.
        frame = bytes.fromhex("4080") + bytes(32766)
        rows = png_rows(ql_screen_png(frame, 5))
        self.assertEqual(rows[1:13], bytes.fromhex("d02020") * 4)
        self.assertEqual(rows[1538:1544], bytes(6))

    def test_invalid_frame_size(self):
        with self.assertRaises(ValueError):
            ql_screen_png(bytes(10), 0)

    def test_old_fpga_is_rejected(self):
        class Old:
            def transact(self, _request):
                return bytes(9)
        with self.assertRaisesRegex(RuntimeError, "does not support screenshots"):
            NanoQLLink.screenshot_info(Old())

    def test_capture_does_not_change_cpu_state_and_releases_buffer(self):
        class Fake(NanoQLLink):
            def __init__(self):
                self.commands = []
                self.reconnect_count = 0
                self.address = 0

            def status(self):
                return 0x09

            def wait_idle(self, expect_hold):
                assert expect_hold

            def transact(self, payload):
                self.commands.append(payload[0])
                if payload[0] == 0x12:
                    return b"\x00SC1\x01\x00\x00\x00\x00"
                if payload[0] == 6:
                    self.address = int.from_bytes(payload[1:4], "big")
                    assert SCREENSHOT_ADDRESS <= self.address < SCREENSHOT_ADDRESS + 32768
                if payload[0] == 7:
                    return b"\x00" + bytes((self.address & 255,)) * 8
                return bytes(1)

        link = Fake()
        with contextlib.redirect_stdout(io.StringIO()):
            frame, flags = link.screenshot()
        self.assertEqual(len(frame), 32768)
        self.assertEqual(flags, 0)
        self.assertEqual(frame[8:16], bytes((8,)) * 8)
        self.assertNotIn(1, link.commands)  # HOLD
        self.assertNotIn(13, link.commands)  # RESUME
        self.assertEqual(link.commands[-1], 0x13)


if __name__ == "__main__":
    unittest.main()

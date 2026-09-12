import contextlib
import io
import struct
import sys
import types
import unittest
from unittest.mock import Mock, patch
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from nanoql_link import (
    NanoQLLink, SCREENSHOT_ADDRESS, ql_screen_png, keyboard_screenshot,
    interactive_keyboard_windows, interactive_keyboard_pynput,
    windows_realtime_keymap,
)


def png_rows(data, size=(512, 256)):
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    offset = 8
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        assert crc == zlib.crc32(kind + body) & 0xFFFFFFFF
        if kind == b"IHDR":
            assert struct.unpack(">IIBBBBB", body) == (*size, 8, 2, 0, 0, 0)
        if kind == b"IDAT":
            compressed.extend(body)
        offset += length + 12
    return zlib.decompress(compressed)


class ScreenshotTests(unittest.TestCase):
    def test_mode4_colors_and_png_crc(self):
        # First four pixels are black, red, green, white.
        frame = bytes.fromhex("3050") + bytes(32766)
        rows = png_rows(ql_screen_png(frame, 0, native=True))
        self.assertEqual(len(rows), 256 * (1 + 512 * 3))
        self.assertEqual(rows[:13], bytes.fromhex("00 000000 d02020 20b040 ffffff"))

    def test_mode8_colors_are_doubled_horizontally(self):
        rows = png_rows(ql_screen_png(bytes.fromhex("0a13") + bytes(32766), 1, native=True))
        self.assertEqual(rows[1:25], bytes.fromhex(
            "000000 000000 2040d0 2040d0 20b040 20b040 ffffff ffffff"
        ))

    def test_blank_and_flash_latch_reset_at_each_line(self):
        frame = bytes.fromhex("5000") + bytes(32766)
        self.assertEqual(set(png_rows(ql_screen_png(frame, 3, native=True))), {0})
        rows = png_rows(ql_screen_png(frame, 5, native=True))
        self.assertEqual(set(rows), {0})
        # Red first pixel with F=1 makes the next black pixel flash red.
        frame = bytes.fromhex("4080") + bytes(32766)
        rows = png_rows(ql_screen_png(frame, 5, native=True))
        self.assertEqual(rows[1:13], bytes.fromhex("d02020") * 4)
        self.assertEqual(rows[1538:1544], bytes(6))

    def test_invalid_frame_size(self):
        with self.assertRaises(ValueError):
            ql_screen_png(bytes(10), 0)

    def test_default_geometry_matches_hdmi_sharp_without_crop_or_blending(self):
        frame = bytes(range(256)) * 128
        for flags in (0, 1, 3, 5):
            with self.subTest(flags=flags):
                original = png_rows(ql_screen_png(frame, flags, native=True))
                corrected = png_rows(ql_screen_png(frame, flags), (1024, 698))
                self.assertEqual(len(corrected), 698 * 3073)
                sampled_rows = set()
                for y in range(698):
                    source_y = y * 256 // 698
                    sampled_rows.add(source_y)
                    start = source_y * 1537 + 1
                    row = original[start:start + 1536]
                    doubled = b"".join(row[x:x + 3] * 2 for x in range(0, 1536, 3))
                    self.assertEqual(corrected[y * 3073:(y + 1) * 3073], b"\0" + doubled)
                self.assertEqual(sampled_rows, set(range(256)))

    def test_sharp_dimensions_follow_rtl(self):
        rtl = (Path(__file__).resolve().parents[1] / "src/ql_hdmi_window.sv").read_text()
        self.assertIn("ql_width = 11'd1024;", rtl)
        self.assertIn("ql_height = 10'd698;", rtl)

    def test_old_fpga_is_rejected(self):
        class Old:
            def transact(self, _request):
                return bytes(9)
        with self.assertRaisesRegex(RuntimeError, "does not support screenshots"):
            NanoQLLink.screenshot_info(Old())

    def test_f11_capture_releases_keys_even_after_error(self):
        release = Mock()
        link = Mock()
        folder = Path("captures")
        with patch("nanoql_link.save_screenshot", side_effect=RuntimeError("test error")) as save:
            with contextlib.redirect_stdout(io.StringIO()) as output:
                keyboard_screenshot(link, folder, release)
        save.assert_called_once_with(link, folder)
        self.assertEqual(release.call_count, 2)
        self.assertIn("Screenshot failed: test error", output.getvalue())

    def test_windows_f11_is_local_and_does_not_repeat_while_held(self):
        mapping = windows_realtime_keymap()
        self.assertNotIn(0x7A, mapping)
        self.assertNotIn(0x75, mapping)
        self.assertEqual(mapping[0x7B], 0x45)  # F12 still reaches the overlay.
        f11_states = iter((False, True, True, True, False))

        def get_key(vk):
            return 0x8000 if vk == 0x7A and next(f11_states) else 0

        link = Mock(ql_layout="uk")
        windll = types.SimpleNamespace(user32=types.SimpleNamespace(GetAsyncKeyState=get_key))
        with patch("nanoql_link.ctypes.windll", windll, create=True), \
                patch("nanoql_link.windows_realtime_keymap", return_value=mapping), \
                patch.dict(sys.modules, {"msvcrt": types.SimpleNamespace(kbhit=lambda: False)}), \
                patch("nanoql_link.stop_requested", side_effect=(False, False, False, True)), \
                patch("nanoql_link.time.sleep"), \
                patch("nanoql_link.save_screenshot") as save, \
                contextlib.redirect_stdout(io.StringIO()):
            interactive_keyboard_windows(link, screenshot_folder=Path("captures"))
        save.assert_called_once_with(link, Path("captures"))
        link.key_event.assert_not_called()

    def test_pynput_f11_autorepeat_captures_once_on_serial_owner(self):
        key_names = types.SimpleNamespace(f6="F6", f11="F11", f12="F12")
        callback_active = False

        class Listener:
            def __init__(self, on_press, on_release, **_kwargs):
                self.on_press = on_press

            def start(self):
                nonlocal callback_active
                callback_active = True
                self.on_press("F11")
                self.on_press("F11")  # OS key-repeat must not queue a second PNG.
                callback_active = False

            def is_alive(self):
                return False

            def stop(self):
                pass

            def join(self, **_kwargs):
                pass

        keyboard = types.SimpleNamespace(Key=key_names, Listener=Listener)
        link = Mock(ql_layout="fr")

        def save_on_owner(*_args):
            self.assertFalse(callback_active)

        with patch.dict(sys.modules, {"pynput": types.SimpleNamespace(keyboard=keyboard)}), \
                patch("nanoql_link.sys.platform", "linux"), \
                patch("nanoql_link.sys.stdin.isatty", return_value=False), \
                patch("nanoql_link.save_screenshot", side_effect=save_on_owner) as save, \
                contextlib.redirect_stdout(io.StringIO()):
            interactive_keyboard_pynput(link, screenshot_folder=Path("captures"))
        save.assert_called_once_with(link, Path("captures"))
        link.key_event.assert_not_called()

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

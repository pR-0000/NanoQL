import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from nanoql_link import (  # noqa: E402
    CMD_KEY,
    KEY_DIRECT_MATRIX,
    MOD_LEFT_CTRL,
    MOD_LEFT_SHIFT,
    NanoQLLink,
)


class RemoteMatrixProtocolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.link = NanoQLLink.__new__(NanoQLLink)
        self.requests = []
        self.link.transact = self.requests.append

    def test_printable_contact_uses_direct_matrix_protocol(self) -> None:
        self.link.key_event(0x36, True)   # English QL comma
        self.link.key_event(0x36, False)
        self.assertEqual(
            self.requests,
            [bytes((CMD_KEY, KEY_DIRECT_MATRIX, 0x3F)),
             bytes((CMD_KEY, KEY_DIRECT_MATRIX, 0xBF))],
        )

    def test_overlay_key_keeps_legacy_menu_protocol(self) -> None:
        self.link.key_event(0x45, True)   # F12
        self.assertEqual(self.requests, [bytes((CMD_KEY, 0x45))])

    def test_overlay_navigation_keeps_raw_hid_usages(self) -> None:
        for usage in (0x28, 0x29, 0x2C, 0x4B, 0x4E, 0x4F, 0x50, 0x51, 0x52):
            with self.subTest(usage=usage):
                self.requests.clear()
                self.link.key_event(usage, True)
                self.link.key_event(usage, False)
                self.assertEqual(
                    self.requests,
                    [bytes((CMD_KEY, usage)), bytes((CMD_KEY, usage | 0x80))],
                )


class FrenchKeyboardMappingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.link = NanoQLLink.__new__(NanoQLLink)
        self.link.ql_layout = "fr"
        self.link.keyboard_layout = "host"

    def test_french_rom_ascii_punctuation(self) -> None:
        expected = {
            "!": (0x1E, (MOD_LEFT_SHIFT,)),
            "#": (0x20, (MOD_LEFT_SHIFT,)),
            "$": (0x21, (MOD_LEFT_SHIFT,)),
            "%": (0x22, (MOD_LEFT_SHIFT,)),
            "&": (0x24, (MOD_LEFT_SHIFT,)),
            "*": (0x25, (MOD_LEFT_SHIFT,)),
            "(": (0x26, (MOD_LEFT_SHIFT,)),
            ")": (0x27, (MOD_LEFT_SHIFT,)),
            "-": (0x2D, ()),
            "_": (0x2D, (MOD_LEFT_SHIFT,)),
            "=": (0x2E, ()),
            "+": (0x2E, (MOD_LEFT_SHIFT,)),
            ",": (0x10, ()),
            ".": (0x36, ()),
            ";": (0x37, ()),
            ":": (0x37, (MOD_LEFT_SHIFT,)),
            "'": (0x23, (MOD_LEFT_SHIFT,)),
            '"': (0x1F, (MOD_LEFT_SHIFT,)),
            "@": (0x23, (MOD_LEFT_CTRL,)),
            "<": (0x10, (MOD_LEFT_SHIFT,)),
            ">": (0x36, (MOD_LEFT_SHIFT,)),
            "[": (0x26, (MOD_LEFT_CTRL,)),
            "]": (0x27, (MOD_LEFT_CTRL,)),
            "{": (0x2D, (MOD_LEFT_CTRL,)),
            "}": (0x2E, (MOD_LEFT_CTRL,)),
            "^": (0x35, (MOD_LEFT_CTRL,)),
            "`": (0x38, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "\\": (0x2F, (MOD_LEFT_SHIFT,)),
            "|": (0x25, (MOD_LEFT_CTRL,)),
            "~": (0x31, (MOD_LEFT_CTRL,)),
            "/": (0x34, (MOD_LEFT_SHIFT,)),
            "?": (0x38, (MOD_LEFT_SHIFT,)),
        }
        for character, contact in expected.items():
            with self.subTest(character=character):
                self.assertEqual(self.link.character_key(character), contact)


    def test_french_rom_letters_use_azerty_contacts(self) -> None:
        expected = {
            "a": (0x14, ()), "A": (0x14, (MOD_LEFT_SHIFT,)),
            "q": (0x04, ()), "Q": (0x04, (MOD_LEFT_SHIFT,)),
            "z": (0x1A, ()), "Z": (0x1A, (MOD_LEFT_SHIFT,)),
            "w": (0x1D, ()), "W": (0x1D, (MOD_LEFT_SHIFT,)),
            "m": (0x33, ()), "M": (0x33, (MOD_LEFT_SHIFT,)),
        }
        for character, contact in expected.items():
            with self.subTest(character=character):
                self.assertEqual(self.link.character_key(character), contact)


class EnglishKeyboardMappingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.link = NanoQLLink.__new__(NanoQLLink)
        self.link.ql_layout = "uk"
        self.link.keyboard_layout = "host"

    def test_azerty_characters_target_english_ql_contacts(self) -> None:
        expected = {
            "1": (0x1E, ()), "&": (0x24, (MOD_LEFT_SHIFT,)),
            "8": (0x25, ()), "_": (0x2D, (MOD_LEFT_SHIFT,)),
            "m": (0x10, ()), "M": (0x10, (MOD_LEFT_SHIFT,)),
            ",": (0x36, ()), ";": (0x33, ()), ":": (0x33, (MOD_LEFT_SHIFT,)),
            '"': (0x34, (MOD_LEFT_SHIFT,)), "@": (0x1F, (MOD_LEFT_SHIFT,)),
            "£": (0x32, ()),
        }
        for character, contact in expected.items():
            with self.subTest(character=character):
                self.assertEqual(self.link.character_key(character), contact)

    def test_english_rom_uses_the_standard_ql_accent_table(self) -> None:
        expected = {
            "ä": (0x29, (MOD_LEFT_CTRL,)),
            "é": (0x20, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "è": (0x27, (MOD_LEFT_CTRL,)),
            "ê": (0x1E, (MOD_LEFT_CTRL,)),
            "ë": (0x38, (MOD_LEFT_CTRL,)),
            "à": (0x2D, (MOD_LEFT_CTRL,)),
            "â": (0x37, (MOD_LEFT_CTRL,)),
            "ç": (0x26, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "î": (0x22, (MOD_LEFT_CTRL,)),
            "ï": (0x1F, (MOD_LEFT_CTRL,)),
            "ô": (0x25, (MOD_LEFT_CTRL,)),
            "ö": (0x21, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "ù": (0x33, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "û": (0x33, (MOD_LEFT_CTRL,)),
            "ü": (0x34, (MOD_LEFT_CTRL,)),
            "É": (0x06, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "Ç": (0x0B, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
        }
        for character, contact in expected.items():
            with self.subTest(character=character):
                self.assertEqual(self.link.character_key(character), contact)

class FrenchNationalKeyboardMappingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.link = NanoQLLink.__new__(NanoQLLink)
        self.link.ql_layout = "fr"
        self.link.keyboard_layout = "host"

    def test_french_rom_national_characters(self) -> None:
        expected = {
            "é": (0x2F, ()),
            "è": (0x30, ()),
            "ù": (0x31, ()),
            "à": (0x34, ()),
            "ç": (0x38, ()),
            "ê": (0x1E, (MOD_LEFT_CTRL,)),
            "ï": (0x26, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "î": (0x37, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "ô": (0x1A, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "û": (0x37, (MOD_LEFT_CTRL,)),
            "É": (0x06, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "Ç": (0x0B, (MOD_LEFT_SHIFT, MOD_LEFT_CTRL)),
            "§": (0x30, (MOD_LEFT_SHIFT,)),
            "£": (0x31, (MOD_LEFT_SHIFT,)),
            "°": (0x24, (MOD_LEFT_CTRL,)),
        }
        for character, contact in expected.items():
            with self.subTest(character=character):
                self.assertEqual(self.link.character_key(character), contact)


if __name__ == "__main__":
    unittest.main()

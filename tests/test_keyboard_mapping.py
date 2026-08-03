import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from nanoql_link import (  # noqa: E402
    MOD_LEFT_ALT,
    MOD_LEFT_CTRL,
    MOD_LEFT_SHIFT,
    NanoQLLink,
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
            "^": (0x32, (MOD_LEFT_CTRL,)),
            "`": (0x38, (MOD_LEFT_ALT,)),
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
        }
        for character, contact in expected.items():
            with self.subTest(character=character):
                self.assertEqual(self.link.character_key(character), contact)

    def test_accented_letters_are_folded_for_an_english_rom(self) -> None:
        expected = {
            "é": "e", "è": "e", "ê": "e", "ë": "e",
            "à": "a", "â": "a", "ä": "a", "ç": "c",
            "î": "i", "ï": "i", "ô": "o", "ö": "o",
            "ù": "u", "û": "u", "ü": "u", "É": "E",
        }
        for accented, plain in expected.items():
            with self.subTest(character=accented):
                self.assertEqual(
                    self.link.character_key(accented),
                    self.link.character_key(plain),
                )

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
            "§": (0x30, (MOD_LEFT_SHIFT,)),
            "£": (0x31, (MOD_LEFT_SHIFT,)),
            "°": (0x24, (MOD_LEFT_CTRL,)),
        }
        for character, contact in expected.items():
            with self.subTest(character=character):
                self.assertEqual(self.link.character_key(character), contact)


if __name__ == "__main__":
    unittest.main()

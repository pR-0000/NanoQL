import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from nanoql_link import (  # noqa: E402
    NanoQLLink,
    disassemble_m68000,
    find_ir_address,
    format_disassembly_dump,
    format_hex_dump,
)


class DisassemblerTests(unittest.TestCase):
    def test_debugger_capability_signature_is_explicit(self) -> None:
        class FakeLink:
            @staticmethod
            def transact(_request):
                return b"\x00DB2\x07\x08\x00"

        self.assertEqual(
            NanoQLLink.debugger_info(FakeLink()),
            {"version": 2, "capabilities": 7, "max_read": 8},
        )

    def test_old_bitstream_gets_actionable_error(self) -> None:
        class FakeLink:
            @staticmethod
            def transact(_request):
                return bytes(9)

        with self.assertRaisesRegex(RuntimeError, "predates"):
            NanoQLLink.debugger_info(FakeLink())

    def test_known_68000_instructions_keep_raw_bytes(self) -> None:
        code = bytes.fromhex("7001 5280 4e75")
        instructions = disassemble_m68000(code, 0x030000)

        self.assertEqual(
            [item[0] for item in instructions],
            [0x030000, 0x030002, 0x030004],
        )
        self.assertEqual(b"".join(item[1] for item in instructions), code)
        self.assertEqual(
            [item[2].split()[0] for item in instructions],
            ["moveq", "addq.l", "rts"],
        )

    def test_ir_match_uses_nearest_aligned_word_before_pc(self) -> None:
        data = bytes.fromhex("4e71 7001 4e71 4e75")
        self.assertEqual(
            find_ir_address(data, 0x030000, 0x030008, 0x4E71),
            0x030004,
        )

    def test_hex_dump_preserves_address_bytes_and_ascii(self) -> None:
        text = format_hex_dump(b"NanoQL\x00\xff", 0x020000)
        self.assertIn("020000: 4e 61 6e 6f 51 4c 00 ff", text)
        self.assertIn("NanoQL..", text)

    def test_text_disassembly_contains_only_reusable_instructions(self) -> None:
        text = format_disassembly_dump(bytes.fromhex("7001 4e75"), 0x030000)
        self.assertEqual(text.splitlines(), ["\tmoveq #$1, d0", "\trts"])
        self.assertNotIn("030000", text)
        self.assertNotIn("70 01", text)


if __name__ == "__main__":
    unittest.main()

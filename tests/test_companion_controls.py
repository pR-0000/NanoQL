import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]


class CompanionControlTests(unittest.TestCase):
    def test_overlay_exposes_stateful_session_pause(self) -> None:
        xml = (REPOSITORY / "src" / "companion" / "nanoql.xml").read_text(
            encoding="utf-8"
        )
        self.assertIn('<menu label="NanoQL v0.3.9">', xml)
        self.assertIn('<list label="Execution:" id="P" default="0">', xml)
        self.assertIn('<listentry label="Running" value="0"/>', xml)
        self.assertIn('<listentry label="Paused" value="1"/>', xml)
        self.assertNotIn("[F9]", xml)

    def test_remote_f9_uses_the_overlay_pause_variable(self) -> None:
        source = (
            REPOSITORY
            / "firmware"
            / "bl616"
            / "nanoql_companion"
            / "nanoql_usb.c"
        ).read_text(encoding="utf-8")
        self.assertIn("if (usage == 0x42) { /* F9 */", source)
        self.assertIn("menu_toggle_value('P');", source)

    def test_standalone_screenshot_reports_success(self) -> None:
        source = (
            REPOSITORY
            / "firmware"
            / "bl616"
            / "nanoql_companion"
            / "nanoql_screenshot.c"
        ).read_text(encoding="utf-8")
        self.assertIn('"[OK] Saved %s"', source)


if __name__ == "__main__":
    unittest.main()

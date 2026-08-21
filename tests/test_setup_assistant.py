import base64
import runpy
import struct
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
GUI = REPOSITORY / "tools" / "nanoql_setup.pyw"


class SetupAssistantTests(unittest.TestCase):
    def test_embedded_board_guide_is_valid_gif(self) -> None:
        namespace = runpy.run_path(str(GUI), run_name="nanoql_setup_test")
        images = namespace["BOARD_GUIDE_GIFS"]
        self.assertEqual(set(images), {"normal", "s1", "update"})
        for image_data in images.values():
            image = base64.b64decode(image_data)
            self.assertIn(image[:6], (b"GIF87a", b"GIF89a"))
            self.assertEqual(struct.unpack_from("<HH", image, 6), (360, 174))

    def test_beginner_labels_and_compatibility_launcher(self) -> None:
        source = GUI.read_text(encoding="utf-8")
        self.assertIn("Program SRAM (temporary)", source)
        self.assertIn("Program Flash (permanent)", source)
        self.assertIn('text="2. BL616"', source)
        self.assertIn('text="3. FPGA"', source)
        self.assertIn('text="4. NanoQL Link"', source)
        self.assertIn('text="Program injection"', source)
        self.assertIn('"Install / update NanoQL firmware",', source)
        self.assertNotIn("messagebox.askyesno", source)
        self.assertTrue((REPOSITORY / "tools" / "nanoql_setup.py").is_file())

    def test_french_catalog_covers_beginner_workflow(self) -> None:
        namespace = runpy.run_path(str(GUI), run_name="nanoql_setup_test")
        translations = namespace["TRANSLATIONS"]["fr"]
        for text in (
            "Start here",
            "2. BL616",
            "3. FPGA",
            "4. NanoQL Link",
            "Program SRAM (temporary)",
            "Program Flash (permanent)",
            "Install / update NanoQL firmware",
            "Inject and execute",
        ):
            self.assertIn(text, translations)


if __name__ == "__main__":
    unittest.main()

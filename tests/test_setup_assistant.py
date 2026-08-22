import base64
import runpy
import struct
import tempfile
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
        self.assertIn("Release folder or FPGA file", source)
        self.assertIn("Extracted release folder", source)
        self.assertIn("NanoQL BL616 firmware", source)
        self.assertIn("Select folder...", source)
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
            "Release folder or FPGA file",
            "Extracted release folder",
            "NanoQL BL616 firmware",
            "Select release folder...",
            "Select folder...",
            "Install / update NanoQL firmware",
            "Inject and execute",
        ):
            self.assertIn(text, translations)

    def test_release_folder_populates_matching_bl616_and_fpga_files(self) -> None:
        namespace = runpy.run_path(str(GUI), run_name="nanoql_setup_test")
        resolve = namespace["resolve_release_bundle"]
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary) / "NanoQL-v0.4.0-Complete-3923"
            release.mkdir()
            firmware = release / "NanoQL-v0.4.0-BL616-3923.bin"
            firmware.write_bytes(b"BFNP" + bytes(32))
            (release / "NanoQL-v0.4.0-BL616-3921.bin").write_bytes(
                b"BFNP" + bytes(32)
            )
            bitstream = release / "NanoQL-v0.4.0-FPGA.fs"
            bitstream.write_text("// synthetic test", encoding="ascii")

            selected_firmware, selected_bitstream = resolve(str(release), "3923")

            self.assertEqual(selected_firmware, firmware.resolve())
            self.assertEqual(selected_bitstream, bitstream.resolve())

    def test_release_folder_rejects_missing_board_revision(self) -> None:
        namespace = runpy.run_path(str(GUI), run_name="nanoql_setup_test")
        resolve = namespace["resolve_release_bundle"]
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            (release / "NanoQL-v0.4.0-BL616-3921.bin").write_bytes(
                b"BFNP" + bytes(32)
            )
            (release / "NanoQL-v0.4.0-FPGA.fs").write_text(
                "// synthetic test", encoding="ascii"
            )
            with self.assertRaises(FileNotFoundError):
                resolve(str(release), "3923")


if __name__ == "__main__":
    unittest.main()

import json
import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from nanoql_drive import (  # noqa: E402
    DriveFile,
    build_qlay_image,
    extract_qlay_image,
    parse_qlay_image,
)


class NanoQLDriveTest(unittest.TestCase):
    def test_build_and_extract_round_trip(self) -> None:
        files = [
            DriveFile("hello_bas", b"100 PRINT \"HELLO\"\n"),
            DriveFile("machine_bin", bytes(range(256)), True, 4096),
        ]
        image = build_qlay_image(files, "TEST")
        parsed = parse_qlay_image(image)
        self.assertEqual([file.name for file in parsed], ["hello_bas", "machine_bin"])
        self.assertEqual([file.data for file in parsed], [files[0].data, files[1].data])
        self.assertTrue(parsed[1].executable)
        self.assertEqual(parsed[1].data_space, 4096)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "files"
            written = extract_qlay_image(image, output)
            self.assertEqual((output / "hello_bas").read_bytes(), files[0].data)
            self.assertEqual((output / "machine_bin").read_bytes(), files[1].data)
            self.assertEqual(len(written), 2)
            manifest = json.loads((output / "nanoql_manifest.json").read_text())
            self.assertEqual(manifest["files"][1]["data_space"], 4096)

    def test_rejects_corrupt_data_checksum(self) -> None:
        image = bytearray(build_qlay_image([DriveFile("test", b"data")]))
        image[52] ^= 0x01
        with self.assertRaisesRegex(ValueError, "data checksum"):
            parse_qlay_image(bytes(image))


if __name__ == "__main__":
    unittest.main()

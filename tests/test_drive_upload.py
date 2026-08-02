import sys
import tempfile
import unittest
import zlib
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from nanoql_link import (  # noqa: E402
    CMD_FS_CANCEL,
    CMD_FS_INFO,
    CMD_FS_PUT_BEGIN,
    CMD_FS_PUT_COMMIT,
    CMD_FS_PUT_DATA,
    NanoQLLink,
)


class FakeSerial:
    def __init__(self) -> None:
        self.timeout = 2.0


class FakeDriveLink(NanoQLLink):
    def __init__(self, payload: bytes) -> None:
        self.serial = FakeSerial()
        self.payload = payload
        self.timeouts: dict[int, list[float]] = {}

    def transact(self, request: bytes) -> bytes:
        command = request[0]
        self.timeouts.setdefault(command, []).append(self.serial.timeout)
        if command == CMD_FS_INFO:
            return b"NFS1" + bytes((1, 0x1F, 200))
        if command == CMD_FS_PUT_BEGIN:
            return b"\x00"
        if command == CMD_FS_PUT_DATA:
            offset = int.from_bytes(request[1:5], "big")
            return (offset + len(request) - 5).to_bytes(4, "big")
        if command == CMD_FS_PUT_COMMIT:
            checksum = zlib.crc32(self.payload) & 0xFFFFFFFF
            return len(self.payload).to_bytes(4, "big") + checksum.to_bytes(4, "big")
        if command == CMD_FS_CANCEL:
            return b"\x00"
        raise AssertionError(f"Unexpected command 0x{command:02x}")


class DriveUploadTimeoutTests(unittest.TestCase):
    def test_slow_card_timeouts_are_scoped_to_upload(self) -> None:
        payload = bytes(range(256)) * 3
        link = FakeDriveLink(payload)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "test.bin"
            source.write_bytes(payload)
            link.filesystem_put(source, "tests/test.bin")

        self.assertEqual(link.serial.timeout, 2.0)
        self.assertGreaterEqual(link.timeouts[CMD_FS_PUT_BEGIN][0], 15.0)
        self.assertTrue(
            all(value >= 15.0 for value in link.timeouts[CMD_FS_PUT_DATA])
        )
        self.assertGreaterEqual(link.timeouts[CMD_FS_PUT_COMMIT][0], 60.0)


if __name__ == "__main__":
    unittest.main()

import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch


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


class LostCommitReplyDriveLink(FakeDriveLink):
    def __init__(self, payload: bytes) -> None:
        super().__init__(payload)
        self.commit_attempts = 0
        self.verified_path = None

    def transact(self, request: bytes) -> bytes:
        if request[0] == CMD_FS_PUT_COMMIT:
            self.commit_attempts += 1
            raise RuntimeError(
                "Missing or invalid response from the NanoQL Link BL616 firmware."
            )
        return super().transact(request)

    def filesystem_crc32(self, remote_path: str) -> tuple[int, int]:
        self.verified_path = remote_path
        return len(self.payload), zlib.crc32(self.payload) & 0xFFFFFFFF


class PhasedCommitDriveLink(FakeDriveLink):
    def __init__(self, payload: bytes) -> None:
        super().__init__(payload)
        self.commit_attempts = 0

    def transact(self, request: bytes) -> bytes:
        if request[0] == CMD_FS_PUT_COMMIT:
            self.timeouts.setdefault(request[0], []).append(self.serial.timeout)
            self.commit_attempts += 1
            if self.commit_attempts <= 3:
                return bytes((0xFE, self.commit_attempts))
        return super().transact(request)


class InlineCommitDriveLink(FakeDriveLink):
    def __init__(self, payload: bytes) -> None:
        super().__init__(payload)
        self.commit_attempts = 0

    def transact(self, request: bytes) -> bytes:
        if request[0] == CMD_FS_PUT_DATA:
            response = super().transact(request)
            if int.from_bytes(response, "big") == len(self.payload):
                checksum = zlib.crc32(self.payload) & 0xFFFFFFFF
                return (
                    response
                    + len(self.payload).to_bytes(4, "big")
                    + checksum.to_bytes(4, "big")
                )
            return response
        if request[0] == CMD_FS_PUT_COMMIT:
            self.commit_attempts += 1
        return super().transact(request)


class StalledCommitDriveLink(FakeDriveLink):
    def transact(self, request: bytes) -> bytes:
        if request[0] == CMD_FS_PUT_COMMIT:
            return bytes((0xFE, 2))
        return super().transact(request)


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
        self.assertGreaterEqual(link.timeouts[CMD_FS_PUT_COMMIT][0], 30.0)

    def test_lost_commit_reply_is_recovered_by_remote_crc(self) -> None:
        payload = b"NanoQL MDV recovery" * 32
        link = LostCommitReplyDriveLink(payload)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "MDV1.mdv"
            source.write_bytes(payload)
            link.filesystem_put(source, "MDV1.mdv")

        self.assertEqual(link.commit_attempts, 2)
        self.assertEqual(link.verified_path, "MDV1.mdv")
        self.assertEqual(link.serial.timeout, 2.0)

    def test_phased_commit_completes_all_filesystem_operations(self) -> None:
        payload = b"NanoQL phased commit" * 32
        link = PhasedCommitDriveLink(payload)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "MDV1.mdv"
            source.write_bytes(payload)
            link.filesystem_put(source, "MDV1.mdv")

        self.assertEqual(link.commit_attempts, 4)
        self.assertEqual(link.serial.timeout, 2.0)

    def test_inline_verification_skips_separate_commit_transaction(self) -> None:
        payload = b"NanoQL inline verification" * 32
        link = InlineCommitDriveLink(payload)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "MDV1.mdv"
            source.write_bytes(payload)
            link.filesystem_put(source, "MDV1.mdv")

        self.assertEqual(link.commit_attempts, 0)
        self.assertEqual(link.serial.timeout, 2.0)

    def test_stalled_commit_is_bounded_and_cancelled(self) -> None:
        payload = b"NanoQL stalled commit" * 32
        link = StalledCommitDriveLink(payload)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "MDV1.mdv"
            source.write_bytes(payload)
            with patch("nanoql_link.SD_COMMIT_STALL_TIMEOUT", 0.0):
                with self.assertRaisesRegex(TimeoutError, "did not complete"):
                    link.filesystem_put(source, "MDV1.mdv")

        self.assertEqual(link.serial.timeout, 2.0)


if __name__ == "__main__":
    unittest.main()

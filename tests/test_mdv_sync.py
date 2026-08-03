import types
import unittest

from tools.nanoql_link import CMD_FS_MDV_CONTROL, NanoQLLink


class MicrodriveSyncTests(unittest.TestCase):
    def test_mount_releases_companion_reset_before_final_qdos_restart(self) -> None:
        link = NanoQLLink.__new__(NanoQLLink)
        link.serial = types.SimpleNamespace(timeout=1.0)
        requests = []

        link.filesystem_info = lambda: (0x20, 200)
        link.transact = lambda payload: requests.append(payload) or b"\x00"
        link.qdos = lambda: requests.append(b"qdos")

        link.microdrive_sync_control(True)

        self.assertEqual(
            requests,
            [
                bytes((CMD_FS_MDV_CONTROL, 1)),
                bytes((CMD_FS_MDV_CONTROL, 2)),
                b"qdos",
            ],
        )
        self.assertEqual(link.serial.timeout, 1.0)


if __name__ == "__main__":
    unittest.main()

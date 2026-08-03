import types
import unittest

from tools.nanoql_link import CMD_FS_MDV_CONTROL, NanoQLLink


class MicrodriveSyncTests(unittest.TestCase):
    def test_close_abandons_transitioning_cdc_handle(self) -> None:
        link = NanoQLLink.__new__(NanoQLLink)
        close_calls = []
        link.serial = types.SimpleNamespace(
            is_open=True,
            close=lambda: close_calls.append(True),
        )
        link.abandon_serial_on_close = True

        link.close()

        self.assertFalse(link.serial.is_open)
        self.assertEqual(close_calls, [])

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

    def test_mdv5_mount_reports_each_operation_separately(self) -> None:
        link = NanoQLLink.__new__(NanoQLLink)
        link.serial = types.SimpleNamespace(timeout=1.0)
        link.drive_firmware_build = "MDV5"
        requests = []

        link.filesystem_info = lambda: (0x20, 200)
        link.transact = lambda payload: requests.append(payload) or b"\x00"
        link.qdos = lambda: requests.append(b"qdos")

        link.microdrive_sync_control(True)

        self.assertEqual(
            requests,
            [
                bytes((CMD_FS_MDV_CONTROL, 3)),
                bytes((CMD_FS_MDV_CONTROL, 4)),
                bytes((CMD_FS_MDV_CONTROL, 5)),
                bytes((CMD_FS_MDV_CONTROL, 2)),
                b"qdos",
            ],
        )
        self.assertEqual(link.serial.timeout, 1.0)

    def test_mdv7_finishes_on_the_settings_acknowledgement(self) -> None:
        link = NanoQLLink.__new__(NanoQLLink)
        link.serial = types.SimpleNamespace(timeout=1.0)
        link.drive_firmware_build = "MDV7"
        requests = []

        link.filesystem_info = lambda: (0x20, 200)
        link.transact = lambda payload: requests.append(payload) or b"\x00"
        link.qdos = lambda: requests.append(b"qdos")

        link.microdrive_sync_control(True)

        self.assertEqual(
            requests,
            [
                bytes((CMD_FS_MDV_CONTROL, 3)),
                bytes((CMD_FS_MDV_CONTROL, 4)),
            ],
        )
        self.assertTrue(link.abandon_serial_on_close)
        self.assertEqual(link.serial.timeout, 1.0)

    def test_mdv8_uses_the_bounded_completion_sequence(self) -> None:
        link = NanoQLLink.__new__(NanoQLLink)
        link.serial = types.SimpleNamespace(timeout=1.0)
        link.drive_firmware_build = "MDV8"
        requests = []

        link.filesystem_info = lambda: (0x20, 200)
        link.transact = lambda payload: requests.append(payload) or b"\x00"

        link.microdrive_sync_control(True)

        self.assertEqual(
            requests,
            [
                bytes((CMD_FS_MDV_CONTROL, 3)),
                bytes((CMD_FS_MDV_CONTROL, 4)),
            ],
        )
        self.assertTrue(link.abandon_serial_on_close)
        self.assertEqual(link.serial.timeout, 1.0)

    def test_mdv9_mount_does_not_expect_a_usb_reset(self) -> None:
        link = NanoQLLink.__new__(NanoQLLink)
        link.serial = types.SimpleNamespace(timeout=1.0)
        link.drive_firmware_build = "MDV9"
        requests = []

        link.filesystem_info = lambda: (0x20, 200)
        link.transact = lambda payload: requests.append(payload) or b"\x00"

        link.microdrive_sync_control(True)

        self.assertEqual(
            requests,
            [
                bytes((CMD_FS_MDV_CONTROL, 3)),
                bytes((CMD_FS_MDV_CONTROL, 4)),
            ],
        )
        self.assertFalse(getattr(link, "abandon_serial_on_close", False))
        self.assertEqual(link.serial.timeout, 1.0)

    def test_md10_runtime_mount_does_not_expect_a_usb_reset(self) -> None:
        link = NanoQLLink.__new__(NanoQLLink)
        link.serial = types.SimpleNamespace(timeout=1.0)
        link.drive_firmware_build = "MD10"
        requests = []

        link.filesystem_info = lambda: (0x20, 200)
        link.transact = lambda payload: requests.append(payload) or b"\x00"

        link.microdrive_sync_control(True)

        self.assertEqual(
            requests,
            [
                bytes((CMD_FS_MDV_CONTROL, 3)),
                bytes((CMD_FS_MDV_CONTROL, 4)),
            ],
        )
        self.assertFalse(getattr(link, "abandon_serial_on_close", False))
        self.assertEqual(link.serial.timeout, 1.0)


if __name__ == "__main__":
    unittest.main()

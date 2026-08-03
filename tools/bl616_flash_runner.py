#!/usr/bin/env python3
"""Run Bouffalo Lab's BL616 flasher through its robust UART write path."""

from __future__ import annotations

BL616_WRITE_TIMEOUT_SECONDS = 30.0
BL616_FLASH_PAYLOAD_SIZE = 256


def main() -> None:
    # Importing the package adds its internal ``libs`` directory to sys.path.
    # bflb-mcu-tool 1.10.1 otherwise forces a three-second PySerial write
    # timeout, which is too short for some BL616 USB links on Windows/macOS.
    import bflb_mcu_tool  # noqa: F401
    from libs import bflb_interface_uart

    original_if_init = bflb_interface_uart.BflbUartPort.if_init

    def if_init_with_tolerant_writes(self, *args, **kwargs):
        result = original_if_init(self, *args, **kwargs)
        if self._ser is not None:
            self._ser.write_timeout = BL616_WRITE_TIMEOUT_SECONDS
        return result

    bflb_interface_uart.BflbUartPort.if_init = if_init_with_tolerant_writes

    from libs import bflb_eflash_loader

    original_flash_load = (
        bflb_eflash_loader.BflbEflashLoader.flash_load_main_process
    )

    def flash_load_without_compression(self, *args, **kwargs):
        # The BL616 USB BootROM can stop consuming the compressed command
        # stream on some hosts. Standard flash_write commands are individually
        # acknowledged and avoid leaving the board with a partially erased
        # firmware image.
        self._decompress_write = False
        # Once the verified image is installed, ask the BL616 loader to reset
        # the CPU and boot it from Flash. UPDATE has already been released by
        # the user, so the board leaves BootROM mode without a power cycle.
        self._cpu_reset = True
        # The tool normally sends 2048-byte protocol payloads. Smaller,
        # individually acknowledged blocks avoid filling the BL616 USB
        # BootROM endpoint on Windows while keeping the protocol unchanged.
        self._bflb_com_tx_size = BL616_FLASH_PAYLOAD_SIZE + 8
        return original_flash_load(self, *args, **kwargs)

    bflb_eflash_loader.BflbEflashLoader.flash_load_main_process = (
        flash_load_without_compression
    )

    print(
        "NanoQL BL616 flasher: using 256-byte acknowledged writes "
        f"with a {BL616_WRITE_TIMEOUT_SECONDS:.0f}-second serial timeout; "
        "the BL616 will restart after verification."
    )

    bflb_eflash_loader.run()


if __name__ == "__main__":
    main()

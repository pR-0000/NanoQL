# NanoQL unified BL616 firmware

This source module extends the pinned FPGA Companion firmware with a safe USB role choice:

- S1 left untouched: autonomous Companion mode with USB keyboard and microSD;
- S1 pressed after the FPGA LEDs start, including while QDOS runs: NanoQL Link USB CDC development mode without resetting the FPGA.

S1 is also the Gowin MODE0 configuration pin and must not be held while the board is powered on. Press it only after the FPGA LEDs or HDMI output appear. The FPGA latches S1 and exposes it through the standard `SPI_SYS_BUTTONS` command. S2 is not used by NanoQL Link. If the FPGA does not answer, the firmware deliberately selects autonomous mode. Switching to CDC disconnects the USB-host keyboard; the remote keyboard can then take over. The module and patch contain no generated firmware or third-party binary.

NanoQL Link is a USB CDC device, not the official FPGA Partner firmware's dual-channel `SIPEED USB Debugger`. It streams bitstreams directly from USB to the BL616 JTAG engine through the NanoQL Python tool, without using the microSD, but does not enumerate as the A/B interface expected by Gowin Programmer. The `fpga` command targets volatile SRAM. Persistent SPI Flash programming is disabled until its failure recovery path has been validated on hardware; use Gowin Programmer for persistent configuration.

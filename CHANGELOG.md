# Changelog

## v0.1.0 - 2026-07-23

First packaged NanoQL release for Tang Nano 20K revisions 3921 and 3923.

- Boots selectable QL ROMs from microSD with 128, 640, or 896 KiB RAM.
- Provides faithful ZX8301 video timing, HDMI 720p50 output, QL sound, and optional QSound.
- Removes QSound crackle by keeping AY timing independent from CPU speed and using stable HDMI audio-domain transfer.
- Provides live QL and 16 MHz CPU modes.
- Adds QL-SD reads and writable persistent Microdrive support.
- Converts microSD folders to MDV1 cartridges directly from the overlay.
- Adds QWERTY/AZERTY USB and English/French ROM keyboard profiles, including corrected punctuation mappings.
- Adds the NanoQL Link USB development interface and direct FPGA SRAM loading.
- Displays the NanoQL version in the overlay.

The release assets contain compiled BL616 firmware images for both supported board revisions. The FPGA bitstream is built locally because it currently embeds the user-supplied IPC firmware; publishing it would redistribute that firmware indirectly. User-supplied QL, IPC, QL-SD, and QSound ROM images are not distributed.

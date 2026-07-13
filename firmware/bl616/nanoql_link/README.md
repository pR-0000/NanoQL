# NanoQL Link firmware

This directory contains the source-only BL616 USB CDC to FPGA SPI bridge used by NanoQL Link. No generated firmware is committed. The two Tang Nano 20K revisions require separate builds because their internal BL616 SPI data pins differ.

Build targets:

- `make TANG_BOARD=nano20k` for revision 3921;
- `make TANG_BOARD=nano20k_v3923` for revision 3923.

The automated workflow pins these upstream revisions:

- MiSTle-Dev Bouffalo SDK: `b51858d3fe5ffb587718167b8115c4188fb369de`;
- Bouffalo RISC-V Linux toolchain: `c4afe91cbd01bf7dce525e0d23b4219c8691e8f0`.

The CherryUSB CDC descriptor and endpoint pattern are adapted from the Bouffalo SDK `cherryusb_cli` example, copyright (c) 2024 sakumisu. The SPI pin mapping and initialization pattern are adapted from MiSTle-Dev FPGA Companion `v1.4.22`. Both upstream sources are Apache-2.0 licensed. NanoQL-specific code is distributed under GPL-3.0-only.

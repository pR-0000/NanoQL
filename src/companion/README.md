# NanoQL FPGA Companion integration

NanoQL uses the standard MiSTle FPGA Companion protocol in SPI mode 1. Tang Nano 20K revisions 3921 and 3923 use their on-board BL616 with the upstream `nano20k` and `nano20k_v3923` firmware targets respectively. The FPGA bitstream is common; only the BL616 SPI pin mapping differs.

The files under `vendor/` are imported from MiSTeryNano and retain their original notices. MiSTeryNano and NanoQL are distributed under GPLv3.

The generated `nanoql_xml.hex` contains the gzip-compressed `nanoql.xml` configuration served to FPGA Companion. Regenerate it from the repository root with `tools/build_companion_config.ps1`. Target 0 is the QL ROM and target 1 is the optional QL-SD image. The microSD preparation tools also create `nanoql.ini`; the XML loads it at startup so Companion mounts `/sd/QL.rom` as drive 0. The XML `default` attribute alone only configures the selector and does not mount a file. `ql_sd_rom_loader.sv` accepts 48 KiB and 64 KiB images, pads a 48 KiB image to 64 KiB with `0xff`, stores it in the reserved SDRAM ROM area, and verifies every word before releasing the 68000.

`ql_companion_hid.sv` consumes the first raw USB event in FPGA Companion HID command 1 packets. It maintains the original QL 8x8 matrix and feeds it to the 8049 data bus according to the row selected on `P1`. Later PS/2 compatibility bytes in each packet are ignored. The mapping is adapted from the MiST QL keyboard implementation and retains its delayed modifier combinations.

`ql_companion_osd.sv` implements the FPGA Companion `u8g2` 128x64 display protocol in one BSRAM block. It composites a centered 2x overlay after the QL video path, allowing the firmware menu to remain visible without modifying QL VRAM.

The vendor modules were imported from MiSTeryNano revision `1b4432869e3c4bcedf68f138e1a3beb7421c43aa`.

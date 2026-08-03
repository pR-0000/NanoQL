# Changelog

## v0.2.7 - 2026-08-03

- Advanced MDV synchronization now restarts QDOS through the FPGA host link and explicitly releases the Companion reset afterward, preventing the BL616 holding-reset startup screen.

## v0.2.6 - 2026-08-02

- Stops Gowin `programmer_cli` after its final status when affected versions remain resident and would lock USB Debugger A/1 for subsequent attempts.
- Reports stale programmer processes, a changed cable location, and the required BL616 ORIGINAL profile directly in the setup assistant.
- Probes the FPGA external Flash before erasing it and bounds Gowin detection/programming time so a failed SPI handover cannot hang indefinitely.
- Keeps macOS Terminal echo enabled so Secure Keyboard Entry cannot block `pynput`, while still flushing buffered input when the remote keyboard exits.
- Reconciles macOS remote-keyboard state with Quartz so a missed key-release event cannot leave a repeating key or modifier stuck in the QL matrix.
- Resets only the QL after `mdv-sync`, keeping NanoQL Link and the remote keyboard active on the same serial port.

## v0.2.5 - 2026-08-02

- Returns the BL616 automatically to normal Companion mode after `mdv-sync`, avoiding a QL left on the `BL616 IS HOLDING RESET` startup screen.
- Documents that microSD controller compatibility can vary independently of brand, capacity, speed class, and formatting.
- Suppresses terminal echo during the macOS/Linux remote-keyboard session and discards buffered escape sequences before returning control.

## v0.2.4 - 2026-08-02

- Queues overlay configuration saves in a dedicated BL616 task so slow microSD synchronization cannot block menu input or trap a held Enter key.
- Coalesces repeated option changes while a previous settings write is still running.
- Allows slow microSD allocation and erase pauses during NanoQL Link uploads without treating them as a missing BL616 response on macOS.
- Updates the visible overlay title to `NanoQL v0.2.4`, making stale persistent FPGA installations immediately identifiable.

## v0.2.3 - 2026-08-02

- Saves overlay settings through an atomic `nanoql.ini.tmp` replacement instead of truncating the active configuration in place.
- Preserves a recoverable `nanoql.ini.bak` while replacing the configuration and restores it automatically after an interrupted save.
- Prevents keyboard-layout selection, or another saved overlay option, from losing the selected QL and IPC ROM paths after a microSD write failure or power interruption.
- Keeps the FPGA bitstream unchanged from v0.2.1 and v0.2.2; this release updates the BL616 firmware for both supported board revisions.

## v0.2.2 - 2026-08-02

- Completes the French QL ROM keyboard mapping for punctuation, national characters, brackets, braces, and common programming symbols.
- Makes macOS punctuation handling independent from host key names that may be reported using a US layout.
- Clarifies that the setup assistant's keyboard selector describes the QL ROM layout; the host keyboard layout remains managed by the operating system.
- Adds regression tests for French ROM letters, punctuation, modifiers, and national characters.
- Keeps the FPGA bitstream and BL616 firmware unchanged from v0.2.1; existing v0.2.1 installations only need the updated Python tools.

## v0.2.1 - 2026-08-02

- Stabilizes the remote keyboard on macOS by preserving QL key-matrix presses long enough for the IPC scanner and sequencing modifier transitions safely.
- Reports the exact Python executable that requires macOS Input Monitoring and Accessibility permissions.
- Hides the former green boot-status square after a successful startup while retaining full-screen failure diagnostics.
- Updates the overlay version and packaged FPGA bitstream to v0.2.1.

## v0.2.0 - 2026-07-30

- Loads the 2 KiB 8049 IPC firmware dynamically from microSD instead of embedding it in the FPGA bitstream.
- Adds an OSD selector for standard Sinclair or Hermes IPC firmware.
- Accepts raw `.bin`/`.rom` and Intel HEX IPC files directly from the OSD, with hardware checksum and coverage validation.
- Accepts whitespace-separated hexadecimal IPC dumps such as 8,192-byte CR/LF files containing one byte per line.
- Removes mandatory `QL.rom` and `IPC.rom` filenames; missing selections now lead to a clear `F12` setup screen.
- Repairs a zero map-sector header checksum and restores omitted physical sector-tail patterns while streaming otherwise valid QLAY images accepted by Q-emuLator.
- Expands the Tkinter setup assistant with a guided install page, tool detection, official ROM/tool links, safe FPGA/BL616 sequencing, NanoQL Link checks, USB stress testing, and one-click remote keyboard startup.
- Replaces the oversized README with a concise bilingual project overview and adds a dedicated French/English installation guide.
- Adds native BL616 flashing on Windows, macOS, and Linux through Bouffalo Lab's official Python UART loader, while retaining FlashCube as an optional Windows recovery path.
- Stores every overlay-built folder cartridge as `/NanoQL/Generated/<folder>.mdv`, so users can copy, archive, remount, and retain QDOS writes in a clearly named image.
- Corrects the physical AZERTY `3` key for an English QL ROM by emitting the QL's Shift+2 quote contact; host Shift+3 remains the digit `3`.
- Holds the QL in reset and displays a clear startup diagnostic when the selected IPC image is missing, invalid, or cannot be read.
- Keeps all user-supplied IPC firmware outside the repository and compiled FPGA artifacts.
- Keeps QL-mode video contention active while a Microdrive is selected, restoring realistic VBL-to-VBL CPU headroom for programs such as Game8.
- Adds regression coverage for native VSYNC frame-interrupt latching and 68000 acknowledgement.

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

The v0.1.0 release assets contain compiled BL616 firmware images for both supported board revisions. Its FPGA bitstream was built locally because that version still embedded the user-supplied IPC firmware. User-supplied QL, IPC, QL-SD, and QSound ROM images are not distributed.

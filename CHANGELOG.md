# Changelog

## v0.3.5 - 2026-08-28

- Adds two complete 32 KiB SDRAM video snapshots between the native 50.080 Hz QL raster and independent 720p scanout, publishing a new page only after its full copy and eliminating mixed-page tearing and sprite flicker.
- Gives QL CPU RAM accesses priority over background HDMI snapshot copies, preserving Microdrive Turbo timing while allowing video to keep updating after a cartridge load.
- Extends the SDRAM router and video path to 22-bit word addresses while keeping the dynamic QL ROM and snapshots in documented non-overlapping high-memory regions.
- Adds focused HDL coverage for atomic frame publication, HDMI acknowledgement, interrupted-copy restart, SDRAM ownership, and the original 128 KiB contention boundary.
- Silently checks for a newer GitHub release when the Setup Assistant starts, with no warning or delay requirement when the computer is offline.
- Lets a verified Complete package transactionally update the bilingual Setup Assistant, NanoQL Link, and public helper scripts, restore the previous files on failure, preserve user settings, and restart automatically.

## v0.3.4 - 2026-08-26

- Adds an optional Microdrive Turbo mode that accelerates the virtual tape and CPU together while preserving the validated read cadence across QL, 16 MHz, and 24 MHz operation.
- Lets the Setup Assistant download, verify, extract, and select the latest Complete GitHub release as the first installation or update step.
- Adds a documented `Hello NanoQL` 68000 example with direct `vasmm68k_mot` and NanoQL Link commands for rapid bare-metal development.
- Extends NanoQL Link with non-resetting 68000 register inspection, including D0-D7, A0-A7, USP, SSP, PC, IR, SR, and decoded condition flags; exact halt and resume now preserve the complete CPU state.
- Prevents missed or stuck physical USB keys by preserving short semantic key holds and by reconciling all-released HID reports without disturbing the independent remote keyboard.
- Makes physical USB Caps Lock select the complete shifted QL layer for letters, digits, and punctuation, with Shift selecting the opposite layer and focused AZERTY/QWERTY regression coverage.
- Keeps Advanced MDV synchronization compatible with an active remote keyboard and improves the graphical assistant workflow, progress reporting, saved settings, and NanoQL Link status feedback.

## v0.3.3 - 2026-08-24

- Calibrates QL-mode ZX8301 contention for NanoQL's fx68k-to-SDRAM bridge: the original 32-of-40 DRAM ownership pattern is represented by 20 additional gated chunks because the bridge and physical SDRAM transaction already consume part of each 68008 memory cycle.
- Gives CPU transactions priority over asynchronous HDMI line prefetch in QL mode, preventing physical SDRAM arbitration from charging the emulated video contention a second time; accelerated modes retain bounded video priority.
- Restricts ZX8301 cycle stealing to the original 128 KiB internal DRAM range, leaving ROM, I/O, and expansion RAM uncontended by video fetches.
- Physically validates the resulting frame cadence and screen-bank behavior with Kizuna in the QL/128 KiB profile: the transient squares and magenta underflows disappear, while the fractal-to-greetings transition closely follows the real-hardware recording.
- Moves the QL-SD image selector after the Microdrive controls in the Storage overlay.
- Adds focused HDL coverage for contended internal RAM versus uncontended expansion accesses, plus live `peek` and `watch` commands for non-resetting hardware diagnostics.

## v0.3.2 - 2026-08-23

- Hotfix: maps the QL character-set pound sign to the original dedicated English matrix contact used by JS and standard English ROMs, while retaining the MGF French Shift combination.
- Translates physical USB punctuation against the selected QL ROM table, preserves the QL character set's accented letters, gives USB Caps Lock modern letter/Shift behavior without double-toggling native QL Caps, and enables the numeric keypad independently of Num Lock.
- Keeps release-folder selection exclusively on the Start page, leaves one explicit FPGA-file selector in the FPGA tab, and tells users to press S1 when a NanoQL Link programming command cannot start.
- Stops treating the AZERTY comma/question-mark position as an alphabetic HID key and adds matrix-level regression tests for French `$`, `£`, `?`, and `*`.
- Establishes generated QL Shift/Ctrl contacts for a complete IPC matrix scan before the translated key contact, then applies the full minimum key hold; pound remains QL character code `0x60` rather than ISO-8859-1 `0xA3`.
- Accepts both HID usages emitted by ISO AZERTY keyboards for the physical asterisk key and translates either one through the selected QL ROM keyboard matrix.

## v0.3.1 - 2026-08-21

- Hotfix (2026-08-22): lets the Setup Assistant select one extracted Complete release folder from Start, then automatically fills the revision-matched BL616 `.bin` and FPGA `.fs` fields in their respective tabs while retaining independent advanced selectors.
- Hotfix (2026-08-22): accepts Gowin `.fs` files directly through NanoQL Link by validating and decoding their binary payload and checksum.
- Hotfix (2026-08-22): rejects BL616 firmware, malformed binaries, and bitstreams for another FPGA before any SRAM or persistent-Flash programming begins.
- Programs the FPGA SRAM or persistent configuration Flash directly through the NanoQL BL616 firmware, with JEDEC detection, erase/program/readback verification, diagnostics, and automatic recovery when the persistent core is missing or invalid.
- Speeds up persistent FPGA updates with native 64 KiB block erases and page programming, while preserving the Sipeed firmware and external JTAG route as a recovery option.
- Reorders the graphical setup workflow around the required BL616-first installation, separates normal updates from recovery tools, and accepts precompiled `.bin`/`.fs` release files without requiring Gowin EDA.
- Adds scrollable assistant pages, a compact ten-line log, a graphical progress bar, read-only workflow markers, corrected Continue navigation, and a live bottom status indicator for automatic NanoQL Link port detection.
- Makes `Sharp` use an exact 2x horizontal pixel scale while retaining the corrected QL pixel aspect vertically; `Large` and `Fit` keep centered, overscan-safe alternatives at both 50 Hz and 60 Hz.
- Stores the semantic QL contact and modifiers for each physical USB key until release, preventing Shift ordering, short presses, Backspace, Caps Lock, digits, and punctuation from leaving stale or incorrect matrix contacts.
- Keeps the physical USB keyboard and NanoQL Link remote keyboard as independent input sources, and stabilizes macOS modifier/key identities when the operating system reports different objects on press and release.
- Mirrors Caps Lock on the Tang Nano 20K WS2812 and LED 6, with HDL regression coverage for the LED waveform, keyboard state, video windows, and HDMI mode metadata.

## v0.3.0 - 2026-08-13

- Replaces monitor-dependent `Monitor`, `TV`, and wide geometry with centered `Sharp` (564×384), `Large` (844×576), and `Fit` (990×675) windows. Their approximately 4.4:3 geometry reproduces the QL's non-square pixels without asking the HDMI display to stretch the 1280×720 signal; `Fit` retains an overscan-safe margin so the complete raster remains visible.
- Releases ordinary USB keys before their modifiers when both change in one HID report, preventing shifted keys from leaving an unrelated QL matrix contact stuck.
- Atomically clears the local USB-keyboard matrix when the BL616 receives an all-keys-released HID report, recovering from any missed release without disturbing NanoQL Link's independent remote keyboard.
- Mirrors the QL Caps Lock toggle to the physical USB keyboard's Caps Lock LED through a standard HID output report; as on original QL hardware, Caps Lock affects letters but not digits or punctuation.
- Treats PC AZERTY Caps Lock as a number-row lock during local USB character translation, while retaining the QL IPC's native letter-only Caps Lock semantics; idle snapshots now keep the BL616 LED state and FPGA translation state synchronized.
- Makes the BL616 lock state authoritative and derives the QL IPC Caps Lock pulse from that state, eliminating independent LED, number-row, and letter-lock toggles that could become inverted after a lost event.
- Sends Caps Lock through a dedicated Companion command and a fixed isolated QL matrix pulse, so holding or pressing Shift during the transition cannot turn it into the distinct Shift+Caps IPC code.
- Reorganizes the overlay into System, Storage, Display, and Keyboard sections, fixes the one-pixel selection overflow, dims the QL picture behind a cleaner high-contrast panel, and labels host-keyboard and ROM-keyboard settings unambiguously.
- Adds live 720p50 and 720p60 output profiles at the same 74.25 MHz pixel clock, emitting VIC 19 or VIC 4 in the HDMI AVI InfoFrame.
- Makes the overlay distinguish the local `USB layout` from the `QL ROM layout`, and renames the PC assistant tab to `Remote keyboard`; NanoQL Link keys remain independently character-mapped by the host.
- Converts local USB AZERTY/QWERTY printable keys semantically, including number-row punctuation, French national keys, and common AltGr programming symbols.
- Gives NanoQL Link a direct QL-matrix protocol and independent key state, preventing remote punctuation from being translated again by the USB-keyboard path or releasing a locally held key.
- Reworks the graphical Setup Assistant around beginner-facing actions: temporary SRAM programming, permanent Flash programming, one-click BL616 flashing, remote keyboard, and binary injection. FPGA builds and MDV synchronization now live under Advanced.
- Adds embedded user-prepared Tang Nano 20K illustrations that blink between normal, `UPDATE`, and `S1` states, a larger resizable log area, persistent user settings, and a console-free Windows `.pyw` launcher while retaining the former `.py` command as a compatibility wrapper.
- Adds an immediately switchable and persistent English/French interface catalog, concise keyword-led instructions, and an unambiguous Remote keyboard tab distinct from a physical USB keyboard attached through a hub.

## v0.2.8 - 2026-08-03

- Persists Setup Assistant paths, selected tools, ports, and developer parameters in a per-user cross-platform INI file.
- Adds a Bare-metal assistant tab for verified raw 68000 injection with configurable load, PC, and SSP addresses and one-click QDOS restart.
- Paces the BL616 BootROM's acknowledged 256-byte Flash writes to prevent intermittent USB receive-endpoint saturation.
- Finalizes NanoQL Link uploads with one FatFs close operation instead of a redundant sync-then-close sequence.
- Adds a live-switchable 24 MHz CPU mode while preserving native QL video, IPC, Microdrive, QL-SD, audio, and SDRAM timing in a new 48 MHz system domain.
- Keeps 42 MHz disabled because fx68k requires an 84 MHz phase domain, above the placed GW2AR-18 design's timing limit.
- Recovers MDV synchronization when macOS loses the final microSD commit reply by retrying the commit and validating the installed file by size and CRC32.
- Suppresses local Terminal escape-sequence echo on macOS through the authorized Quartz event tap and preserves real NanoQL Link errors instead of misreporting them as privacy-permission failures.
- Removes Gowin operation 51 from persistent FPGA programming because it can hang with the Sipeed FPGA Partner before programming starts.
- Routes the graphical assistant's persistent Gowin programming through the same `fpga-flash-native` implementation as the CLI, including a second USB Debugger A/1 scan immediately before programming.
- Requires and prefers openFPGALoader v1.1.1 or newer for scripted persistent programming because Gowin CLI operation 8 hangs and Gowin `JTAGLoading` does not support the BL616 `USB Debugger A` cable.
- Maps NanoQL Link keyboard input by the character produced by Windows or macOS, folds accented letters for English QL ROMs, and adds a graphical Stop remote keyboard button.
- Keeps the ZX8302 receive byte stable across the complete status/data handshake and scales the virtual Microdrive cadence with accelerated CPU modes, fixing MDV1 reads at QL, 16 MHz, and 24 MHz.
- Makes Microdrive uploads resilient to slow or interrupted microSD finalization and verifies the installed image by size and CRC32.
- Automates FPGA and BL616 programming on Windows while retaining cross-platform openFPGALoader and Bouffalo Lab tool support.

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

#!/usr/bin/env python3
"""NanoQL desktop setup assistant using only the Python standard library."""

from __future__ import annotations

import os
import platform
import queue
import shutil
import subprocess
import sys
import threading
from pathlib import Path

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
except ImportError as error:
    raise SystemExit(
        "Tkinter is required. On Linux install your distribution's python3-tk package."
    ) from error


REPOSITORY = Path(__file__).resolve().parent.parent
TOOLS = REPOSITORY / "tools"
CREATE_NO_WINDOW = 0x08000000 if platform.system() == "Windows" else 0
BUILD_SCRIPT = "build_sd_rom.tcl"


def find_gowin() -> str:
    command = shutil.which("gw_sh")
    if command:
        return command
    if platform.system() == "Windows":
        roots = (Path("C:/Gowin"), Path("C:/Program Files/Gowin"))
        candidates: list[Path] = []
        for root in roots:
            if root.exists():
                candidates.extend(root.glob("**/IDE/bin/gw_sh.exe"))
        if candidates:
            return str(sorted(candidates, reverse=True)[0])
    return ""


class NanoQLSetup(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("NanoQL Setup Assistant")
        self.geometry("940x720")
        self.minsize(820, 620)
        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.busy_widgets: list[ttk.Button] = []

        self.revision = tk.StringVar(value="3923")
        self.firmware_mode = tk.StringVar(value="nanoql")
        self.rom_path = tk.StringVar()
        self.qsound_rom_path = tk.StringVar()
        self.sd_path = tk.StringVar()
        self.ipc_path = tk.StringVar()
        self.mdv_folder = tk.StringVar()
        self.mdv_name = tk.StringVar(value="NANOQL")
        self.link_port = tk.StringVar()
        self.gowin_path = tk.StringVar(value=find_gowin())
        self.loader_path = tk.StringVar(value=shutil.which("openFPGALoader") or "")
        self.bitstream_path = tk.StringVar(
            value=str(REPOSITORY / "impl" / "pnr" / "NanoQL_sd_rom.fs")
        )
        self.status = tk.StringVar(value="Ready")

        self._build_ui()
        self.after(100, self._poll_events)

    def _build_ui(self) -> None:
        style = ttk.Style(self)
        style.configure("Title.TLabel", font=("Segoe UI", 16, "bold"))
        style.configure("Section.TLabel", font=("Segoe UI", 10, "bold"))

        header = ttk.Frame(self, padding=(16, 12))
        header.pack(fill="x")
        ttk.Label(header, text="NanoQL Setup Assistant", style="Title.TLabel").pack(
            side="left"
        )
        ttk.Label(header, textvariable=self.status).pack(side="right")

        notebook = ttk.Notebook(self)
        notebook.pack(fill="both", expand=True, padx=12)
        firmware_tab = ttk.Frame(notebook, padding=16)
        storage_tab = ttk.Frame(notebook, padding=16)
        fpga_tab = ttk.Frame(notebook, padding=16)
        microdrive_tab = ttk.Frame(notebook, padding=16)
        notebook.add(firmware_tab, text="1. BL616 Companion")
        notebook.add(storage_tab, text="2. ROM and microSD")
        notebook.add(fpga_tab, text="3. FPGA")
        notebook.add(microdrive_tab, text="4. Developer MDV sync")

        self._build_firmware_tab(firmware_tab)
        self._build_storage_tab(storage_tab)
        self._build_fpga_tab(fpga_tab)
        self._build_microdrive_tab(microdrive_tab)

        log_frame = ttk.LabelFrame(self, text="Log", padding=8)
        log_frame.pack(fill="both", expand=False, padx=12, pady=12)
        self.log = tk.Text(
            log_frame,
            height=11,
            wrap="word",
            state="disabled",
            font=("Consolas", 9),
        )
        scrollbar = ttk.Scrollbar(log_frame, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=scrollbar.set)
        self.log.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self._append_log(f"Repository: {REPOSITORY}\n")

    def _build_firmware_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(1, weight=1)
        ttk.Label(parent, text="Board revision", style="Section.TLabel").grid(
            row=0, column=0, sticky="w", pady=(0, 8)
        )
        revision = ttk.Combobox(
            parent, textvariable=self.revision, values=("3921", "3923"), state="readonly", width=12
        )
        revision.grid(row=0, column=1, sticky="w", pady=(0, 8))

        ttk.Label(parent, text="Firmware mode", style="Section.TLabel").grid(
            row=1, column=0, sticky="nw", pady=8
        )
        modes = ttk.Frame(parent)
        modes.grid(row=1, column=1, sticky="w", pady=8)
        ttk.Radiobutton(
            modes,
            text="NanoQL: normal operation and NanoQL Link",
            variable=self.firmware_mode,
            value="nanoql",
        ).pack(anchor="w")
        ttk.Radiobutton(
            modes,
            text="Original: Sipeed FPGA Partner and Companion",
            variable=self.firmware_mode,
            value="original",
        ).pack(anchor="w")

        actions = ttk.Frame(parent)
        actions.grid(row=2, column=0, columnspan=2, sticky="w", pady=(18, 8))
        self._button(actions, "Prepare files", self.prepare_firmware).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Prepare and open FlashCube", self.prepare_and_open_flashcube).pack(
            side="left"
        )

        ttk.Label(
            parent,
            text=(
                "Hold UPDATE while connecting USB, release it, select the serial port "
                "in FlashCube, then choose the .ini file shown in the log."
            ),
            wraplength=760,
        ).grid(row=3, column=0, columnspan=2, sticky="w", pady=(12, 0))

    def _build_storage_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(1, weight=1)
        self._path_row(parent, 0, "48/64 KiB QL ROM", self.rom_path, self._browse_rom)
        self._path_row(parent, 1, "Optional 8 KiB QSound ROM", self.qsound_rom_path, self._browse_qsound_rom)
        self._path_row(parent, 2, "microSD root", self.sd_path, self._browse_sd)
        self._path_row(parent, 3, "Sinclair IPC firmware (Intel HEX)", self.ipc_path, self._browse_ipc)

        actions = ttk.Frame(parent)
        actions.grid(row=4, column=0, columnspan=3, sticky="w", pady=(18, 8))
        self._button(actions, "Prepare microSD", self.prepare_sd).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Convert IPC firmware", self.prepare_ipc).pack(side="left")

        ttk.Label(
            parent,
            text=(
                "The ROM remains private: it is validated and copied as QL.rom. "
                "nanoql.ini and the NanoQL/Drive1 user-file folder are also created."
            ),
            wraplength=760,
        ).grid(row=5, column=0, columnspan=3, sticky="w", pady=(12, 0))

    def _build_fpga_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(1, weight=1)
        self._path_row(parent, 0, "Gowin gw_sh", self.gowin_path, self._browse_gowin)
        self._path_row(
            parent, 1, "openFPGALoader", self.loader_path, self._browse_loader
        )

        ttk.Label(parent, text="Bitstream", style="Section.TLabel").grid(
            row=2, column=0, sticky="w", pady=8
        )
        ttk.Entry(parent, textvariable=self.bitstream_path, state="readonly").grid(
            row=2, column=1, columnspan=2, sticky="ew", pady=8
        )

        actions = ttk.Frame(parent)
        actions.grid(row=3, column=0, columnspan=3, sticky="w", pady=(18, 8))
        self._button(actions, "Build", self.build_fpga).pack(side="left", padx=(0, 8))
        self._button(actions, "Program SRAM", lambda: self.program_fpga(False)).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Program Flash", lambda: self.program_fpga(True)).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Prepare all and build", self.prepare_and_build).pack(
            side="left"
        )

        ttk.Label(
            parent,
            text=(
                "SRAM is temporary and is lost at power-off. Flash is persistent and lets "
                "the normal BL616 firmware start Companion without a computer."
            ),
            wraplength=760,
        ).grid(row=4, column=0, columnspan=3, sticky="w", pady=(12, 0))

    def _build_microdrive_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(1, weight=1)
        self._path_row(
            parent, 0, "PC folder synchronized as MDV1", self.mdv_folder,
            self._browse_mdv_folder,
        )
        ttk.Label(parent, text="Medium name", style="Section.TLabel").grid(
            row=1, column=0, sticky="w", pady=8
        )
        ttk.Entry(parent, textvariable=self.mdv_name, width=16).grid(
            row=1, column=1, sticky="w", padx=8, pady=8
        )
        ttk.Label(parent, text="NanoQL Link port", style="Section.TLabel").grid(
            row=2, column=0, sticky="w", pady=8
        )
        ttk.Entry(parent, textvariable=self.link_port, width=16).grid(
            row=2, column=1, sticky="w", padx=8, pady=8
        )
        self._button(parent, "Synchronize and restart QL", self.sync_microdrive).grid(
            row=3, column=0, columnspan=3, sticky="w", pady=(18, 8)
        )
        ttk.Label(
            parent,
            text=(
                "Optional developer workflow: start NanoQL, briefly press S1 to expose "
                "NanoQL Link, then synchronize. Normal users can instead copy folders to "
                "NanoQL/Microdrives on the microSD and select Build MDV1 from: in the F12 "
                "overlay."
            ),
            wraplength=760,
        ).grid(row=4, column=0, columnspan=3, sticky="w", pady=(12, 0))

    def _path_row(
        self,
        parent: ttk.Frame,
        row: int,
        label: str,
        variable: tk.StringVar,
        browse,
    ) -> None:
        ttk.Label(parent, text=label, style="Section.TLabel").grid(
            row=row, column=0, sticky="w", pady=8
        )
        ttk.Entry(parent, textvariable=variable).grid(
            row=row, column=1, sticky="ew", padx=8, pady=8
        )
        ttk.Button(parent, text="Browse...", command=browse).grid(
            row=row, column=2, pady=8
        )

    def _button(self, parent: ttk.Frame, text: str, command) -> ttk.Button:
        button = ttk.Button(parent, text=text, command=command)
        self.busy_widgets.append(button)
        return button

    def _browse_rom(self) -> None:
        path = filedialog.askopenfilename(title="Select the QL ROM")
        if path:
            self.rom_path.set(path)

    def _browse_sd(self) -> None:
        path = filedialog.askdirectory(title="Select the microSD root")
        if path:
            self.sd_path.set(path)

    def _browse_qsound_rom(self) -> None:
        path = filedialog.askopenfilename(
            title="Select an 8 KiB QSound ROM",
            filetypes=(("ROM images", "*.rom *.bin"), ("All files", "*")),
        )
        if path:
            self.qsound_rom_path.set(path)

    def _browse_ipc(self) -> None:
        path = filedialog.askopenfilename(
            title="Select ipc8049.hex",
            filetypes=(("Intel HEX", "*.hex"), ("All files", "*")),
        )
        if path:
            self.ipc_path.set(path)

    def _browse_mdv_folder(self) -> None:
        path = filedialog.askdirectory(title="Select the folder exposed as MDV1")
        if path:
            self.mdv_folder.set(path)

    def _browse_gowin(self) -> None:
        path = filedialog.askopenfilename(title="Select gw_sh")
        if path:
            self.gowin_path.set(path)

    def _browse_loader(self) -> None:
        path = filedialog.askopenfilename(title="Select openFPGALoader")
        if path:
            self.loader_path.set(path)

    def _selected_config(self) -> Path:
        if self.firmware_mode.get() == "nanoql":
            filename = f"2_NANOQL_{self.revision.get()}.ini"
        else:
            filename = f"1_ORIGINAL_{self.revision.get()}_partner.ini"
        return (
            REPOSITORY
            / "private"
            / "bl616"
            / "flash-package"
            / filename
        )

    def prepare_firmware(self, callback=None) -> None:
        command = [
            sys.executable,
            str(TOOLS / "prepare_bl616_firmware.py"),
            "--revision",
            self.revision.get(),
        ]
        self._run(command, "Preparing BL616 firmware", callback)

    def prepare_and_open_flashcube(self) -> None:
        self.prepare_firmware(self._open_flashcube)

    def _open_flashcube(self) -> None:
        config = self._selected_config()
        candidates = list((REPOSITORY / "private" / "bl616" / "flashcube").rglob("BLFlashCube.exe"))
        if platform.system() != "Windows" or not candidates:
            messagebox.showinfo(
                "Firmware ready",
                f"Configuration prepared:\n{config}\n\nFlashCube is available on Windows only.",
            )
            return
        self.clipboard_clear()
        self.clipboard_append(str(config))
        self._append_log(f"Configuration to select (copied): {config}\n")
        subprocess.Popen([str(candidates[0])], cwd=config.parent)
        messagebox.showinfo(
            "FlashCube",
            f"Select this configuration in FlashCube:\n\n{config}\n\nThe path has been copied.",
        )

    def prepare_sd(self) -> None:
        if not self.rom_path.get() or not self.sd_path.get():
            messagebox.showerror("Missing fields", "Select the ROM and microSD root.")
            return
        command = [
            sys.executable, str(TOOLS / "prepare_sd_card.py"),
            self.rom_path.get(), self.sd_path.get(),
        ]
        if self.qsound_rom_path.get():
            command.extend(["--qsound-rom", self.qsound_rom_path.get()])
        if self.mdv_folder.get():
            command.extend([
                "--mdv-folder", self.mdv_folder.get(),
                "--mdv-name", self.mdv_name.get(),
            ])
        self._run(command, "Preparing microSD")

    def sync_microdrive(self) -> None:
        if not self.mdv_folder.get():
            messagebox.showerror("Missing folder", "Select the PC folder exposed as MDV1.")
            return
        command = [sys.executable, str(TOOLS / "nanoql_link.py")]
        if self.link_port.get().strip():
            command.extend(["--port", self.link_port.get().strip()])
        command.extend([
            "mdv-sync", self.mdv_folder.get(), "--name", self.mdv_name.get()
        ])
        self._run(command, "Synchronizing MDV1")

    def prepare_ipc(self) -> None:
        if not self.ipc_path.get():
            messagebox.showerror(
                "Missing field",
                "Select the standard Sinclair ipc8049.hex firmware.",
            )
            return
        self._run(
            [sys.executable, str(TOOLS / "prepare_ql_ipc_rom.py"), self.ipc_path.get()],
            "Converting IPC firmware",
        )

    def build_fpga(self) -> None:
        gowin = self.gowin_path.get()
        if not gowin or not Path(gowin).is_file():
            messagebox.showerror("Gowin not found", "Select a valid gw_sh executable.")
            return
        ipc = REPOSITORY / "src" / "ipc" / "ql_ipc_rom.hex"
        if not ipc.is_file():
            messagebox.showerror("Missing IPC firmware", "Convert the IPC firmware first.")
            return
        self._run([gowin, BUILD_SCRIPT], "Building NanoQL")

    def prepare_and_build(self) -> None:
        gowin = self.gowin_path.get()
        if not gowin or not Path(gowin).is_file():
            messagebox.showerror("Gowin not found", "Select a valid gw_sh executable.")
            return
        if not self.rom_path.get() or not self.sd_path.get():
            messagebox.showerror("Missing fields", "Select the ROM and microSD root.")
            return
        ipc_output = REPOSITORY / "src" / "ipc" / "ql_ipc_rom.hex"
        if not self.ipc_path.get() and not ipc_output.is_file():
            messagebox.showerror(
                "Missing IPC firmware",
                "Select the standard Sinclair ipc8049.hex firmware on first use.",
            )
            return

        commands: list[list[str]] = []
        if self.ipc_path.get():
            commands.append(
                [sys.executable, str(TOOLS / "prepare_ql_ipc_rom.py"), self.ipc_path.get()]
            )
        prepare_sd_command = [
            sys.executable,
            str(TOOLS / "prepare_sd_card.py"),
            self.rom_path.get(),
            self.sd_path.get(),
        ]
        if self.qsound_rom_path.get():
            prepare_sd_command.extend([
                "--qsound-rom", self.qsound_rom_path.get()
            ])
        if self.mdv_folder.get():
            prepare_sd_command.extend([
                "--mdv-folder", self.mdv_folder.get(),
                "--mdv-name", self.mdv_name.get(),
            ])
        commands.append(prepare_sd_command)
        commands.append([gowin, "build_sd_rom.tcl"])
        self._run_commands(commands, "Preparing microSD and building")

    def program_fpga(self, persistent: bool) -> None:
        loader = self.loader_path.get()
        bitstream = Path(self.bitstream_path.get())
        if not loader or not Path(loader).is_file():
            messagebox.showerror(
                "openFPGALoader not found", "Select a valid openFPGALoader executable."
            )
            return
        if not bitstream.is_file():
            messagebox.showerror("Missing bitstream", "Build this variant first.")
            return
        command = [loader, "-b", "tangnano20k"]
        if persistent:
            command.append("-f")
        command.append(str(bitstream))
        self._run(command, "Programming Flash" if persistent else "Programming SRAM")

    def _run(self, command: list[str], title: str, callback=None) -> None:
        self._run_commands([command], title, callback)

    def _run_commands(
        self, commands: list[list[str]], title: str, callback=None
    ) -> None:
        self.status.set(title)
        for widget in self.busy_widgets:
            widget.configure(state="disabled")

        def worker() -> None:
            try:
                for command in commands:
                    self.events.put(("log", f"\n> {' '.join(command)}\n"))
                    process = subprocess.Popen(
                        command,
                        cwd=REPOSITORY,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        encoding="utf-8",
                        errors="replace",
                        creationflags=CREATE_NO_WINDOW,
                    )
                    assert process.stdout is not None
                    for line in process.stdout:
                        self.events.put(("log", line))
                    code = process.wait()
                    if code:
                        raise RuntimeError(f"Command failed with exit code {code}")
                self.events.put(("done", (title, callback)))
            except Exception as error:
                self.events.put(("error", (title, str(error))))

        threading.Thread(target=worker, daemon=True).start()

    def _poll_events(self) -> None:
        try:
            while True:
                event, payload = self.events.get_nowait()
                if event == "log":
                    self._append_log(str(payload))
                elif event == "done":
                    title, callback = payload
                    self._finish_busy("Complete")
                    self._append_log(f"{title}: OK\n")
                    if callback:
                        callback()
                elif event == "error":
                    title, error = payload
                    self._finish_busy("Error")
                    self._append_log(f"{title}: ERROR: {error}\n")
                    messagebox.showerror(title, error)
        except queue.Empty:
            pass
        self.after(100, self._poll_events)

    def _finish_busy(self, status: str) -> None:
        self.status.set(status)
        for widget in self.busy_widgets:
            widget.configure(state="normal")

    def _append_log(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", text)
        self.log.see("end")
        self.log.configure(state="disabled")


def main() -> int:
    app = NanoQLSetup()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

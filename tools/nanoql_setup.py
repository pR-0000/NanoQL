#!/usr/bin/env python3
"""NanoQL desktop setup assistant using only the Python standard library."""

from __future__ import annotations

import importlib.util
import platform
import queue
import shutil
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path


def install_python_packages(*packages: str) -> None:
    command = [sys.executable, "-m", "pip", "install", *packages]
    try:
        subprocess.check_call(command)
    except subprocess.CalledProcessError:
        if platform.system() != "Darwin" or "--break-system-packages" in command:
            raise
        subprocess.check_call([
            sys.executable,
            "-m",
            "pip",
            "install",
            "--user",
            "--break-system-packages",
            *packages,
        ])


try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
except ImportError as error:
    raise SystemExit(
        "Tkinter is required. On Linux install your distribution's python3-tk package."
    ) from error

try:
    from serial.tools import list_ports
except ImportError:
    install_python_packages("pyserial")
    from serial.tools import list_ports


REPOSITORY = Path(__file__).resolve().parent.parent
TOOLS = REPOSITORY / "tools"
CREATE_NO_WINDOW = 0x08000000 if platform.system() == "Windows" else 0
BUILD_SCRIPT = "build_sd_rom.tcl"
OPENFPGA_INSTALL_URL = (
    "https://trabucayre.github.io/openFPGALoader/guide/install.html"
)
QL_ROM_URL = "https://sinclairql.net/djw/qlrom/index.html"
IPC_ROM_URL = "https://github.com/MiSTer-devel/QL_MiSTer/tree/master/rtl"
HERMES_URL = "http://firshman.co.uk/ql/hermes.htm"
PYTHON_URL = "https://www.python.org/downloads/"
HOMEBREW_URL = "https://brew.sh/"
AUTO_PORT = "Automatic detection"
SELECT_PORT = "Select a serial port"


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


def find_openfpgaloader() -> str:
    command = shutil.which("openFPGALoader") or shutil.which("openfpgaloader")
    if command:
        return command
    candidates = (
        Path("/opt/homebrew/bin/openFPGALoader"),
        Path("/usr/local/bin/openFPGALoader"),
        Path("C:/msys64/ucrt64/bin/openFPGALoader.exe"),
        Path("C:/msys64/mingw64/bin/openFPGALoader.exe"),
        Path("C:/Program Files/openFPGALoader/bin/openFPGALoader.exe"),
        Path("C:/Program Files/openFPGALoader/openFPGALoader.exe"),
        Path.home() / "scoop/apps/openfpgaloader/current/openFPGALoader.exe",
    )
    return next((str(path) for path in candidates if path.is_file()), "")


def find_homebrew() -> str:
    command = shutil.which("brew")
    if command:
        return command
    return next(
        (str(path) for path in (
            Path("/opt/homebrew/bin/brew"),
            Path("/usr/local/bin/brew"),
        ) if path.is_file()),
        "",
    )


def find_precompiled_bitstream() -> str:
    preferred = REPOSITORY / "impl" / "pnr" / "NanoQL_sd_rom.fs"
    if preferred.is_file():
        return str(preferred)
    candidates: list[Path] = []
    for folder in (REPOSITORY, Path.cwd(), Path.home() / "Downloads"):
        if folder.is_dir():
            candidates.extend(folder.glob("NanoQL*-FPGA.fs"))
            candidates.extend(folder.glob("NanoQL*/NanoQL*-FPGA.fs"))
    if candidates:
        return str(max(candidates, key=lambda path: path.stat().st_mtime))
    return str(preferred)


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
        self.bl616_port = tk.StringVar(value=SELECT_PORT)
        self.rom_path = tk.StringVar()
        self.qsound_rom_path = tk.StringVar()
        self.sd_path = tk.StringVar()
        self.ipc_path = tk.StringVar()
        self.mdv_folder = tk.StringVar()
        self.mdv_name = tk.StringVar(value="NANOQL")
        self.link_port = tk.StringVar(value=AUTO_PORT)
        self.ql_layout = tk.StringVar(value="auto")
        self.gowin_path = tk.StringVar(value=find_gowin())
        self.loader_path = tk.StringVar(value=find_openfpgaloader())
        self.bitstream_path = tk.StringVar(value=find_precompiled_bitstream())
        self.port_devices: dict[str, str] = {}
        self.status = tk.StringVar(value="Ready")

        self._build_ui()
        self.refresh_ports()
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
        quick_tab = ttk.Frame(notebook, padding=16)
        link_tab = ttk.Frame(notebook, padding=16)
        firmware_tab = ttk.Frame(notebook, padding=16)
        storage_tab = ttk.Frame(notebook, padding=16)
        fpga_tab = ttk.Frame(notebook, padding=16)
        microdrive_tab = ttk.Frame(notebook, padding=16)
        notebook.add(quick_tab, text="Start here")
        notebook.add(storage_tab, text="1. ROMs and microSD")
        notebook.add(fpga_tab, text="2. FPGA")
        notebook.add(firmware_tab, text="3. BL616")
        notebook.add(link_tab, text="4. USB keyboard")
        notebook.add(microdrive_tab, text="Advanced MDV sync")

        self._build_quick_tab(quick_tab)
        self._build_firmware_tab(firmware_tab)
        self._build_storage_tab(storage_tab)
        self._build_fpga_tab(fpga_tab)
        self._build_link_tab(link_tab)
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
        self.after(200, self.check_requirements)

    def _build_quick_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        ttk.Label(
            parent,
            text="Install NanoQL in three steps",
            style="Title.TLabel",
        ).grid(row=0, column=0, sticky="w", pady=(0, 14))
        ttk.Label(
            parent,
            text=(
                "1. Prepare the microSD with one QL ROM and one IPC firmware.\n"
                "2. While the board still has its original BL616 firmware, program "
                "NanoQL permanently into the FPGA.\n"
                "3. Install the NanoQL BL616 firmware last. This enables the USB "
                "keyboard, microSD services, overlay, and NanoQL Link."
            ),
            wraplength=780,
            justify="left",
        ).grid(row=1, column=0, sticky="w")

        requirements = ttk.LabelFrame(parent, text="Requirements", padding=12)
        requirements.grid(row=2, column=0, sticky="ew", pady=(18, 10))
        requirements.columnconfigure(1, weight=1)
        self.requirements_text = tk.StringVar()
        ttk.Label(
            requirements,
            textvariable=self.requirements_text,
            justify="left",
            wraplength=650,
        ).grid(row=0, column=0, columnspan=3, sticky="w")
        actions = ttk.Frame(requirements)
        actions.grid(row=1, column=0, columnspan=3, sticky="w", pady=(12, 0))
        self._button(actions, "Check again", self.check_requirements).pack(
            side="left", padx=(0, 8)
        )
        ttk.Button(
            actions,
            text="Install openFPGALoader",
            command=self.install_openfpgaloader,
        ).pack(side="left", padx=(0, 8))
        ttk.Button(
            actions,
            text="Install Python",
            command=lambda: self._open_url(PYTHON_URL),
        ).pack(side="left", padx=(0, 8))
        ttk.Button(
            actions,
            text="Install BL616 tool",
            command=self.install_bl616_tool,
        ).pack(side="left")

        sources = ttk.LabelFrame(parent, text="ROM sources", padding=12)
        sources.grid(row=3, column=0, sticky="ew", pady=10)
        ttk.Label(
            sources,
            text=(
                "NanoQL does not redistribute Sinclair or third-party ROMs. Obtain "
                "files legally, then select them in the next tab."
            ),
            wraplength=760,
        ).pack(anchor="w")
        links = ttk.Frame(sources)
        links.pack(anchor="w", pady=(10, 0))
        ttk.Button(
            links, text="QL ROM archive", command=lambda: self._open_url(QL_ROM_URL)
        ).pack(side="left", padx=(0, 8))
        ttk.Button(
            links, text="Standard IPC source", command=lambda: self._open_url(IPC_ROM_URL)
        ).pack(side="left", padx=(0, 8))
        ttk.Button(
            links, text="Hermes IPC", command=lambda: self._open_url(HERMES_URL)
        ).pack(side="left")

        ttk.Label(
            parent,
            text=(
                "Important: after installing the NanoQL BL616 firmware, standard JTAG "
                "is no longer exposed. To update the persistent FPGA core later, use "
                "NanoQL Link's native flash command or temporarily restore the ORIGINAL "
                "BL616 profile."
            ),
            wraplength=780,
        ).grid(row=4, column=0, sticky="w", pady=(12, 0))

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

        ttk.Label(parent, text="BL616 bootloader port", style="Section.TLabel").grid(
            row=2, column=0, sticky="w", pady=8
        )
        self.bl616_port_combo = ttk.Combobox(
            parent, textvariable=self.bl616_port, state="readonly", width=62
        )
        self.bl616_port_combo.grid(row=2, column=1, sticky="ew", pady=8)
        ttk.Button(parent, text="Refresh", command=self.refresh_ports).grid(
            row=2, column=2, padx=(8, 0), pady=8
        )

        actions = ttk.Frame(parent)
        actions.grid(row=3, column=0, columnspan=2, sticky="w", pady=(18, 8))
        self._button(actions, "Prepare files", self.prepare_firmware).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Prepare and open FlashCube", self.prepare_and_open_flashcube).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Flash selected firmware", self.flash_bl616).pack(
            side="left"
        )

        ttk.Label(
            parent,
            text=(
                "Do this only after persistent FPGA programming. Hold UPDATE while "
                "connecting USB, release it, and enter the new bootloader serial port. "
                "The native button uses Bouffalo Lab's Python tool on Windows, macOS, "
                "and Linux. FlashCube remains available as a Windows fallback."
            ),
            wraplength=760,
        ).grid(row=4, column=0, columnspan=2, sticky="w", pady=(12, 0))

    def _build_storage_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(1, weight=1)
        self._path_row(parent, 0, "microSD root", self.sd_path, self._browse_sd)
        self._path_row(parent, 1, "48/64 KiB QL ROM", self.rom_path, self._browse_rom)
        self._path_row(
            parent, 2, "IPC firmware: original OR Hermes",
            self.ipc_path, self._browse_ipc,
        )
        self._path_row(parent, 3, "Optional 8 KiB QSound ROM", self.qsound_rom_path, self._browse_qsound_rom)

        actions = ttk.Frame(parent)
        actions.grid(row=4, column=0, columnspan=3, sticky="w", pady=(18, 8))
        self._button(actions, "Prepare microSD", self.prepare_sd).pack(
            side="left", padx=(0, 8)
        )

        ttk.Label(
            parent,
            text=(
                "The selected files are validated and copied to the card. These "
                "convenient names are not mandatory: files copied manually can be "
                "selected later from the F12 overlay."
            ),
            wraplength=760,
        ).grid(row=5, column=0, columnspan=3, sticky="w", pady=(12, 0))

    def _build_fpga_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(1, weight=1)
        ttk.Label(parent, text="Bitstream", style="Section.TLabel").grid(
            row=0, column=0, sticky="w", pady=8
        )
        ttk.Entry(parent, textvariable=self.bitstream_path).grid(
            row=0, column=1, sticky="ew", padx=8, pady=8
        )
        ttk.Button(parent, text="Browse...", command=self._browse_bitstream).grid(
            row=0, column=2, pady=8
        )
        self._path_row(
            parent, 1, "openFPGALoader", self.loader_path, self._browse_loader
        )
        self._path_row(
            parent, 2, "Optional Gowin compiler", self.gowin_path, self._browse_gowin
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
                "Program Flash before replacing the original BL616 firmware. SRAM is "
                "temporary and lost at power-off; Flash is persistent. Release users "
                "should select NanoQL-*-FPGA.fs and do not need to click Build."
            ),
            wraplength=760,
        ).grid(row=4, column=0, columnspan=3, sticky="w", pady=(12, 0))

    def _build_link_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(1, weight=1)
        ttk.Label(parent, text="NanoQL Link port", style="Section.TLabel").grid(
            row=0, column=0, sticky="w", pady=8
        )
        self.link_port_combo = ttk.Combobox(
            parent, textvariable=self.link_port, state="readonly", width=62
        )
        self.link_port_combo.grid(row=0, column=1, sticky="ew", padx=8, pady=8)
        ttk.Button(parent, text="Refresh", command=self.refresh_ports).grid(
            row=0, column=2, pady=8
        )
        ttk.Label(parent, text="QL keyboard layout", style="Section.TLabel").grid(
            row=1, column=0, sticky="w", pady=8
        )
        ttk.Combobox(
            parent,
            textvariable=self.ql_layout,
            values=("auto", "fr", "uk"),
            state="readonly",
            width=15,
        ).grid(row=1, column=1, sticky="w", padx=8, pady=8)
        actions = ttk.Frame(parent)
        actions.grid(row=2, column=0, columnspan=3, sticky="w", pady=(18, 8))
        self._button(actions, "Check connection", self.link_status).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Start remote keyboard", self.start_remote_keyboard).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "30 s USB test", self.link_stress).pack(side="left")
        ttk.Label(
            parent,
            text=(
                "Connect NanoQL to the computer with a USB data cable, let the FPGA "
                "start, then briefly press S1. Keep Automatic detection selected or "
                "choose the NanoQL Link port after clicking Refresh. "
                "Remote keyboard mode is currently available on Windows; "
                "press F6 to return control to this assistant."
            ),
            wraplength=760,
        ).grid(row=3, column=0, columnspan=3, sticky="w", pady=(12, 0))

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
        self.mdv_port_combo = ttk.Combobox(
            parent, textvariable=self.link_port, state="readonly", width=62
        )
        self.mdv_port_combo.grid(row=2, column=1, sticky="ew", padx=8, pady=8)
        ttk.Button(parent, text="Refresh", command=self.refresh_ports).grid(
            row=2, column=2, pady=8
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
            title="Select the primary IPC firmware",
            filetypes=(
                ("IPC firmware", "*.hex *.rom *.bin"),
                ("All files", "*"),
            ),
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

    def _browse_bitstream(self) -> None:
        path = filedialog.askopenfilename(
            title="Select a precompiled NanoQL FPGA bitstream",
            filetypes=(
                ("Gowin bitstreams", "*.fs *.bin"),
                ("All files", "*"),
            ),
        )
        if path:
            self.bitstream_path.set(path)

    def _open_url(self, url: str) -> None:
        webbrowser.open(url)

    def refresh_ports(self) -> None:
        selected_devices = {
            "link": self._selected_port(self.link_port, allow_auto=True),
            "bl616": self._selected_port(self.bl616_port, allow_auto=False),
        }
        ports = sorted(
            list_ports.comports(),
            key=lambda port: (
                not any(word in (port.description or "").lower()
                        for word in ("nanoql", "bouffalo", "usb", "serial")),
                port.device.lower(),
            ),
        )
        self.port_devices = {}
        labels: list[str] = []
        for port in ports:
            name = port.name or Path(port.device).name
            description = port.description or "Serial port"
            label = f"{name} | {port.device} | {description}"
            self.port_devices[label] = port.device
            labels.append(label)

        link_values = (AUTO_PORT, *labels)
        bl616_values = (SELECT_PORT, *labels)
        self.link_port_combo.configure(values=link_values)
        self.mdv_port_combo.configure(values=link_values)
        self.bl616_port_combo.configure(values=bl616_values)

        self.link_port.set(next(
            (label for label, device in self.port_devices.items()
             if device == selected_devices["link"]),
            AUTO_PORT,
        ))
        self.bl616_port.set(next(
            (label for label, device in self.port_devices.items()
             if device == selected_devices["bl616"]),
            SELECT_PORT,
        ))
        self._append_log(
            f"Serial ports refreshed: {len(labels)} detected.\n"
        )

    def _selected_port(self, variable: tk.StringVar, allow_auto: bool) -> str:
        value = variable.get().strip()
        if not value or value == SELECT_PORT or (allow_auto and value == AUTO_PORT):
            return ""
        return self.port_devices.get(value, value)

    def install_openfpgaloader(self) -> None:
        if find_openfpgaloader():
            messagebox.showinfo("openFPGALoader", "openFPGALoader is already installed.")
            self.check_requirements()
            return
        if platform.system() == "Darwin":
            brew = find_homebrew()
            if not brew:
                messagebox.showinfo(
                    "Homebrew required",
                    "Install Homebrew first, then click Install openFPGALoader again.",
                )
                self._open_url(HOMEBREW_URL)
                return
            self._run(
                [brew, "install", "openfpgaloader"],
                "Installing openFPGALoader",
                self.check_requirements,
            )
            return
        self._open_url(OPENFPGA_INSTALL_URL)

    def install_bl616_tool(self) -> None:
        self._run(
            [
                sys.executable,
                str(TOOLS / "prepare_bl616_firmware.py"),
                "--install-tools",
            ],
            "Installing the BL616 flashing tool",
            self.check_requirements,
        )

    def check_requirements(self) -> None:
        loader = find_openfpgaloader()
        if loader:
            self.loader_path.set(loader)
        system = platform.system()
        python_state = f"Python {platform.python_version()}: ready"
        loader_state = (
            f"openFPGALoader: {loader}" if loader else "openFPGALoader: not found"
        )
        flash_state = (
            "BL616 tool: "
            + ("installed" if importlib.util.find_spec("bflb_mcu_tool") else "not installed")
            + "; native UART flashing is supported on Windows, macOS, and Linux"
        )
        self.requirements_text.set(
            f"Operating system: {system}\n{python_state}\n{loader_state}\n{flash_state}"
        )

    def _link_command(self, command: str) -> list[str]:
        result = [sys.executable, str(TOOLS / "nanoql_link.py")]
        port = self._selected_port(self.link_port, allow_auto=True)
        if port:
            result.extend(["--port", port])
        result.extend(["--ql-layout", self.ql_layout.get(), command])
        return result

    def link_status(self) -> None:
        self._run(self._link_command("status"), "Checking NanoQL Link")

    def start_remote_keyboard(self) -> None:
        if platform.system() != "Windows":
            messagebox.showinfo(
                "Remote keyboard",
                "The low-latency remote keyboard is currently available on Windows only.",
            )
            return
        self._run(self._link_command("keyboard"), "Remote keyboard active; press F6 to stop")

    def link_stress(self) -> None:
        self._run(self._link_command("link-stress"), "Testing NanoQL Link USB")

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

    def flash_bl616(self) -> None:
        port = self._selected_port(self.bl616_port, allow_auto=False)
        if not port:
            messagebox.showerror(
                "Missing port",
                "Enter the serial port that appears while UPDATE boot mode is active.",
            )
            return
        if not messagebox.askyesno(
            "Program BL616",
            "This replaces the selected BL616 firmware profile. Continue?",
        ):
            return
        command = [
            sys.executable,
            str(TOOLS / "prepare_bl616_firmware.py"),
            "--revision",
            self.revision.get(),
            "--profile",
            self.firmware_mode.get(),
            "--flash",
            "--port",
            port,
            "--baudrate",
            "230400" if platform.system() == "Darwin" else "2000000",
            "--yes",
        ]
        self._run(command, "Programming BL616 firmware")

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
        if self.ipc_path.get():
            command.extend(["--ipc-rom", self.ipc_path.get()])
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
        port = self._selected_port(self.link_port, allow_auto=True)
        if port:
            command.extend(["--port", port])
        command.extend([
            "mdv-sync", self.mdv_folder.get(), "--name", self.mdv_name.get()
        ])
        self._run(command, "Synchronizing MDV1")

    def build_fpga(self) -> None:
        gowin = self.gowin_path.get()
        if not gowin or not Path(gowin).is_file():
            messagebox.showerror("Gowin not found", "Select a valid gw_sh executable.")
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
        ipc_output = Path(self.sd_path.get()) / "IPC.rom"
        if not self.ipc_path.get() and not ipc_output.is_file():
            messagebox.showerror(
                "Missing IPC firmware",
                "Select a standard or Hermes IPC firmware on first use.",
            )
            return

        commands: list[list[str]] = []
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
        if self.ipc_path.get():
            prepare_sd_command.extend(["--ipc-rom", self.ipc_path.get()])
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
            messagebox.showerror(
                "Missing bitstream",
                "The selected bitstream does not exist. Select the precompiled "
                "NanoQL-*-FPGA.fs file from the release, or build NanoQL first.",
            )
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

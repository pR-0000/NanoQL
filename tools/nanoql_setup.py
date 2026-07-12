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
        self.firmware_mode = tk.StringVar(value="normal")
        self.rom_path = tk.StringVar()
        self.sd_path = tk.StringVar()
        self.ipc_path = tk.StringVar()
        self.gowin_path = tk.StringVar(value=find_gowin())
        self.loader_path = tk.StringVar(value=shutil.which("openFPGALoader") or "")
        self.bitstream_path = tk.StringVar(
            value=str(REPOSITORY / "impl" / "pnr" / "NanoQL_sd_rom.fs")
        )
        self.status = tk.StringVar(value="Prêt / Ready")

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
        notebook.add(firmware_tab, text="1. BL616 Companion")
        notebook.add(storage_tab, text="2. ROM et microSD")
        notebook.add(fpga_tab, text="3. FPGA")

        self._build_firmware_tab(firmware_tab)
        self._build_storage_tab(storage_tab)
        self._build_fpga_tab(fpga_tab)

        log_frame = ttk.LabelFrame(self, text="Journal / Log", padding=8)
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
        ttk.Label(parent, text="Révision de carte / Board revision", style="Section.TLabel").grid(
            row=0, column=0, sticky="w", pady=(0, 8)
        )
        revision = ttk.Combobox(
            parent, textvariable=self.revision, values=("3921", "3923"), state="readonly", width=12
        )
        revision.grid(row=0, column=1, sticky="w", pady=(0, 8))

        ttk.Label(parent, text="Mode firmware", style="Section.TLabel").grid(
            row=1, column=0, sticky="nw", pady=8
        )
        modes = ttk.Frame(parent)
        modes.grid(row=1, column=1, sticky="w", pady=8)
        ttk.Radiobutton(
            modes,
            text="Normal: programmateur avec PC, Companion sans PC",
            variable=self.firmware_mode,
            value="normal",
        ).pack(anchor="w")
        ttk.Radiobutton(
            modes,
            text="Test: Companion toujours actif",
            variable=self.firmware_mode,
            value="test",
        ).pack(anchor="w")

        actions = ttk.Frame(parent)
        actions.grid(row=2, column=0, columnspan=2, sticky="w", pady=(18, 8))
        self._button(actions, "Préparer les fichiers", self.prepare_firmware).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Préparer et ouvrir FlashCube", self.prepare_and_open_flashcube).pack(
            side="left"
        )

        ttk.Label(
            parent,
            text=(
                "Maintenez UPDATE pendant la connexion USB, relâchez-le, sélectionnez le port COM "
                "dans FlashCube puis choisissez le fichier .ini indiqué dans le journal."
            ),
            wraplength=760,
        ).grid(row=3, column=0, columnspan=2, sticky="w", pady=(12, 0))

    def _build_storage_tab(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(1, weight=1)
        self._path_row(parent, 0, "ROM QL 48/64 Kio", self.rom_path, self._browse_rom)
        self._path_row(parent, 1, "Racine microSD", self.sd_path, self._browse_sd)
        self._path_row(parent, 2, "Firmware IPC Hermes Intel HEX", self.ipc_path, self._browse_ipc)

        actions = ttk.Frame(parent)
        actions.grid(row=3, column=0, columnspan=3, sticky="w", pady=(18, 8))
        self._button(actions, "Préparer la microSD", self.prepare_sd).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Convertir le firmware IPC", self.prepare_ipc).pack(side="left")

        ttk.Label(
            parent,
            text=(
                "La ROM reste privée: elle est validée puis copiée sous le nom QL.rom. "
                "nanoql.ini est aussi créé pour demander son montage automatique."
            ),
            wraplength=760,
        ).grid(row=4, column=0, columnspan=3, sticky="w", pady=(12, 0))

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
        self._button(actions, "Compiler", self.build_fpga).pack(side="left", padx=(0, 8))
        self._button(actions, "Programmer SRAM", lambda: self.program_fpga(False)).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Programmer Flash", lambda: self.program_fpga(True)).pack(
            side="left", padx=(0, 8)
        )
        self._button(actions, "Tout préparer et compiler", self.prepare_and_build).pack(
            side="left"
        )

        ttk.Label(
            parent,
            text=(
                "SRAM est temporaire et disparaît à la coupure. Flash est persistante et permet "
                "au firmware BL616 normal de démarrer Companion sans ordinateur."
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
        ttk.Button(parent, text="Parcourir...", command=browse).grid(
            row=row, column=2, pady=8
        )

    def _button(self, parent: ttk.Frame, text: str, command) -> ttk.Button:
        button = ttk.Button(parent, text=text, command=command)
        self.busy_widgets.append(button)
        return button

    def _browse_rom(self) -> None:
        path = filedialog.askopenfilename(title="Sélectionner la ROM QL")
        if path:
            self.rom_path.set(path)

    def _browse_sd(self) -> None:
        path = filedialog.askdirectory(title="Sélectionner la racine de la microSD")
        if path:
            self.sd_path.set(path)

    def _browse_ipc(self) -> None:
        path = filedialog.askopenfilename(
            title="Sélectionner ipc8049-hermes.hex", filetypes=(("Intel HEX", "*.hex"), ("Tous", "*"))
        )
        if path:
            self.ipc_path.set(path)

    def _browse_gowin(self) -> None:
        path = filedialog.askopenfilename(title="Sélectionner gw_sh")
        if path:
            self.gowin_path.set(path)

    def _browse_loader(self) -> None:
        path = filedialog.askopenfilename(title="Sélectionner openFPGALoader")
        if path:
            self.loader_path.set(path)

    def _selected_config(self) -> Path:
        mode = "1_NORMAL" if self.firmware_mode.get() == "normal" else "2_TEST"
        suffix = "partner_auto" if mode == "1_NORMAL" else "companion_only"
        return (
            REPOSITORY
            / "private"
            / "bl616"
            / "flash-package"
            / f"{mode}_{self.revision.get()}_{suffix}.ini"
        )

    def prepare_firmware(self, callback=None) -> None:
        command = [
            sys.executable,
            str(TOOLS / "prepare_bl616_firmware.py"),
            "--revision",
            self.revision.get(),
        ]
        self._run(command, "Préparation du firmware BL616", callback)

    def prepare_and_open_flashcube(self) -> None:
        self.prepare_firmware(self._open_flashcube)

    def _open_flashcube(self) -> None:
        config = self._selected_config()
        candidates = list((REPOSITORY / "private" / "bl616" / "flashcube").rglob("BLFlashCube.exe"))
        if platform.system() != "Windows" or not candidates:
            messagebox.showinfo(
                "Firmware prêt",
                f"Configuration préparée:\n{config}\n\nFlashCube est disponible uniquement sous Windows.",
            )
            return
        self.clipboard_clear()
        self.clipboard_append(str(config))
        self._append_log(f"Configuration à sélectionner (copiée): {config}\n")
        subprocess.Popen([str(candidates[0])], cwd=config.parent)
        messagebox.showinfo(
            "FlashCube",
            f"Sélectionnez cette configuration dans FlashCube:\n\n{config}\n\nLe chemin a été copié.",
        )

    def prepare_sd(self) -> None:
        if not self.rom_path.get() or not self.sd_path.get():
            messagebox.showerror("Champs manquants", "Sélectionnez la ROM et la microSD.")
            return
        self._run(
            [sys.executable, str(TOOLS / "prepare_sd_card.py"), self.rom_path.get(), self.sd_path.get()],
            "Préparation de la microSD",
        )

    def prepare_ipc(self) -> None:
        if not self.ipc_path.get():
            messagebox.showerror("Champ manquant", "Sélectionnez le firmware Hermes ipc8049-hermes.hex.")
            return
        self._run(
            [sys.executable, str(TOOLS / "prepare_ql_ipc_rom.py"), self.ipc_path.get()],
            "Conversion du firmware IPC",
        )

    def build_fpga(self) -> None:
        gowin = self.gowin_path.get()
        if not gowin or not Path(gowin).is_file():
            messagebox.showerror("Gowin introuvable", "Sélectionnez un exécutable gw_sh valide.")
            return
        ipc = REPOSITORY / "src" / "ipc" / "ql_ipc_rom.hex"
        if not ipc.is_file():
            messagebox.showerror("IPC manquant", "Convertissez d'abord le firmware IPC.")
            return
        self._run([gowin, BUILD_SCRIPT], "Compilation NanoQL")

    def prepare_and_build(self) -> None:
        gowin = self.gowin_path.get()
        if not gowin or not Path(gowin).is_file():
            messagebox.showerror("Gowin introuvable", "Sélectionnez un exécutable gw_sh valide.")
            return
        if not self.rom_path.get() or not self.sd_path.get():
            messagebox.showerror("Champs manquants", "Sélectionnez la ROM et la microSD.")
            return
        ipc_output = REPOSITORY / "src" / "ipc" / "ql_ipc_rom.hex"
        if not self.ipc_path.get() and not ipc_output.is_file():
            messagebox.showerror(
                "IPC manquant",
                "Sélectionnez le firmware Hermes ipc8049-hermes.hex au premier lancement.",
            )
            return

        commands: list[list[str]] = []
        if self.ipc_path.get():
            commands.append(
                [sys.executable, str(TOOLS / "prepare_ql_ipc_rom.py"), self.ipc_path.get()]
            )
        commands.append(
            [
                sys.executable,
                str(TOOLS / "prepare_sd_card.py"),
                self.rom_path.get(),
                self.sd_path.get(),
            ]
        )
        commands.append([gowin, "build_sd_rom.tcl"])
        self._run_commands(commands, "Préparation et compilation microSD")

    def program_fpga(self, persistent: bool) -> None:
        loader = self.loader_path.get()
        bitstream = Path(self.bitstream_path.get())
        if not loader or not Path(loader).is_file():
            messagebox.showerror(
                "openFPGALoader introuvable", "Sélectionnez un exécutable openFPGALoader valide."
            )
            return
        if not bitstream.is_file():
            messagebox.showerror("Bitstream absent", "Compilez d'abord cette variante.")
            return
        command = [loader, "-b", "tangnano20k"]
        if persistent:
            command.append("-f")
        command.append(str(bitstream))
        self._run(command, "Programmation Flash" if persistent else "Programmation SRAM")

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
                    self._finish_busy("Terminé / Complete")
                    self._append_log(f"{title}: OK\n")
                    if callback:
                        callback()
                elif event == "error":
                    title, error = payload
                    self._finish_busy("Erreur / Error")
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

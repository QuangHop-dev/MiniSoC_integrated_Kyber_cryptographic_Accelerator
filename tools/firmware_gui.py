#!/usr/bin/env python3
"""Desktop firmware loader and serial monitor for the Kyber PL SoC."""

from __future__ import annotations

import argparse
import queue
import subprocess
import sys
import threading
import time
from pathlib import Path
from tkinter import filedialog, messagebox, scrolledtext, ttk
import tkinter as tk

import serial
from serial.tools import list_ports


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "scripts"
SW_DIR = REPO_ROOT / "sw"
UPLOAD_TARGET = "imem"


def discover_apps() -> list[str]:
    apps_dir = SW_DIR / "apps"
    return sorted(
        path.name
        for path in apps_dir.iterdir()
        if path.is_dir() and (path / "main.c").is_file() and path.name != "uart_bootloader"
    )


def payload_path(app: str) -> Path:
    return SW_DIR / "build" / f"{app}_uart_{UPLOAD_TARGET}" / "firmware.bin"


class SerialMonitor:
    def __init__(self, output_queue: queue.Queue[tuple[str, str]]) -> None:
        self.output_queue = output_queue
        self.serial: serial.Serial | None = None
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None

    @property
    def is_open(self) -> bool:
        return self.serial is not None and self.serial.is_open

    def open(self, port: str, baud: int) -> None:
        self.close()
        self.serial = serial.Serial(port=port, baudrate=baud, timeout=0.1)
        self.stop_event.clear()
        self.thread = threading.Thread(target=self._reader, daemon=True)
        self.thread.start()

    def close(self) -> None:
        self.stop_event.set()
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=0.5)
        if self.serial is not None:
            self.serial.close()
        self.serial = None
        self.thread = None

    def write(self, data: bytes) -> None:
        if not self.is_open or self.serial is None:
            raise RuntimeError("serial monitor is not open")
        self.serial.write(data)
        self.serial.flush()

    def _reader(self) -> None:
        assert self.serial is not None
        while not self.stop_event.is_set():
            try:
                data = self.serial.read(256)
            except serial.SerialException as exc:
                self.output_queue.put(("error", f"Serial error: {exc}\n"))
                break
            if data:
                self.output_queue.put(("serial", data.decode("utf-8", errors="replace")))


class FirmwareGui(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("SoC Firmware Loader")
        self.geometry("900x650")
        self.minsize(760, 520)

        self.events: queue.Queue[tuple[str, str]] = queue.Queue()
        self.monitor = SerialMonitor(self.events)
        self.busy = False

        apps = discover_apps()
        default_app = "full_demo" if "full_demo" in apps else (
            "peripheral_demo" if "peripheral_demo" in apps else apps[0]
        )
        self.app_var = tk.StringVar(value=default_app)
        self.source_var = tk.StringVar()
        self.output_var = tk.StringVar()
        self.port_var = tk.StringVar()
        self.baud_var = tk.StringVar(value="115200")
        self.kat_tests_var = tk.StringVar(value="1")
        self.status_var = tk.StringVar(value="Ready")

        self._build_ui(apps)
        self._sync_paths()
        self.refresh_ports()
        self.after(50, self._drain_events)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_ui(self, apps: list[str]) -> None:
        root = ttk.Frame(self, padding=12)
        root.grid(row=0, column=0, sticky="nsew")
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(4, weight=1)

        firmware = ttk.LabelFrame(root, text="Firmware", padding=10)
        firmware.grid(row=0, column=0, columnspan=3, sticky="ew")
        firmware.columnconfigure(1, weight=1)

        ttk.Label(firmware, text="Application").grid(row=0, column=0, sticky="w", padx=(0, 8))
        app_box = ttk.Combobox(
            firmware, textvariable=self.app_var, values=apps, state="readonly", width=24
        )
        app_box.grid(row=0, column=1, sticky="w")
        app_box.bind("<<ComboboxSelected>>", lambda _event: self._sync_paths())

        ttk.Label(firmware, text="Source").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(firmware, textvariable=self.source_var, state="readonly").grid(
            row=1, column=1, columnspan=2, sticky="ew", pady=(8, 0)
        )

        ttk.Label(firmware, text="Payload").grid(row=2, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(firmware, textvariable=self.output_var).grid(
            row=2, column=1, sticky="ew", pady=(8, 0)
        )
        ttk.Button(firmware, text="Browse", command=self.browse_payload).grid(
            row=2, column=2, sticky="e", padx=(8, 0), pady=(8, 0)
        )

        serial_frame = ttk.LabelFrame(root, text="Serial Port", padding=10)
        serial_frame.grid(row=1, column=0, columnspan=3, sticky="ew", pady=(10, 0))
        serial_frame.columnconfigure(1, weight=1)

        ttk.Label(serial_frame, text="Port").grid(row=0, column=0, sticky="w", padx=(0, 8))
        self.port_box = ttk.Combobox(serial_frame, textvariable=self.port_var, state="readonly")
        self.port_box.grid(row=0, column=1, sticky="ew")
        ttk.Button(serial_frame, text="Refresh", command=self.refresh_ports).grid(
            row=0, column=2, padx=(8, 0)
        )
        ttk.Label(serial_frame, text="Baud").grid(row=0, column=3, padx=(16, 8))
        ttk.Entry(serial_frame, textvariable=self.baud_var, width=10).grid(row=0, column=4)

        actions = ttk.Frame(root)
        actions.grid(row=2, column=0, columnspan=3, sticky="ew", pady=10)
        self.compile_button = ttk.Button(actions, text="Compile", command=self.compile_firmware)
        self.compile_button.pack(side="left")
        self.upload_button = ttk.Button(actions, text="Upload", command=self.upload_firmware)
        self.upload_button.pack(side="left", padx=(8, 0))
        self.monitor_button = ttk.Button(
            actions, text="Open Serial Monitor", command=self.toggle_monitor
        )
        self.monitor_button.pack(side="left", padx=(8, 0))
        self.kat_button = ttk.Button(
            actions, text="Run HW KAT", command=self.run_hw_kat
        )
        self.kat_button.pack(side="left", padx=(8, 0))
        ttk.Label(actions, text="Tests").pack(side="left", padx=(12, 4))
        self.kat_tests_entry = ttk.Entry(actions, textvariable=self.kat_tests_var, width=6)
        self.kat_tests_entry.pack(side="left")
        ttk.Label(
            actions,
            text="Re-upload: click Upload, then press CPU_RESET (SW20)",
        ).pack(side="left", padx=(18, 0))
        ttk.Button(actions, text="Clear Log", command=lambda: self.log.delete("1.0", tk.END)).pack(
            side="right"
        )

        ttk.Separator(root).grid(row=3, column=0, columnspan=3, sticky="ew")
        self.log = scrolledtext.ScrolledText(root, wrap=tk.WORD, font=("Consolas", 10))
        self.log.grid(row=4, column=0, columnspan=3, sticky="nsew", pady=(10, 0))

        status = ttk.Frame(root)
        status.grid(row=5, column=0, columnspan=3, sticky="ew", pady=(8, 0))
        ttk.Label(status, textvariable=self.status_var).pack(side="left")

    def _sync_paths(self) -> None:
        app = self.app_var.get()
        self.source_var.set(str(SW_DIR / "apps" / app / "main.c"))
        self.output_var.set(str(payload_path(app)))
        if hasattr(self, "kat_button"):
            state = tk.NORMAL if app == "kyber_hw_kat" and not self.busy else tk.DISABLED
            self.kat_button.configure(state=state)
            self.kat_tests_entry.configure(state=state)

    def browse_payload(self) -> None:
        selected = filedialog.askopenfilename(
            initialdir=str(Path(self.output_var.get()).parent),
            filetypes=(("Firmware binary", "*.bin"), ("Intel HEX", "*.ihex"), ("All files", "*.*")),
        )
        if selected:
            self.output_var.set(selected)

    def refresh_ports(self) -> None:
        port_info = list(list_ports.comports())
        ports = [port.device for port in port_info]
        self.port_box["values"] = ports
        if ports and self.port_var.get() not in ports:
            preferred = next(
                (
                    port.device
                    for port in port_info
                    if "CP2108" in port.description and "Interface 2" in port.description
                ),
                ports[0],
            )
            self.port_var.set(preferred)
            self.status_var.set(f"Serial port ready: {preferred}")
        elif not ports:
            self.port_var.set("")
            self.status_var.set("No serial port detected")

    def _append(self, text: str) -> None:
        self.log.insert(tk.END, text)
        self.log.see(tk.END)

    def _set_busy(self, busy: bool, status: str) -> None:
        self.busy = busy
        state = tk.DISABLED if busy else tk.NORMAL
        self.compile_button.configure(state=state)
        self.upload_button.configure(state=state)
        kat_state = tk.NORMAL if (not busy and self.app_var.get() == "kyber_hw_kat") else tk.DISABLED
        self.kat_button.configure(state=kat_state)
        self.kat_tests_entry.configure(state=kat_state)
        self.status_var.set(status)

    def _run_command(self, command: list[str], success: str) -> None:
        def worker() -> None:
            output_lines: list[str] = []
            self.events.put(("log", "$ " + subprocess.list2cmdline(command) + "\n"))
            process = subprocess.Popen(
                command,
                cwd=REPO_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            assert process.stdout is not None
            for line in process.stdout:
                output_lines.append(line)
                self.events.put(("log", line))
            rc = process.wait()
            if rc == 0:
                self.events.put(("done", success))
            else:
                output = "".join(output_lines)
                if "UART bootloader did not respond" in output:
                    failure = (
                        "Bootloader did not respond.\n\n"
                        "Click Upload again, then immediately press and release "
                        "CPU_RESET (SW20) on the ZCU102.\n\n"
                        "Use COM5 (CP2108 Interface 2). Do not use SW3 or SW4."
                    )
                else:
                    failure = f"Command failed with exit code {rc}"
                self.events.put(("failed", failure))

        threading.Thread(target=worker, daemon=True).start()

    def compile_firmware(self) -> None:
        if self.busy:
            return
        self._set_busy(True, "Compiling firmware...")
        command = [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(SCRIPTS / "build_uart_payload.ps1"),
            "-App", self.app_var.get(), "-Target", UPLOAD_TARGET,
        ]
        self._run_command(command, "Compile completed")

    def _serial_settings(self) -> tuple[str, int] | None:
        port = self.port_var.get().strip()
        try:
            baud = int(self.baud_var.get(), 10)
        except ValueError:
            messagebox.showerror("Invalid baud", "Baud rate must be an integer.")
            return None
        if not port:
            messagebox.showerror("No serial port", "Select a serial port first.")
            return None
        return port, baud

    def upload_firmware(self) -> None:
        if self.busy:
            return
        settings = self._serial_settings()
        if settings is None:
            return
        payload = Path(self.output_var.get())
        if not payload.is_file():
            messagebox.showerror("Missing payload", f"Compile or select a payload first:\n{payload}")
            return
        if self.monitor.is_open:
            self.toggle_monitor()

        port, baud = settings
        available = [item.device for item in list_ports.comports()]
        if port not in available:
            self.refresh_ports()
            choices = ", ".join(available) if available else "none"
            messagebox.showerror(
                "Serial port disconnected",
                f"{port} is no longer available.\n\n"
                f"Available ports: {choices}\n\n"
                "Reconnect the board USB-UART cable, then click Refresh.",
            )
            return
        self._append(
            "\n"
            "============================================================\n"
            "UPLOAD: press and release CPU_RESET (SW20) on the ZCU102 now.\n"
            "The loader will wait up to 12 seconds for the bootloader.\n"
            "============================================================\n"
        )
        self._set_busy(True, "Waiting for CPU_RESET (SW20), then uploading...")
        command = [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(SCRIPTS / "send_uart_payload.ps1"),
            "-Port", port, "-Payload", str(payload), "-Target", UPLOAD_TARGET, "-Baud", str(baud),
            "-BannerTimeout", "12",
        ]
        self._run_command(command, "Upload completed")

    def toggle_monitor(self) -> None:
        if self.monitor.is_open:
            self.monitor.close()
            self.monitor_button.configure(text="Open Serial Monitor")
            self.status_var.set("Serial monitor closed")
            return
        settings = self._serial_settings()
        if settings is None:
            return
        port, baud = settings
        try:
            self.monitor.open(port, baud)
        except serial.SerialException as exc:
            messagebox.showerror("Serial error", str(exc))
            return
        self.monitor_button.configure(text="Close Serial Monitor")
        self.status_var.set(f"Monitoring {port} at {baud} baud")

    def run_hw_kat(self) -> None:
        if self.busy:
            return
        if self.app_var.get() != "kyber_hw_kat":
            messagebox.showerror(
                "Wrong application",
                "Select kyber_hw_kat, upload it, then run the hardware KAT stream.",
            )
            return
        settings = self._serial_settings()
        if settings is None:
            return
        try:
            tests = int(self.kat_tests_var.get(), 10)
        except ValueError:
            messagebox.showerror("Invalid KAT count", "Tests must be an integer.")
            return
        if tests <= 0 or tests > 10000:
            messagebox.showerror("Invalid KAT count", "Tests must be in range 1..10000.")
            return
        if self.monitor.is_open:
            self.toggle_monitor()

        port, baud = settings
        batch_size = min(100, tests)
        self._append(
            "\n"
            "==============================================================================\n"
            "HW KAT: streaming C reference vectors to kyber_hw_kat firmware.\n"
            "If the firmware is not waiting for KHV1, upload kyber_hw_kat again first.\n"
            "==============================================================================\n"
        )
        self._set_busy(True, f"Running {tests} Kyber HW KAT test(s)...")
        command = [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(SCRIPTS / "run_kyber_hw_kat_uart.ps1"),
            "-Port", port,
            "-Tests", str(tests),
            "-BatchSize", str(batch_size),
            "-Baud", str(baud),
            "-NoFirmwareBuild",
        ]
        self._run_command(command, "HW KAT completed")

    def _drain_events(self) -> None:
        try:
            while True:
                kind, text = self.events.get_nowait()
                if kind in {"log", "serial"}:
                    self._append(text)
                elif kind == "error":
                    self._append(text)
                    self.status_var.set("Serial monitor error")
                elif kind == "done":
                    self._append(text + "\n")
                    self._set_busy(False, text)
                elif kind == "failed":
                    self._append(text + "\n")
                    self._set_busy(False, text)
                    messagebox.showerror("Operation failed", text)
        except queue.Empty:
            pass
        self.after(50, self._drain_events)

    def _on_close(self) -> None:
        self.monitor.close()
        self.destroy()


def self_test() -> int:
    apps = discover_apps()
    assert "kyber_demo" in apps
    assert "peripheral_demo" in apps
    assert payload_path("kyber_demo").name == "firmware.bin"
    print("PASS: firmware GUI dependencies and app discovery")
    print("Applications:", ", ".join(apps))
    print("Serial ports:", ", ".join(port.device for port in list_ports.comports()) or "none")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    app = FirmwareGui()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

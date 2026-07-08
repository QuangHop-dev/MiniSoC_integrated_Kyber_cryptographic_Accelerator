#!/usr/bin/env python3
"""Send a Kyber SoC UART-bootloader payload.

Binary and memh inputs are wrapped in the KBL1 binary packet:
  "KBL1" + dst:u32le + len:u32le + entry:u32le + sum:u32le + payload

Intel HEX inputs are sent as text and keep the addresses encoded in the file.
"""

import argparse
import sys
import time
from pathlib import Path


def parse_u32(text: str) -> int:
    return int(text, 0) & 0xFFFFFFFF


def load_memh(path: Path) -> bytes:
    data = bytearray()
    for raw_line in path.read_text(encoding="ascii").splitlines():
        line = raw_line.split("#", 1)[0].split("//", 1)[0].strip()
        if not line:
            continue
        word = int(line, 16) & 0xFFFFFFFF
        data.extend(
            (
                word & 0xFF,
                (word >> 8) & 0xFF,
                (word >> 16) & 0xFF,
                (word >> 24) & 0xFF,
            )
        )
    return bytes(data)


def load_payload(path: Path, fmt: str) -> bytes:
    if fmt == "bin":
        return path.read_bytes()
    if fmt == "memh":
        return load_memh(path)
    if fmt == "ihex":
        return path.read_bytes()
    raise ValueError(f"unsupported format: {fmt}")


def detect_format(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix in {".bin", ".raw"}:
        return "bin"
    if suffix in {".ihex", ".ihx"}:
        return "ihex"
    return "memh"


def write_u32_le(value: int) -> bytes:
    return bytes(
        (
            value & 0xFF,
            (value >> 8) & 0xFF,
            (value >> 16) & 0xFF,
            (value >> 24) & 0xFF,
        )
    )


def make_binary_packet(payload: bytes, dst: int, entry: int) -> bytes:
    checksum = sum(payload) & 0xFFFFFFFF
    return (
        b"KBL1"
        + write_u32_le(dst)
        + write_u32_le(len(payload))
        + write_u32_le(entry)
        + write_u32_le(checksum)
        + payload
    )


def open_serial(port: str, baud: int):
    try:
        import serial  # type: ignore
        from serial.tools import list_ports  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "pyserial is required. Install it with: python -m pip install pyserial"
        ) from exc

    available = [item.device for item in list_ports.comports()]
    if port not in available:
        choices = ", ".join(available) if available else "none"
        raise RuntimeError(
            f"serial port {port} is not connected (available ports: {choices})"
        )
    try:
        return serial.Serial(port=port, baudrate=baud, timeout=0.1, write_timeout=2.0)
    except serial.SerialException as exc:
        raise RuntimeError(f"cannot open serial port {port}: {exc}") from exc


def drain_text(ser, seconds: float) -> str:
    end = time.time() + seconds
    out = bytearray()
    while time.time() < end:
        chunk = ser.read(256)
        if chunk:
            out.extend(chunk)
        else:
            time.sleep(0.01)
    return out.decode("ascii", errors="replace")


def wait_for_text(ser, needle: str, seconds: float) -> str:
    end = time.time() + seconds
    out = bytearray()
    needle_bytes = needle.encode("ascii")
    while time.time() < end:
        chunk = ser.read(256)
        if chunk:
            out.extend(chunk)
            if needle_bytes in out:
                break
        else:
            time.sleep(0.01)
    return out.decode("ascii", errors="replace")


def wait_for_any_text(ser, needles: tuple[str, ...], seconds: float) -> str:
    end = time.time() + seconds
    out = bytearray()
    needle_bytes = tuple(needle.encode("ascii") for needle in needles)
    while time.time() < end:
        chunk = ser.read(256)
        if chunk:
            out.extend(chunk)
            if any(needle in out for needle in needle_bytes):
                break
        else:
            time.sleep(0.01)
    return out.decode("ascii", errors="replace")


def wait_for_bootloader(ser, seconds: float) -> str:
    """Detect a fresh boot banner or probe an already-running bootloader."""
    banner = wait_for_text(ser, "KBL1 ready", min(seconds, 0.75))
    if "KBL1 ready" in banner:
        return banner

    # The bootloader reports code 1 for an unknown command and then returns to
    # its receive loop. This provides a nondestructive liveness handshake.
    ser.write(b"?")
    ser.flush()
    # A previous payload may still own the CPU. If the user presses CPU_RESET
    # while this probe is waiting, accept the fresh boot banner immediately.
    probe = wait_for_any_text(
        ser,
        ("ERR 0x00000001", "KBL1 ready"),
        max(seconds - 0.75, 0.75),
    )
    return banner + probe


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("payload", type=Path)
    parser.add_argument("--port", required=True, help="Serial port, for example COM5")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--format", choices=("auto", "bin", "memh", "ihex"), default="auto")
    parser.add_argument("--dest", type=parse_u32, help="Destination address for bin/memh")
    parser.add_argument("--entry", type=parse_u32, help="Entry address for bin/memh")
    parser.add_argument("--chunk", type=int, default=256)
    parser.add_argument("--banner-timeout", type=float, default=12.0)
    parser.add_argument(
        "--post-jump-seconds",
        type=float,
        default=1.5,
        help="capture early firmware UART output after the bootloader jump",
    )
    args = parser.parse_args()

    fmt = detect_format(args.payload) if args.format == "auto" else args.format
    payload = load_payload(args.payload, fmt)

    if fmt in {"bin", "memh"}:
        if args.dest is None:
            parser.error("--dest is required for bin/memh payloads")
        entry = args.entry if args.entry is not None else args.dest
        tx_data = make_binary_packet(payload, args.dest, entry)
    else:
        tx_data = payload

    try:
        ser = open_serial(args.port, args.baud)
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 5

    with ser:
        ser.reset_input_buffer()
        print(
            f"Waiting up to {args.banner_timeout:g}s for KBL1. "
            "If firmware is already running, press and release CPU_RESET (SW20) now."
        )
        handshake = wait_for_bootloader(ser, args.banner_timeout)
        if "KBL1 ready" in handshake:
            sys.stdout.write(handshake)
        elif "ERR 0x00000001" in handshake:
            print("KBL1 bootloader ready (probe)")
        if ("KBL1 ready" not in handshake) and ("ERR 0x00000001" not in handshake):
            print(
                "ERROR: UART bootloader did not respond. On ZCU102, click Upload "
                f"and press/release CPU_RESET (SW20) during the {args.banner_timeout:g}-second wait. "
                "If it still fails, program the bootloader bitstream again and "
                "select CP2108 Interface 2 (PL UART).",
                file=sys.stderr,
            )
            return 2

        total = len(tx_data)
        sent = 0
        while sent < total:
            end = min(sent + args.chunk, total)
            ser.write(tx_data[sent:end])
            sent = end
        ser.flush()

        response = wait_for_any_text(ser, ("JMP ", "OK BIN ", "OK B", "OK "), 10.0)
        if response:
            sys.stdout.write(response)
        if "ERR " in response:
            print("bootloader reported an error", file=sys.stderr)
            return 3
        if ("JMP " not in response) and ("OK " not in response):
            print("bootloader did not acknowledge and jump", file=sys.stderr)
            return 4
        if args.post_jump_seconds > 0:
            firmware_output = drain_text(ser, args.post_jump_seconds)
            if firmware_output:
                sys.stdout.write(firmware_output)

    print(f"sent {len(payload)} payload bytes as {fmt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

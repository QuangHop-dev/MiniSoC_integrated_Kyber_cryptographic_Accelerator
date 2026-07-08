#!/usr/bin/env python3
"""Stream Kyber KAT vectors to the on-board kyber_hw_kat firmware."""

from __future__ import annotations

import argparse
import struct
import sys
import time
from pathlib import Path

import serial


SEED_BYTES = 64
PK_BYTES = 800
SK_BYTES = 1632
CT_BYTES = 768
SS_BYTES = 32


def read_hex_bytes(path: Path, expected: int) -> bytes:
    text = path.read_text(encoding="utf-8")
    tokens = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if len(line) == 2:
            tokens.append(line)
        else:
            compact = "".join(line.split())
            if len(compact) % 2 != 0:
                raise ValueError(f"odd hex digit count in {path}")
            tokens.extend(compact[i : i + 2] for i in range(0, len(compact), 2))
    data = bytes(int(token, 16) for token in tokens)
    if len(data) != expected:
        raise ValueError(f"{path} has {len(data)} byte(s), expected {expected}")
    return data


def slice_case(data: bytes, index: int, size: int) -> bytes:
    start = index * size
    return data[start : start + size]


def load_vectors(vec_dir: Path, count: int) -> dict[str, bytes]:
    return {
        "keygen_seed": read_hex_bytes(vec_dir / "keygen_seed.hex", count * SEED_BYTES),
        "enc_seed": read_hex_bytes(vec_dir / "enc_seed.hex", count * SEED_BYTES),
        "pk": read_hex_bytes(vec_dir / "pk.hex", count * PK_BYTES),
        "sk": read_hex_bytes(vec_dir / "sk.hex", count * SK_BYTES),
        "ct": read_hex_bytes(vec_dir / "ct.hex", count * CT_BYTES),
        "ss_enc": read_hex_bytes(vec_dir / "ss_enc.hex", count * SS_BYTES),
        "ss_dec_valid": read_hex_bytes(vec_dir / "ss_dec_valid.hex", count * SS_BYTES),
        "ct_invalid": read_hex_bytes(vec_dir / "ct_invalid.hex", count * CT_BYTES),
        "ss_dec_invalid": read_hex_bytes(vec_dir / "ss_dec_invalid.hex", count * SS_BYTES),
    }


def vector_frame(vectors: dict[str, bytes], local: int, global_index: int) -> bytes:
    parts = [
        struct.pack("<I", global_index),
        slice_case(vectors["keygen_seed"], local, SEED_BYTES),
        slice_case(vectors["enc_seed"], local, SEED_BYTES),
        slice_case(vectors["pk"], local, PK_BYTES),
        slice_case(vectors["sk"], local, SK_BYTES),
        slice_case(vectors["ct"], local, CT_BYTES),
        slice_case(vectors["ss_enc"], local, SS_BYTES),
        slice_case(vectors["ss_dec_valid"], local, SS_BYTES),
        slice_case(vectors["ct_invalid"], local, CT_BYTES),
        slice_case(vectors["ss_dec_invalid"], local, SS_BYTES),
    ]
    return b"".join(parts)


class Log:
    def __init__(self, path: Path | None):
        self.path = path
        self.file = None
        if path is not None:
            path.parent.mkdir(parents=True, exist_ok=True)
            self.file = path.open("w", encoding="utf-8", newline="")

    def write(self, text: str) -> None:
        print(text, end="")
        if self.file is not None:
            self.file.write(text)
            self.file.flush()

    def close(self) -> None:
        if self.file is not None:
            self.file.close()


def read_line(ser: serial.Serial, log: Log, timeout: float) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        raw = ser.readline()
        if raw:
            text = raw.decode("utf-8", errors="replace")
            log.write(text)
            return text
    raise TimeoutError("timed out waiting for firmware log")


def wait_for_marker(
    ser: serial.Serial,
    log: Log,
    markers: tuple[str, ...],
    timeout: float,
) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        line = read_line(ser, log, max(0.1, deadline - time.monotonic()))
        for marker in markers:
            if marker in line:
                return marker
    raise TimeoutError(f"timed out waiting for any of: {', '.join(markers)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--vectors", required=True, type=Path)
    parser.add_argument("--start-test", type=int, required=True)
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--boot-wait", type=float, default=1.0)
    parser.add_argument("--ready-timeout", type=float, default=3.0)
    parser.add_argument("--test-timeout", type=float, default=20.0)
    args = parser.parse_args()

    if args.count <= 0 or args.count > 100:
        raise SystemExit("--count must be in range 1..100")

    vectors = load_vectors(args.vectors, args.count)
    log = Log(args.log)

    try:
        with serial.Serial(args.port, args.baud, timeout=0.2, write_timeout=5.0) as ser:
            time.sleep(0.2)
            ser.reset_input_buffer()
            if args.boot_wait > 0.0:
                boot_deadline = time.monotonic() + args.boot_wait
                while time.monotonic() < boot_deadline:
                    raw = ser.readline()
                    if raw:
                        text = raw.decode("utf-8", errors="replace")
                        log.write(text)
                        if "READY: kyber_hw_kat" in text:
                            break
            ser.write(b"KHV1")
            ser.write(struct.pack("<IHH", args.start_test, args.count, 0))
            ser.flush()

            marker = wait_for_marker(
                ser,
                log,
                ("READY-VECTOR", "RESULT: FAIL", "READY: kyber_hw_kat"),
                args.ready_timeout,
            )
            if marker == "READY: kyber_hw_kat":
                marker = wait_for_marker(
                    ser,
                    log,
                    ("READY-VECTOR", "RESULT: FAIL"),
                    args.ready_timeout,
                )
            if marker == "RESULT: FAIL":
                return 1

            for local in range(args.count):
                global_index = args.start_test + local
                ser.write(vector_frame(vectors, local, global_index))
                ser.flush()

                final_markers = ("READY-VECTOR", "PASS: kyber_hw_kat", "RESULT: FAIL")
                marker = wait_for_marker(ser, log, final_markers, args.test_timeout)
                if marker == "RESULT: FAIL":
                    return 1
                if marker == "PASS: kyber_hw_kat":
                    if local != args.count - 1:
                        log.write(
                            f"ERROR: firmware ended batch after vector {global_index}, "
                            f"expected {args.start_test + args.count - 1}\n"
                        )
                        return 1
                    return 0

            marker = wait_for_marker(
                ser,
                log,
                ("PASS: kyber_hw_kat", "RESULT: FAIL"),
                args.test_timeout,
            )
            return 0 if marker == "PASS: kyber_hw_kat" else 1
    finally:
        log.close()


if __name__ == "__main__":
    raise SystemExit(main())

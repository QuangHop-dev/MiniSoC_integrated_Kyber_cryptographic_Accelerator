#!/usr/bin/env python3
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <firmware.bin> <firmware.hex>", file=sys.stderr)
        return 2

    data = bytearray(Path(sys.argv[1]).read_bytes())
    while len(data) % 4:
        data.append(0)

    out = Path(sys.argv[2])
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="ascii", newline="\n") as f:
        for i in range(0, len(data), 4):
            word = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)
            f.write(f"{word:08x}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

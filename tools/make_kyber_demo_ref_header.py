from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VEC = ROOT / "build" / "kyber_wb_slave_kat_tb" / "vectors"
OUT = ROOT / "sw" / "include" / "kyber_demo_ref.h"

SPECS = [
    ("ref_keygen_seed", "keygen_seed.hex", 64),
    ("ref_enc_seed", "enc_seed.hex", 64),
    ("ref_pk", "pk.hex", 800),
    ("ref_sk", "sk.hex", 1632),
    ("ref_ct", "ct.hex", 768),
    ("ref_ss_enc", "ss_enc.hex", 32),
    ("ref_ss_dec_valid", "ss_dec_valid.hex", 32),
    ("ref_ss_dec_invalid", "ss_dec_invalid.hex", 32),
]

def read_first_bytes(name: str, n: int) -> list[int]:
    path = VEC / name
    if not path.exists():
        raise SystemExit(f"missing vector file: {path}")
    vals = []
    for line in path.read_text().splitlines():
        s = line.strip()
        if not s:
            continue
        vals.append(int(s, 16) & 0xff)
        if len(vals) == n:
            break
    if len(vals) != n:
        raise SystemExit(f"{path} has only {len(vals)} bytes, need {n}")
    return vals

def emit_array(var: str, vals: list[int]) -> str:
    lines = []
    lines.append(f"static const uint8_t {var}[{len(vals)}] = {{")
    for i in range(0, len(vals), 16):
        chunk = vals[i:i+16]
        lines.append("    " + ", ".join(f"0x{x:02x}" for x in chunk) + ",")
    lines.append("};")
    return "\n".join(lines)

parts = [
    "#ifndef KYBER_DEMO_REF_H",
    "#define KYBER_DEMO_REF_H",
    "",
    "#include <stdint.h>",
    "",
]

for var, fname, n in SPECS:
    parts.append(emit_array(var, read_first_bytes(fname, n)))
    parts.append("")

parts += ["#endif", ""]

OUT.write_text("\n".join(parts), encoding="ascii")
print(f"wrote {OUT}")
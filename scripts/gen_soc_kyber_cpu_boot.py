#!/usr/bin/env python3
import argparse
from pathlib import Path


X0 = 0
RA = 1
T0 = 5
T1 = 6
T2 = 7
S0 = 8
S1 = 9
A0 = 10
S2 = 18
S3 = 19


def sign12(value: int) -> int:
    value &= 0xFFF
    return value - 0x1000 if value & 0x800 else value


def check_imm(value: int, bits: int, align: int = 1) -> None:
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    if value < lo or value > hi or (value % align) != 0:
        raise ValueError(f"Immediate {value} does not fit signed {bits}-bit alignment {align}")


def enc_i(imm, rs1, funct3, rd, opcode):
    check_imm(imm, 12)
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm, rs2, rs1, funct3, opcode=0x23):
    check_imm(imm, 12)
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | opcode


def enc_b(imm, rs2, rs1, funct3, opcode=0x63):
    check_imm(imm, 13, 2)
    imm &= 0x1FFF
    return ((imm >> 12) & 0x1) << 31 | ((imm >> 5) & 0x3F) << 25 | (rs2 << 20) | (rs1 << 15) | \
        (funct3 << 12) | ((imm >> 1) & 0xF) << 8 | ((imm >> 11) & 0x1) << 7 | opcode


def enc_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def enc_j(imm, rd, opcode=0x6F):
    check_imm(imm, 21, 2)
    imm &= 0x1FFFFF
    return ((imm >> 20) & 0x1) << 31 | ((imm >> 1) & 0x3FF) << 21 | ((imm >> 11) & 0x1) << 20 | \
        ((imm >> 12) & 0xFF) << 12 | (rd << 7) | opcode


class Asm:
    def __init__(self):
        self.words = []
        self.labels = {}
        self.fixups = []

    @property
    def pc(self):
        return len(self.words) * 4

    def label(self, name):
        self.labels[name] = self.pc

    def word(self, value):
        self.words.append(value & 0xFFFFFFFF)

    def addi(self, rd, rs1, imm):
        self.word(enc_i(imm, rs1, 0b000, rd, 0x13))

    def andi(self, rd, rs1, imm):
        self.word(enc_i(imm, rs1, 0b111, rd, 0x13))

    def lui(self, rd, imm20):
        self.word(enc_u(imm20, rd, 0x37))

    def lw(self, rd, imm, rs1):
        self.word(enc_i(imm, rs1, 0b010, rd, 0x03))

    def sw(self, rs2, imm, rs1):
        self.word(enc_s(imm, rs2, rs1, 0b010))

    def beq(self, rs1, rs2, label):
        self.fixups.append((len(self.words), "beq", rs1, rs2, label))
        self.word(0)

    def bne(self, rs1, rs2, label):
        self.fixups.append((len(self.words), "bne", rs1, rs2, label))
        self.word(0)

    def jal(self, rd, label):
        self.fixups.append((len(self.words), "jal", rd, 0, label))
        self.word(0)

    def jalr(self, rd, imm, rs1):
        self.word(enc_i(imm, rs1, 0b000, rd, 0x67))

    def li(self, rd, value):
        value &= 0xFFFFFFFF
        signed_value = value - 0x100000000 if value & 0x80000000 else value
        if -2048 <= signed_value <= 2047:
            self.addi(rd, X0, signed_value)
            return

        hi = (value + 0x800) >> 12
        lo = sign12(value - (hi << 12))
        self.lui(rd, hi)
        if lo != 0:
            self.addi(rd, rd, lo)

    def align_words(self):
        while self.pc % 4:
            self.word(0)

    def data_bytes(self, data):
        for i in range(0, len(data), 4):
            chunk = data[i:i + 4]
            while len(chunk) < 4:
                chunk.append(0)
            self.word(chunk[0] | (chunk[1] << 8) | (chunk[2] << 16) | (chunk[3] << 24))

    def resolve(self):
        for idx, kind, a, b, label in self.fixups:
            if label not in self.labels:
                raise KeyError(f"Unknown label {label}")
            pc = idx * 4
            off = self.labels[label] - pc
            if kind == "beq":
                self.words[idx] = enc_b(off, b, a, 0b000)
            elif kind == "bne":
                self.words[idx] = enc_b(off, b, a, 0b001)
            elif kind == "jal":
                self.words[idx] = enc_j(off, a)
            else:
                raise ValueError(kind)


def read_hex_bytes(path: Path, count: int, offset: int = 0):
    values = []
    with path.open("r", encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if line:
                values.append(int(line, 16))
    chunk = values[offset:offset + count]
    if len(chunk) != count:
        raise ValueError(f"{path} has {len(values)} byte entries, need offset {offset} count {count}")
    return chunk


def build_program(keygen_seed, enc_seed, ct_invalid):
    a = Asm()

    # Permanent base registers: s2=GPIO0, s3=GPIO1.
    a.li(S2, 0x00020000)
    a.li(S3, 0x00030000)

    a.li(T0, 0xFF)
    a.sw(T0, 0, S2)       # GPIO0 direction = output.
    a.li(T0, 0x01)
    a.sw(T0, 4, S2)       # Boot marker.

    # Key generation.
    a.jal(RA, "soft_reset")
    a.li(S0, 0)           # patched after labels resolve
    keygen_src_li_idx = len(a.words) - 1
    a.li(S1, 0x00083000)  # KYBER seed window.
    a.li(T2, 16)
    a.jal(RA, "copy_words")
    a.li(T1, 0x03)        # opcode=1, start=1.
    a.jal(RA, "start_and_poll")
    a.li(A0, 0x11)
    a.jal(RA, "report_wait")

    # Encapsulation.
    a.jal(RA, "soft_reset")
    a.li(S0, 0)
    enc_src_li_idx = len(a.words) - 1
    a.li(S1, 0x00083000)
    a.li(T2, 16)
    a.jal(RA, "copy_words")
    a.li(T1, 0x05)        # opcode=2, start=1.
    a.jal(RA, "start_and_poll")
    a.li(A0, 0x22)
    a.jal(RA, "report_wait")

    # Valid decapsulation reuses SK and CT already in the Kyber window.
    a.jal(RA, "soft_reset")
    a.li(T1, 0x07)        # opcode=3, start=1.
    a.jal(RA, "start_and_poll")
    a.li(A0, 0x33)
    a.jal(RA, "report_wait")

    # Invalid decapsulation overwrites CT with a KAT-mutated ciphertext.
    a.li(S0, 0)
    invalid_ct_src_li_idx = len(a.words) - 1
    a.li(S1, 0x00081770)  # KYBER CT window.
    a.li(T2, 192)
    a.jal(RA, "copy_words")
    a.jal(RA, "soft_reset")
    a.li(T1, 0x07)
    a.jal(RA, "start_and_poll")
    a.li(T0, 0x44)
    a.sw(T0, 4, S2)
    a.label("done")
    a.jal(X0, "done")

    a.label("copy_words")
    a.label("copy_loop")
    a.lw(T0, 0, S0)
    a.sw(T0, 0, S1)
    a.addi(S0, S0, 4)
    a.addi(S1, S1, 4)
    a.addi(T2, T2, -1)
    a.bne(T2, X0, "copy_loop")
    a.jalr(X0, 0, RA)

    a.label("soft_reset")
    a.li(T0, 0x100)
    a.li(S1, 0x00084000)
    a.sw(T0, 0, S1)
    a.jalr(X0, 0, RA)

    a.label("start_and_poll")
    a.li(S1, 0x00084000)
    a.sw(T1, 0, S1)
    a.li(S1, 0x00084004)
    a.label("poll_loop")
    a.lw(T0, 0, S1)
    a.andi(T0, T0, 0x02)
    a.beq(T0, X0, "poll_loop")
    a.jalr(X0, 0, RA)

    a.label("report_wait")
    a.sw(A0, 4, S2)
    a.label("wait_ack_high")
    a.lw(T0, 4, S3)
    a.andi(T0, T0, 0x01)
    a.beq(T0, X0, "wait_ack_high")
    a.label("wait_ack_low")
    a.lw(T0, 4, S3)
    a.andi(T0, T0, 0x01)
    a.bne(T0, X0, "wait_ack_low")
    a.jalr(X0, 0, RA)

    a.align_words()
    a.label("keygen_seed")
    a.data_bytes(list(keygen_seed))
    a.label("enc_seed")
    a.data_bytes(list(enc_seed))
    a.label("ct_invalid")
    a.data_bytes(list(ct_invalid))

    # Patch li placeholders that could not know data labels yet.
    def li_words(rd, value):
        tmp = Asm()
        tmp.li(rd, value)
        return tmp.words

    # The label patch above is intentionally constrained by keeping all data
    # labels below 2048, so each placeholder is a single ADDI.
    if any(a.labels[name] > 2047 for name in ("keygen_seed", "enc_seed", "ct_invalid")):
        raise RuntimeError("Firmware grew beyond single-instruction data address loads")

    for idx, label in (
        (keygen_src_li_idx, "keygen_seed"),
        (enc_src_li_idx, "enc_seed"),
        (invalid_ct_src_li_idx, "ct_invalid"),
    ):
        words = li_words(S0, a.labels[label])
        if len(words) != 1:
            raise RuntimeError(f"{label} address unexpectedly requires multi-instruction li")
        a.words[idx] = words[0]

    a.resolve()
    return a.words


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vectors", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    keygen_seed = read_hex_bytes(args.vectors / "keygen_seed.hex", 64)
    enc_seed = read_hex_bytes(args.vectors / "enc_seed.hex", 64)
    ct_invalid = read_hex_bytes(args.vectors / "ct_invalid.hex", 768)

    words = build_program(keygen_seed, enc_seed, ct_invalid)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="ascii", newline="\n") as f:
        for word in words:
            f.write(f"{word:08x}\n")


if __name__ == "__main__":
    main()

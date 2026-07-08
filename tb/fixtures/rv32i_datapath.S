    .section .text
    .globl _start

_start:
    # U-type
    lui   x1, 0x12345
    auipc x2, 0

    # R-type
    addi  x3, x0, 5
    addi  x4, x0, 7
    add   x5, x3, x4
    sub   x6, x4, x3
    sll   x7, x3, x4
    slt   x8, x3, x4
    sltu  x9, x4, x3
    xor   x10, x3, x4
    srl   x11, x7, x3
    addi  x12, x0, -16
    sra   x13, x12, x3
    or    x14, x3, x4
    and   x15, x3, x4

    # I-type
    addi  x16, x0, -3
    slti  x17, x16, 0
    sltiu x18, x16, 1
    xori  x19, x3, 15
    ori   x20, x3, 8
    andi  x21, x4, 6
    slli  x22, x3, 3
    srli  x23, x22, 2
    srai  x24, x12, 2

    # Store/load, including sign extension.
    sw    x1, 0x100(x0)
    sh    x12, 0x104(x0)
    sb    x16, 0x106(x0)
    lw    x26, 0x100(x0)
    lh    x27, 0x104(x0)
    lhu   x28, 0x104(x0)
    lb    x29, 0x106(x0)
    lbu   x30, 0x106(x0)

    # Every successful branch increments x31. Any failure jumps to fail.
    addi  x31, x0, 0
    beq   x3, x3, beq_ok
    jal   x0, fail
beq_ok:
    addi  x31, x31, 1
    bne   x3, x4, bne_ok
    jal   x0, fail
bne_ok:
    addi  x31, x31, 1
    blt   x3, x4, blt_ok
    jal   x0, fail
blt_ok:
    addi  x31, x31, 1
    bge   x4, x3, bge_ok
    jal   x0, fail
bge_ok:
    addi  x31, x31, 1
    bltu  x3, x4, bltu_ok
    jal   x0, fail
bltu_ok:
    addi  x31, x31, 1
    bgeu  x4, x3, bgeu_ok
    jal   x0, fail
bgeu_ok:
    addi  x31, x31, 1

    # JAL and JALR control-flow tests.
    jal   x0, jal_ok
    jal   x0, fail
jal_ok:
    addi  x31, x31, 1
    lui   x25, %hi(jalr_ok)
    addi  x25, x25, %lo(jalr_ok)
    jalr  x0, 0(x25)
    jal   x0, fail
jalr_ok:
    addi  x31, x31, 1
    addi  x25, x0, 0xa5

done:
    jal   x0, done

fail:
    addi  x31, x0, 0xee
    jal   x0, fail

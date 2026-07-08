    .section .init, "ax"
    .globl _start
    .type _start, @function

_start:
    la   sp, __stack_top

    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop

    la   a0, __data_load_start
    la   a1, __data_start
    la   a2, __data_end
1:
    beq  a1, a2, 2f
    lw   t0, 0(a0)
    sw   t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    jal  zero, 1b

2:
    la   a1, __bss_start
    la   a2, __bss_end
3:
    beq  a1, a2, 4f
    sw   zero, 0(a1)
    addi a1, a1, 4
    jal  zero, 3b

4:
    la   t0, _trap_entry
    csrw mtvec, t0
    call main

5:
    jal  zero, 5b

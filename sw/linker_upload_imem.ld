ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00004000, LENGTH = 16K
    SRAM (rwx) : ORIGIN = 0x00010000, LENGTH = 16K
}

SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.init))
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > IMEM

    .data : ALIGN(4)
    {
        __data_start = .;
        *(.sdata .sdata.*)
        *(.data .data.*)
        . = ALIGN(4);
        __data_end = .;
    } > SRAM AT > IMEM
    __data_load_start = LOADADDR(.data);

    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > SRAM

    . = ALIGN(16);
    __stack_bottom = .;
    __stack_top = ORIGIN(SRAM) + LENGTH(SRAM);
    ASSERT(__stack_bottom <= __stack_top, "SRAM overflow")

    __global_pointer$ = __data_start + 0x800;
}

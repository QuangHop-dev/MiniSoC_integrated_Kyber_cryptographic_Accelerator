# Kyber SoC Firmware

This firmware targets the RV32I CPU instantiated in PL inside `soc_top`.
For the ZCU102 PL-only demo, software is not loaded by the Zynq PS at runtime.
Instead, build a Boot ROM memory image and use it as the BRAM init file before
generating or updating the PL bitstream.

## Build

Install a bare-metal RISC-V toolchain that provides `riscv64-unknown-elf-gcc`
or set `CROSS` to another compatible prefix.

```powershell
cd sw
make APP=kyber_demo
```

On Windows shells where GNU Make is installed as `mingw32-make`, use:

```powershell
cd sw
mingw32-make APP=kyber_demo CROSS=C:/SysGCC/risc-v/bin/riscv64-unknown-elf-
```

If `python` is not in `PATH`, pass `PYTHON=C:/path/to/python.exe`.

Outputs:

| File | Use |
|---|---|
| `build/kyber_demo/firmware.elf` | Debug ELF. |
| `build/kyber_demo/firmware.bin` | Raw binary. |
| `build/kyber_demo/firmware.hex` | 32-bit `$readmemh` image for Boot ROM/IMEM. |
| `build/kyber_demo/firmware.lst` | Disassembly listing. |

## ZCU102 PL-Only Flow

Use `build/kyber_demo/firmware.hex` as the `BOOT_INIT_FILE` for `soc_top`.
Because the demo only programs PL, changing firmware normally requires either:

- regenerating the bitstream with the new BRAM init file, or
- using a Vivado memory-update flow such as `updatemem` if the design exports
  the memory map metadata for the Boot ROM.

## UART Bootloader Flow

The UART bootloader lets the PL bitstream stay fixed while software payloads
are replaced through the PL UART.

Build the bootloader image that is embedded into the bitstream:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_uart_bootloader.ps1
```

Build a payload linked for the writable IMEM window, which is the default
runtime target used by the GUI and upload scripts:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_uart_payload.ps1 -Target imem
```

After programming a bootloader-mode bitstream and resetting the SoC, send the
payload:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\send_uart_payload.ps1 -Port COM5 -Target imem
```

The bootloader can still accept SRAM payloads for low-level debug if the
firmware is linked for SRAM:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_uart_payload.ps1 -Target sram
powershell -ExecutionPolicy Bypass -File scripts\send_uart_payload.ps1 -Port COM5 -Target sram
```

Bootloader-mode memory layout:

| Region | Address | Use |
|---|---:|---|
| Bootloader ROM | `0x00000000..0x00003fff` | UART loader code. |
| Upload IMEM | `0x00004000..0x00007fff` | IMEM payload target. |
| SRAM | `0x00010000..0x00013fff` | Runtime `.data`, `.bss`, heap/stack, or SRAM debug payload target. |

The bootloader supports the `KBL1` binary packet used by
`sw/tools/uart_loader.py` and Intel HEX text records. The PowerShell send script
uses the binary packet for `.bin`/`.hex` memh files.

The demo reports progress on GPIO0:

| GPIO0 value | Meaning |
|---:|---|
| `0x01` | Booted. |
| `0x11` | Kyber keygen completed. |
| `0x22` | Kyber encaps completed. |
| `0x33` | Kyber valid decaps shared secret matched encaps. |
| `0x44` | Invalid ciphertext decaps produced reject-path secret. |
| `0xA5` | Demo finished successfully. |
| `0xE1`..`0xE5` | Error code. |

UART output is optional and depends on the board constraints connecting the PL
UART pins.

## Firmware Contents

- `crt0.S`, `linker.ld`: bare-metal RV32I reset path, SRAM stack, `.data`
  copy, `.bss` clear.
- `include/`, `lib/`: MMIO drivers for GPIO, I2C, Kyber, PIC, Timer, UART and
  the small libc/libgcc helpers needed without a runtime.
- `apps/kyber_demo`: PL-only Kyber demo. It generates deterministic seeds,
  runs keygen, encaps, valid decaps and invalid-ciphertext decaps through the
  Kyber Wishbone IP, then reports progress on GPIO0.

## Simulation Check

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_soc_top_tb.ps1
```

`run_soc_top_tb.ps1` builds the firmware, copies `firmware.hex` into the
simulator work directory, loads it through `tb/tb_soc_top.sv`, and waits for
the GPIO0 success markers through `0xA5`.

The older focused firmware smoke test is also available:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_sw_kyber_demo_tb.ps1
```

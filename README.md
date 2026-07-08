# Mini SoC: RISC-V CPU, integrated CRYSTALS-Kyber cryptographic accelerator.

This repository contains a small bare-metal SoC with a memory-mapped Kyber hardware accelerator. The design is intended for FPGA demonstration on the Xilinx ZCU102 board.

The system uses a 32-bit Wishbone interconnect. A RV32I processor runs firmware from on-chip memory and controls the peripherals and the Kyber accelerator through MMIO registers. The Kyber block supports the three KEM operations: key generation, encapsulation and decapsulation.

## Project scope

The repository is as hardware/software codesign project. It keeps the RTL, firmware, verification testbenches, FPGA scripts, board constraints and Kyber C reference code needed to build and validate the design.

The RV32I instruction set for the RISC-V CPU is based on [9], the I2C master is based on [11], the Kyber algorithm is based on [8] (with a hardware implementation limited to the Kyber-512 security level), and the Keccak-f1600 hash core is based on [12].

## Main features

- RV32I bare-metal processor integrated as the master.
- 32-bit Wishbone MMIO bus for memories, peripherals control.
- On-chip boot memory and SRAM implemented with FPGA BRAM.
- GPIO, UART, Timer, I2C andinterrupt controller peripherals.
- Kyber accelerator with Wishbone register/data-window interface.
- Bare-metal firmware drivers and demo applications.
- Vivado Tcl flow and ZCU102 constraints.

## Repository layout

```text
SoC/
├── rtl/
│   ├── board/              # ZCU102 top-level wrapper
│   ├── bus/                # Wishbone interconnect
│   ├── cpu/                # RV32I CPU core
│   ├── include/            # RTL memory-map definitions
│   ├── kyber/              # Kyber accelerator RTL
│   ├── mem/                # Boot memory, IMEM and SRAM blocks
│   ├── periph/             # GPIO, UART, Timer, I2C and PIC peripherals
│   └── soc_top.v           # SoC integration top
├── sw/
│   ├── apps/               # Bare-metal firmware applications
│   ├── include/            # C headers and MMIO definitions
│   ├── lib/                # Firmware drivers and small runtime helpers
│   ├── tools/              # Binary/HEX conversion and UART loader tools
│   └── Makefile            # RV32I firmware build flow
├── tb/                     # Testbenches 
├── scripts/                # Build, simulation and board scripts
├── fpga/vivado/            # Vivado Tcl project/bitstream/programming flow
├── kyber/ref/              # Kyber C reference used for KAT/vector generation
├── docs/                   # Memory map and project notes
└── tools/                  # Host-side GUI and helper scripts
```

## Hardware overview

At the top level, `rtl/soc_top.v` connects the RV32I CPU to the following address regions:

| Region | Base address | Implemented size | Purpose |
|---|---:|---:|---|
| Boot / IMEM | `0x0000_0000` | 64 KiB slot | Bootloader ROM and IMEM |
| SRAM | `0x0001_0000` | 64 KiB slot | `.data`, `.bss`, stack and heap |
| GPIO0 | `0x0002_0000` | 64 KiB slot | LEDs / general output |
| GPIO1 | `0x0003_0000` | 64 KiB slot | DIP switches / external inputs |
| I2C | `0x0004_0000` | 64 KiB slot | I2C master, used by the LCD demo |
| PIC | `0x0005_0000` | 64 KiB slot | Interrupt pending and enable control |
| Timer | `0x0006_0000` | 64 KiB slot | Periodic timer and interrupt source |
| UART | `0x0007_0000` | 64 KiB slot | Serial log and bootloader payload input |
| Kyber | `0x0008_0000` | 64 KiB slot | Kyber accelerator control |


## Kyber accelerator interface

The Kyber accelerator is exposed through a Wishbone slave at `0x0008_0000`. It has fixed byte windows for the KEM objects and a small CSR area for operation control.

| Data window | Offset | Size |
|---|---:|---:|
| Public key (`pk`) | `0x0000` | 800 bytes |
| Secret key (`sk`) | `0x07D0` | 1632 bytes |
| Ciphertext (`ct`) | `0x1770` | 768 bytes |
| Shared secret (`ss`) | `0x1F40` | 32 bytes |
| Seed input | `0x3000` | 64 bytes |

| CSR | Offset | Use |
|---|---:|---|
| `CTRL` | `0x4000` | Start pulse, operation opcode and soft reset |
| `STATUS` | `0x4004` | Busy, done, error and debug state |
| `IRQ_ENABLE` | `0x4008` | Done interrupt enable |
| `IRQ_STATUS` | `0x400C` | Done interrupt status, write-one-to-clear |
| `CYCLE_COUNT` | `0x4010` | Operation cycle counter |

Supported opcodes:

| Opcode | Operation |
|---:|---|
| `1` | Key generation |
| `2` | Encapsulation |
| `3` | Decapsulation |

## Required tools

The main flow is written for Windows PowerShell, but most build steps are standard command-line flows.

| Tool | Used for |
|---|---|
| RISC-V bare-metal GCC | Building RV32I firmware |
| GNU Make or `mingw32-make` | Firmware build automation |
| Python 3 | HEX conversion, UART loader and host utilities |
| pyserial | UART payload upload and serial tools |
| Questa / ModelSim | Simulation |
| Vivado | ZCU102 project, implementation and bitstream generation |
| Host GCC + OpenSSL/libcrypto | Kyber KAT vector generator |

```

## Building firmware

The firmware is built from `sw/Makefile`. The default application is `kyber_demo`.

```powershell
cd sw
mingw32-make APP=kyber_demo CROSS=C:/SysGCC/risc-v/bin/riscv64-unknown-elf-
```

Output files are generated under `sw/build/<app>/`:

| File | Purpose |
|---|---|
| `firmware.elf` | Debug ELF |
| `firmware.bin` | Raw binary image |
| `firmware.hex` | 32-bit `$readmemh` image for simulation/BRAM init |
| `firmware.ihex` | Intel HEX image |
| `firmware.lst` | Disassembly listing |

The repository also provides a convenience wrapper for the main Kyber demo firmware:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_firmware.ps1 `
  -Cross C:\SysGCC\risc-v\bin\riscv64-unknown-elf-
```

## Simulation

Run the full selected regression from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_all_tests.ps1 `
  -KyberRandomTests 100 `
  -KyberKatTests 100 `
  -MaxCycles 80000000
```

Important standalone simulation entry points:

```powershell
# Kyber-512 KAT test through the Wishbone slave interface
powershell -ExecutionPolicy Bypass -File .\scripts\run_kyber_wb_slave_kat_tb.ps1 -Tests 100 -BatchSize 100

# CPU controls the Kyber accelerator through MMIO
powershell -ExecutionPolicy Bypass -File .\scripts\run_soc_top_kyber_cpu_tb.ps1

# Full SoC firmware simulation
powershell -ExecutionPolicy Bypass -File .\scripts\run_soc_top_tb.ps1

# UART bootloader simulation
powershell -ExecutionPolicy Bypass -File .\scripts\run_soc_top_uart_bootloader_tb.ps1
```

Simulation output is written under `build/`. This directory should remain untracked.

## ZCU102 FPGA flow

Create the Vivado project only:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_vivado_zcu102.ps1 -CreateOnly
```

Build a normal bitstream with the Kyber demo firmware embedded in the boot memory:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_vivado_zcu102.ps1 `
  -Jobs 4 `
  -Vivado C:\Vivado_Enterprise\Vivado\2021.2\bin\vivado.bat
```

Build a bootloader-mode bitstream:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_vivado_zcu102.ps1 `
  -Bootloader `
  -Jobs 4 `
  -Vivado C:\Vivado_Enterprise\Vivado\2021.2\bin\vivado.bat
```

Program the board:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\program_zcu102.ps1 `
  -Bitstream .\build\vivado\zcu102\kyber_soc_zcu102.bit
```

Vivado outputs are generated under `build/vivado/zcu102/`.

## UART bootloader flow

Bootloader mode keeps the FPGA bitstream fixed and loads new firmware payloads through the PL UART.

Build the bootloader firmware used as the BRAM initialization image:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_uart_bootloader.ps1
```

Build a payload for the writable IMEM upload region:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_uart_payload.ps1 `
  -App full_demo `
  -Target imem
```

Send the payload after the bootloader-mode bitstream has been programmed:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\send_uart_payload.ps1 `
  -Port COM5 `
  -Target imem `
  -Baud 115200
```

The helper batch file is also available:

```bat
scripts\send_uart_payload.cmd -Port COM5 -Target imem -Baud 115200
```

The GUI wrapper can compile, upload and monitor the serial output:

```bat
scripts\run_firmware_gui.cmd
```

## Firmware applications

| Application | Description |
|---|---|
| `full_demo` | Board demo using UART, GPIO, Timer/PIC interrupt, LCD I2C and Kyber |
| `kyber_hw_kat` | Board-level Kyber KAT runner over UART |

## References

[1] Shor, Peter W. "Quantum computing." Documenta Mathematica 1, no. 1000 (1998): 467-486.  
[2] Crescenzo, Diamante Simone, Rafael Carrera Rodriguez, Riccardo Alidori, Florent Brugière, Emanuele Valea, Pascal Benoit, and Alberto Bosio. "Hardware accelerator for FIPS 202 hash functions in post-quantum ready SoCs." In 2024 IEEE 30th International Symposium on On-Line Testing and Robust System Design (IOLTS), pp. 1-6. IEEE, 2024.    
[3] Nannipieri, Pietro, Stefano Di Matteo, Luca Zulberti, Francesco Albicocchi, Sergio Saponara, and Luca Fanucci. "A RISC-V post quantum cryptography instruction set extension for number theoretic transform to speed-up CRYSTALS algorithms." IEEE Access 9 (2021): 150798-150808.  
[4] Wu-Yiming-Huang, Miaoqing-Huang, Zhongkui-Lei and Jiaxuan, "A Pure Hardware Implementation of CRYSTALS-KYBER PQC Algorithm through Resource Reuse," IEICE Electronics Express, vol. advpub, p. 17.2020023, 2020.  
[5] Soni-Deepraj and Karri-Ramesh, "Efficient Hardware Implementation of PQC Primitives and PQC algorithms Using High-Level Synthesis," 2021 IEEE Computer Society Annual Symposium on VLSI, pp. 296-301, 2021.  
[6] He-Ma-Shiyang, Hui-Li, Fenghua-Li and Ruhui, "A lightweight hardware implementation of CRYSTALS-Kyber," Journal of Information and Intelligence, vol. 2, no. 2, 949-7159, p. 2, 2024.  
[7] Arpan-Jati, Naina-Gupta, Anupam-Chattopadhyay and Kumar-Sanadhya-Somitra, "A Configurable CRYSTALS-Kyber Hardware Implementation with Side-Channel Protection," ACM Trans. Embed. Comput. Syst., vol. 23, no. 1539-9087, p. 25, 2024.  
[8] Avanzi, R., Bos, J., Ducas, L., Kiltz, E., Lepoint, T., Lyubashevsky, V., Schanck, J. M., Schwabe, P., Seiler, G., & Stehlé, D. (2017). CRYSTALS-Kyber Algorithm Specifications and supporting documentation. Available: https://nist.gov  
[9] A. Waterman and K. Asanović, “The RISC-V instruction set manual, vol. I, ver. 2.2”, SiFive Inc. and EECS Department, University of California, Berkeley, 2017. [Online]. Available: riscv.org.  
[10] Wade D. Peterson, “WISHBONE System-on-Chip (SoC) Interconnection Architecture for Portable IP Cores”, WISHBONE Classic Bus Cycle — WISHBONE B3, 2019.  
[11] “I2C Master – WISHBONE Compatible”, I2C Master - WISHBONE Compatible | Lattice Reference Design, 15/1/2015.  
[12] Bertoni-Guido, Daemen-Joan, Hoffer-Seth, Peeters-Michaël, Assche-Gilles-Van and V.-R. Keer, "Team Keccak," Team Keccak, [Online]. Available: https://keccak.team. [Accessed 31 Tháng 5 2026].  
[13] U. Banerjee, T. S. Ukyab, and A. P. Chandrakasan, “Sapphire: A configurable crypto-processor for post-quantum lattice-based protocols (extended version),” in Proc. IACR, 2019, p. 1140.  
[14] Fritzmann, Tim, Georg Sigl, and Johanna Sepúlveda. "RISQ-V: Tightly coupled RISC-V accelerators for post-quantum cryptography." IACR Transactions on Cryptographic Hardware and Embedded Systems (2020): 239-280.  
[15] Bisheh-Niasar-Mojtaba, Azarderakhsh-Reza and Mozaffari-Kermani-Mehran, "Instruction-Set Accelerated Implementation of CRYSTALS-Kyber," IEEE Transactions on Circuits and Systems I: Regular Papers, vol. 68, no. 11, pp. 4648-4659, 2021.





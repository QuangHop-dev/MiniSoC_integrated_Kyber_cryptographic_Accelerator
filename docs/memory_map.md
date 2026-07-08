# Kyber SoC Memory Map

This file defines the address map used by the Kyber-512 RISC-V SoC. The layout uses fixed 64 KiB peripheral slots so the firmware and RTL can share one stable memory map.

## System Address Map

| Region | Base | End | Slot Size | Phase-1 Status | Notes |
|---|---:|---:|---:|---|---|
| Boot ROM / IMEM slot | `0x0000_0000` | `0x0000_7FFF` | 32 KiB implemented | Implemented | Bootloader mode uses 16 KiB ROM at `0x0000_0000..0x0000_3FFF` and 16 KiB writable IMEM at `0x0000_4000..0x0000_7FFF`. |
| SRAM | `0x0001_0000` | `0x0001_3FFF` | 16 KiB implemented | Implemented | Runtime `.data`, `.bss`, heap and stack for current demos. |
| GPIO0 | `0x0002_0000` | `0x0002_FFFF` | 64 KiB | Implemented | Current `gpio_wb` instance. |
| GPIO1 | `0x0003_0000` | `0x0003_FFFF` | 64 KiB | Implemented | Second instance of `gpio_wb`. |
| I2C | `0x0004_0000` | `0x0004_FFFF` | 64 KiB | Implemented | Open-drain master with OpenCores-style registers. |
| PIC | `0x0005_0000` | `0x0005_FFFF` | 64 KiB | Implemented | Interrupt pending/enable/raw registers. |
| TIMER | `0x0006_0000` | `0x0006_FFFF` | 64 KiB | Implemented | Timer counter/compare/status registers. |
| UART | `0x0007_0000` | `0x0007_FFFF` | 64 KiB | Implemented | 32-byte TX/RX FIFOs, configurable frame format and interrupts. |
| Kyber | `0x0008_0000` | `0x0008_FFFF` | 64 KiB | Implemented | Kyber512 accelerator and data window. |

Unmapped addresses must return a Wishbone error response. Reserved slots should
also return a Wishbone error until their slave modules are added.

## Existing Peripheral Register Offsets

### GPIO0

Base: `0x0002_0000`

| Offset | Name | Access | Notes |
|---:|---|---|---|
| `0x00` | `IO_DIR` | R/W | Direction: 0 input, 1 output. |
| `0x04` | `IO_VAL` | R/W | Output latch for outputs, synchronized input value for inputs. |
| `0x08` | `INT_ENABLE` | R/W | Per-bit interrupt enable. |
| `0x0C` | `INT_TYPE` | R/W | 0 level-triggered, 1 edge-triggered. |
| `0x10` | `INT_METHOD` | R/W | 0 low/falling, 1 high/rising. |
| `0x14` | `INT_STATUS` | R/W1C | Latched per-bit interrupt status. |
| `0x1C` | `GPIO_SET_BIT` | W | Set output bits. |
| `0x20` | `GPIO_CLEAR_BIT` | W | Clear output bits. |

### PIC

Base: `0x0005_0000`

| Offset | Name | Access | Notes |
|---:|---|---|---|
| `0x00` | `PIC_STATUS` | R/W1C | Latched pending interrupts. |
| `0x04` | `ENABLE` | R/W | Interrupt enable mask. |
| `0x08` | `RAW` | R | Raw interrupt input lines; local extension for debug. |

### TIMER

Base: `0x0006_0000`

| Offset | Name | Access | Notes |
|---:|---|---|---|
| `0x00` | `CTRL` | R/W | Bit 0 enable, bit 1 count down, bit 2 IRQ enable, bit 3 auto-reload, bit 4 prescaler enable. |
| `0x04` | `COUNT` | R/W | 16-bit current counter value. |
| `0x08` | `PERIOD` | R/W | 16-bit period compare value. |
| `0x0C` | `STATUS` | R/C | Bit 0 period, bit 1 overflow, bit 2 underflow; read clears. |
| `0x10` | `PRESCALER` | R/W | 16-bit prescaler value. |

### UART

Base: `0x0007_0000`

| Offset | Name | Access | Notes |
|---:|---|---|---|
| `0x00` | `TX_BUFFER` | W | Write one byte to the 32-byte TX FIFO. |
| `0x04` | `RX_BUFFER` | R | Read one byte from the 32-byte RX FIFO. |
| `0x08` | `CONTROL` | R/W | Bit 7 enable, bit 6 clear TX FIFO, bit 5 clear RX FIFO, bits 4:3 parity, bit 2 stop bits, bits 1:0 data bits. |
| `0x0C` | `STATUS` | R/C | TX/RX FIFO and error status; read clears error flags. |
| `0x10` | `AVAILABLE_TX` | R | TX FIFO byte count. |
| `0x14` | `AVAILABLE_RX` | R | RX FIFO byte count. |
| `0x18` | `INT_STATUS` | R | UART interrupt status. |
| `0x1C` | `INT_ENABLE` | R/W | UART interrupt enable. |
| `0x20` | `DIV` | R/W | 16x baud divider, `clk/(16*baudrate)`. |

### I2C

Base: `0x0004_0000`

| Offset | Name | Access | Notes |
|---:|---|---|---|
| `0x00` | `PRERlo` | R/W | Prescaler low byte. |
| `0x01` | `PRERhi` | R/W | Prescaler high byte. |
| `0x02` | `CTR` | R/W | Bit 7 enable, bit 6 interrupt enable. |
| `0x03` | `TXR/RXR` | W/R | Transmit or receive byte. |
| `0x04` | `CR/SR` | W/R | Command or status register. |

## Planned Kyber Register/Data Map

Base: `0x0008_0000`

The Kyber512 FSM already uses fixed external byte offsets internally:

| Data Window | Offset | Size | Source |
|---|---:|---:|---|
| Public key `PK` | `0x0000` | 800 bytes | `PK_EXT_BASE = 0` |
| Secret key `SK` | `0x07D0` | 1632 bytes | `SK_EXT_BASE = 2000` |
| Ciphertext `CT` | `0x1770` | 768 bytes | `CT_EXT_BASE = 6000` |
| Shared secret `SS` | `0x1F40` | 32 bytes | `SS_EXT_BASE = 8000` |
| Seed input | `0x3000` | 64 bytes | Wrapper-owned seed register file. |

The wrapper CSR area starts at `0x4000`:

| Offset | Name | Access | Bits |
|---:|---|---|---|
| `0x4000` | `CTRL` | R/W | Bit 0 start pulse, bits `[2:1]` opcode, bit 8 soft reset. |
| `0x4004` | `STATUS` | R | Bit 0 busy, bit 1 done, bit 2 error, bits `[15:8]` `state_dbg`. |
| `0x4008` | `IRQ_ENABLE` | R/W | Bit 0 done interrupt enable. |
| `0x400C` | `IRQ_STATUS` | R/W1C | Bit 0 done interrupt status. |
| `0x4010` | `CYCLE_COUNT` | R | Optional operation cycle counter. |

Kyber opcodes:

| Opcode | Operation |
|---:|---|
| `0b01` | Key generation |
| `0b10` | Encapsulation |
| `0b11` | Decapsulation |

Software should write the 64-byte seed window before key generation and
encapsulation. Decapsulation consumes `SK` and `CT`, then writes `SS`.

#ifndef SOC_MEMORY_MAP_H
#define SOC_MEMORY_MAP_H

#include <stdint.h>

#define SOC_SLOT_SIZE          0x00010000u

#define SOC_BOOT_BASE          0x00000000u
#define SOC_BOOT_BYTES         0x00008000u
#define SOC_BOOT_ROM_BYTES     0x00004000u
#define SOC_IMEM_BASE          (SOC_BOOT_BASE + SOC_BOOT_ROM_BYTES)
#define SOC_IMEM_BYTES         (SOC_BOOT_BYTES - SOC_BOOT_ROM_BYTES)
#define SOC_SRAM_BASE          0x00010000u
#define SOC_SRAM_BYTES         0x00004000u
#define SOC_GPIO0_BASE         0x00020000u
#define SOC_GPIO1_BASE         0x00030000u
#define SOC_I2C_BASE           0x00040000u
#define SOC_PIC_BASE           0x00050000u
#define SOC_TIMER_BASE         0x00060000u
#define SOC_UART_BASE          0x00070000u
#define SOC_KYBER_BASE         0x00080000u

#define GPIO_IO_DIR_OFFSET     0x00u
#define GPIO_IO_VAL_OFFSET     0x04u
#define GPIO_INT_ENABLE_OFFSET 0x08u
#define GPIO_INT_TYPE_OFFSET   0x0Cu
#define GPIO_INT_METHOD_OFFSET 0x10u
#define GPIO_INT_STATUS_OFFSET 0x14u
#define GPIO_SET_OFFSET        0x1Cu
#define GPIO_CLR_OFFSET        0x20u

#define PIC_STATUS_OFFSET      0x00u
#define PIC_ENABLE_OFFSET      0x04u
#define PIC_RAW_OFFSET         0x08u

#define TIMER_CTRL_OFFSET      0x00u
#define TIMER_COUNT_OFFSET     0x04u
#define TIMER_PERIOD_OFFSET    0x08u
#define TIMER_STATUS_OFFSET    0x0Cu
#define TIMER_PRESCALER_OFFSET 0x10u

#define UART_TX_BUFFER_OFFSET  0x00u
#define UART_RX_BUFFER_OFFSET  0x04u
#define UART_CONTROL_OFFSET    0x08u
#define UART_STATUS_OFFSET     0x0Cu
#define UART_AVAILABLE_TX_OFFSET 0x10u
#define UART_AVAILABLE_RX_OFFSET 0x14u
#define UART_INT_STATUS_OFFSET 0x18u
#define UART_INT_ENABLE_OFFSET 0x1Cu
#define UART_DIV_OFFSET        0x20u

#define I2C_PRER_LO_OFFSET     0x00u
#define I2C_PRER_HI_OFFSET     0x01u
#define I2C_CTR_OFFSET         0x02u
#define I2C_TXR_RXR_OFFSET     0x03u
#define I2C_CR_SR_OFFSET       0x04u

#define PIC_IRQ_GPIO0          (1u << 0)
#define PIC_IRQ_GPIO1          (1u << 1)
#define PIC_IRQ_I2C            (1u << 2)
#define PIC_IRQ_TIMER          (1u << 3)
#define PIC_IRQ_UART           (1u << 4)
#define PIC_IRQ_KYBER          (1u << 5)
#define PIC_IRQ_EXT0           (1u << 6)
#define PIC_IRQ_EXT1           (1u << 7)

#define KYBER_PK_OFFSET        0x0000u
#define KYBER_PK_BYTES         800u
#define KYBER_SK_OFFSET        0x07D0u
#define KYBER_SK_BYTES         1632u
#define KYBER_CT_OFFSET        0x1770u
#define KYBER_CT_BYTES         768u
#define KYBER_SS_OFFSET        0x1F40u
#define KYBER_SS_BYTES         32u
#define KYBER_SEED_OFFSET      0x3000u
#define KYBER_SEED_BYTES       64u

#define KYBER_CTRL_OFFSET      0x4000u
#define KYBER_STATUS_OFFSET    0x4004u
#define KYBER_IRQ_EN_OFFSET    0x4008u
#define KYBER_IRQ_STATUS_OFFSET 0x400Cu
#define KYBER_CYCLE_COUNT_OFFSET 0x4010u

#define KYBER_CTRL_START       (1u << 0)
#define KYBER_CTRL_OPCODE_SHIFT 1u
#define KYBER_CTRL_OPCODE_MASK (3u << KYBER_CTRL_OPCODE_SHIFT)
#define KYBER_CTRL_SOFT_RESET  (1u << 8)

#define KYBER_STATUS_BUSY      (1u << 0)
#define KYBER_STATUS_DONE      (1u << 1)
#define KYBER_STATUS_ERROR     (1u << 2)
#define KYBER_STATUS_STATE_SHIFT 8u

#define KYBER_OPCODE_KEYGEN    1u
#define KYBER_OPCODE_ENCAPS    2u
#define KYBER_OPCODE_DECAPS    3u

static inline volatile uint32_t *soc_reg32(uint32_t base, uint32_t offset)
{
    return (volatile uint32_t *)(uintptr_t)(base + offset);
}

#endif

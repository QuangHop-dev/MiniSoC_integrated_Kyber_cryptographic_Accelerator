#include <stdint.h>

#include "i2c.h"
#include "soc_memory_map.h"
#include "soc_platform.h"
#include "uart.h"

#define I2C_TIMEOUT 100000u

static void uart_puthex8(uint8_t value)
{
    static const char hex[] = "0123456789ABCDEF";

    uart_putc(SOC_UART_BASE, hex[(value >> 4) & 0x0fu]);
    uart_putc(SOC_UART_BASE, hex[value & 0x0fu]);
}

int main(void)
{
    uint16_t prescaler = (uint16_t)((SOC_CPU_HZ / (2u * 100000u)) - 1u);
    uint8_t found = 0u;
    uint8_t addr;

    uart_init(SOC_UART_BASE, SOC_CPU_HZ, SOC_UART_BAUD);
    uart_puts(SOC_UART_BASE, "Kyber SoC I2C scan\n");
    uart_puts(SOC_UART_BASE, "SCL=PMOD0 J55.1 SDA=PMOD0 J55.3\n");

    i2c_init(SOC_I2C_BASE, prescaler, 0);

    for (addr = 0x03u; addr <= 0x77u; addr++) {
        int ret = i2c_write_cmd(SOC_I2C_BASE, (uint8_t)(addr << 1),
                                I2C_CMD_START | I2C_CMD_STOP,
                                I2C_TIMEOUT);
        if (ret == 0) {
            uart_puts(SOC_UART_BASE, "ACK 0x");
            uart_puthex8(addr);
            uart_puts(SOC_UART_BASE, "\n");
            found++;
        }
    }

    if (found == 0u) {
        uart_puts(SOC_UART_BASE, "No I2C device ACKed\n");
    } else {
        uart_puts(SOC_UART_BASE, "Found ");
        uart_puthex8(found);
        uart_puts(SOC_UART_BASE, " device(s)\n");
    }

    for (;;)
        ;
}

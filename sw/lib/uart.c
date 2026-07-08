#include "uart.h"
#include "soc_memory_map.h"
#include "soc_mmio.h"

void uart_init_div(uint32_t base, uint16_t baud_div)
{
    uint32_t div = baud_div ? baud_div : 1u;
    mmio_write32(base + UART_CONTROL_OFFSET, UART_CTRL_ENABLE |
                                        UART_CTRL_TX_CLEAR |
                                        UART_CTRL_RX_CLEAR |
                                        UART_CTRL_DATA_8);
    mmio_write32(base + UART_DIV_OFFSET, div);
    mmio_write32(base + UART_CONTROL_OFFSET, UART_CTRL_ENABLE | UART_CTRL_DATA_8);
}

void uart_init(uint32_t base, uint32_t clk_hz, uint32_t baud)
{
    uint32_t denom = 16u * baud;
    uint32_t div = 1u;

    if (denom != 0u)
        div = clk_hz / denom;
    if (div == 0u)
        div = 1u;
    if (div > 0xffffu)
        div = 0xffffu;

    uart_init_div(base, (uint16_t)div);
}

uint32_t uart_status(uint32_t base)
{
    return mmio_read32(base + UART_STATUS_OFFSET) & 0xffu;
}

int uart_getc(uint32_t base)
{
    if (uart_status(base) & UART_STATUS_RX_EMPTY)
        return -1;
    return (int)(mmio_read32(base + UART_RX_BUFFER_OFFSET) & 0xffu);
}

void uart_putc(uint32_t base, char c)
{
    while (uart_status(base) & UART_STATUS_TX_FULL) {
    }
    mmio_write32(base + UART_TX_BUFFER_OFFSET, (uint32_t)(uint8_t)c);
}

void uart_puts(uint32_t base, const char *s)
{
    while (*s != '\0') {
        if (*s == '\n')
            uart_putc(base, '\r');
        uart_putc(base, *s);
        s++;
    }
}

void uart_puthex32(uint32_t base, uint32_t value)
{
    static const char hex[] = "0123456789abcdef";
    int i;

    uart_puts(base, "0x");
    for (i = 7; i >= 0; i--)
        uart_putc(base, hex[(value >> ((uint32_t)i << 2)) & 0xfu]);
}

void uart_wait_tx_idle(uint32_t base)
{
    uint32_t status;

    do {
        status = uart_status(base);
    } while (((status & UART_STATUS_TX_EMPTY) == 0u) ||
             ((status & UART_STATUS_TX_BUSY) != 0u));
}

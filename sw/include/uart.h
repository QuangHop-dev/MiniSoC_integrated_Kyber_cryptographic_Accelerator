#ifndef UART_H
#define UART_H

#include <stdint.h>

#define UART_CTRL_DATA_8       0x03u
#define UART_CTRL_TWO_STOP     (1u << 2)
#define UART_CTRL_PARITY_EVEN  (1u << 3)
#define UART_CTRL_PARITY_ODD   (2u << 3)
#define UART_CTRL_RX_CLEAR     (1u << 5)
#define UART_CTRL_TX_CLEAR     (1u << 6)
#define UART_CTRL_ENABLE       (1u << 7)

#define UART_STATUS_FRAMING    (1u << 0)
#define UART_STATUS_OVERRUN    (1u << 1)
#define UART_STATUS_PARITY     (1u << 2)
#define UART_STATUS_TX_EMPTY   (1u << 3)
#define UART_STATUS_TX_FULL    (1u << 4)
#define UART_STATUS_RX_EMPTY   (1u << 5)
#define UART_STATUS_RX_FULL    (1u << 6)
#define UART_STATUS_TX_BUSY    (1u << 7)

void uart_init_div(uint32_t base, uint16_t baud_div);
void uart_init(uint32_t base, uint32_t clk_hz, uint32_t baud);
uint32_t uart_status(uint32_t base);
int uart_getc(uint32_t base);
void uart_putc(uint32_t base, char c);
void uart_puts(uint32_t base, const char *s);
void uart_puthex32(uint32_t base, uint32_t value);
void uart_wait_tx_idle(uint32_t base);

#endif

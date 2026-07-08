#include <stdint.h>

#include "gpio.h"
#include "i2c.h"
#include "irq.h"
#include "pic.h"
#include "soc_memory_map.h"
#include "soc_mmio.h"
#include "soc_platform.h"
#include "timer.h"
#include "uart.h"

#define UART_IRQ_RX_DATA       (1u << 5)
#define I2C_SLAVE_ADDR         0x50u
#define I2C_MEMORY_ADDR        0x12u
#define I2C_TEST_DATA          0x5au
#define IO_TIMEOUT             1000000u

static volatile uint32_t timer_seen;
static volatile uint32_t gpio_seen;
static volatile uint32_t uart_a_seen;
static volatile uint32_t uart_d_seen;
static volatile uint32_t uart_unexpected;

static void marker(uint8_t value)
{
    gpio_write(SOC_GPIO0_BASE, value);
}

static void fail(uint8_t value)
{
    irq_global_disable();
    marker(value);
    for (;;) {
    }
}

static void uart_wait_idle(void)
{
    while (uart_status(SOC_UART_BASE) & UART_STATUS_TX_BUSY) {
    }
}

static int i2c_memory_test(void)
{
    uint8_t value = 0u;
    uint8_t addr_write = (uint8_t)(I2C_SLAVE_ADDR << 1);
    uint8_t addr_read = (uint8_t)(addr_write | 1u);

    if (i2c_write_cmd(SOC_I2C_BASE, addr_write, I2C_CMD_START,
                      IO_TIMEOUT) != 0)
        return -1;
    if (i2c_write_cmd(SOC_I2C_BASE, I2C_MEMORY_ADDR, 0u,
                      IO_TIMEOUT) != 0)
        return -2;
    if (i2c_write_cmd(SOC_I2C_BASE, I2C_TEST_DATA, I2C_CMD_STOP,
                      IO_TIMEOUT) != 0)
        return -3;

    if (i2c_write_cmd(SOC_I2C_BASE, addr_write, I2C_CMD_START,
                      IO_TIMEOUT) != 0)
        return -4;
    if (i2c_write_cmd(SOC_I2C_BASE, I2C_MEMORY_ADDR, 0u,
                      IO_TIMEOUT) != 0)
        return -5;
    if (i2c_write_cmd(SOC_I2C_BASE, addr_read, I2C_CMD_START,
                      IO_TIMEOUT) != 0)
        return -6;
    if (i2c_read_cmd(SOC_I2C_BASE, I2C_CMD_STOP | I2C_CMD_ACK,
                     IO_TIMEOUT, &value) != 0)
        return -7;

    return (value == I2C_TEST_DATA) ? 0 : -8;
}

void soc_irq_handler(void)
{
    uint32_t pending = pic_pending(SOC_PIC_BASE);

    if (pending & PIC_IRQ_UART) {
        int value;

        while ((value = uart_getc(SOC_UART_BASE)) >= 0) {
            if (value == 'A') {
                uart_putc(SOC_UART_BASE, 'B');
                uart_a_seen++;
            } else if (value == 'D') {
                uart_putc(SOC_UART_BASE, 'E');
                uart_d_seen++;
            } else {
                uart_unexpected++;
            }
        }
    }
    if (pending & PIC_IRQ_TIMER) {
        timer_stop(SOC_TIMER_BASE);
        timer_clear(SOC_TIMER_BASE, 0xffffu);
        timer_seen++;
    }
    if (pending & PIC_IRQ_GPIO1) {
        uint32_t status = gpio_irq_status(SOC_GPIO1_BASE);

        gpio_irq_clear(SOC_GPIO1_BASE, status);
        gpio_seen++;
    }
    pic_clear(SOC_PIC_BASE, pending);
}

int main(void)
{
    uint16_t i2c_prescaler =
        (uint16_t)((SOC_CPU_HZ / (2u * 100000u)) - 1u);

    gpio_set_dir(SOC_GPIO0_BASE, 0xffu);
    gpio_set_dir(SOC_GPIO1_BASE, 0x00u);
    pic_clear(SOC_PIC_BASE, 0xffffffffu);

    marker(0x11u);
    if ((gpio_get_dir(SOC_GPIO0_BASE) != 0xffu) ||
        (gpio_read(SOC_GPIO0_BASE) != 0x11u))
        fail(0xe1u);

    uart_init(SOC_UART_BASE, SOC_CPU_HZ, 115200u);
    marker(0x20u);
    uart_putc(SOC_UART_BASE, 'H');
    uart_putc(SOC_UART_BASE, 'i');
    uart_wait_idle();
    marker(0x22u);

    pic_enable(SOC_PIC_BASE, PIC_IRQ_UART);
    mmio_write32(SOC_UART_BASE + UART_INT_ENABLE_OFFSET, UART_IRQ_RX_DATA);
    irq_global_enable();
    marker(0x31u);
    while (uart_a_seen == 0u) {
    }
    uart_wait_idle();
    mmio_write32(SOC_UART_BASE + UART_INT_ENABLE_OFFSET, 0u);
    if (uart_unexpected != 0u)
        fail(0xe3u);
    marker(0x32u);

    i2c_init(SOC_I2C_BASE, i2c_prescaler, 0);
    marker(0x41u);
    if (i2c_memory_test() != 0)
        fail(0xe4u);
    marker(0x42u);

    pic_clear(SOC_PIC_BASE, 0xffffffffu);
    pic_enable(SOC_PIC_BASE, PIC_IRQ_TIMER);
    marker(0x51u);
    timer_start(SOC_TIMER_BASE, 0u, 63u, 0u, TIMER_CTRL_IRQ_ENABLE);
    while (timer_seen == 0u) {
    }
    marker(0x52u);

    gpio_irq_config(SOC_GPIO1_BASE, 0x01u, 0x01u, 0x01u);
    pic_clear(SOC_PIC_BASE, 0xffffffffu);
    pic_enable(SOC_PIC_BASE, PIC_IRQ_GPIO1);
    marker(0x61u);
    while (gpio_seen == 0u) {
    }
    marker(0x62u);

    pic_enable(SOC_PIC_BASE, 0u);
    uart_init(SOC_UART_BASE, SOC_CPU_HZ, 9600u);
    marker(0x71u);
    uart_putc(SOC_UART_BASE, 'C');
    uart_wait_idle();
    marker(0x72u);

    pic_clear(SOC_PIC_BASE, 0xffffffffu);
    pic_enable(SOC_PIC_BASE, PIC_IRQ_UART);
    mmio_write32(SOC_UART_BASE + UART_INT_ENABLE_OFFSET, UART_IRQ_RX_DATA);
    marker(0x81u);
    while (uart_d_seen == 0u) {
    }
    uart_wait_idle();
    mmio_write32(SOC_UART_BASE + UART_INT_ENABLE_OFFSET, 0u);
    if (uart_unexpected != 0u)
        fail(0xe8u);
    marker(0x82u);

    irq_global_disable();
    pic_enable(SOC_PIC_BASE, 0u);
    marker(0xa5u);
    for (;;) {
    }
}

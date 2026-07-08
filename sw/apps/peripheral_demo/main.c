#include <stdint.h>

#include "gpio.h"
#include "irq.h"
#include "lcd_i2c.h"
#include "pic.h"
#include "soc_memory_map.h"
#include "soc_platform.h"
#include "timer.h"
#include "uart.h"

#define LCD_ADDRESS 0x27u

static volatile uint32_t timer_irq_count;
static volatile uint32_t gpio_irq_count;

static void uart_put_u32(uint32_t value)
{
    char buf[11];
    int i = 0;

    if (value == 0u) {
        uart_putc(SOC_UART_BASE, '0');
        return;
    }
    while ((value != 0u) && (i < 10)) {
        buf[i++] = (char)('0' + (value % 10u));
        value /= 10u;
    }
    while (i != 0)
        uart_putc(SOC_UART_BASE, buf[--i]);
}

void soc_irq_handler(void)
{
    uint32_t pending = pic_pending(SOC_PIC_BASE);

    if (pending & PIC_IRQ_TIMER) {
        timer_clear(SOC_TIMER_BASE, 0xffffu);
        timer_irq_count++;
        gpio_write(SOC_GPIO0_BASE, timer_irq_count);
    }
    if (pending & PIC_IRQ_GPIO1) {
        uint32_t status = gpio_irq_status(SOC_GPIO1_BASE);
        gpio_irq_clear(SOC_GPIO1_BASE, status);
        gpio_irq_count++;
    }
    pic_clear(SOC_PIC_BASE, pending);
}

int main(void)
{
    lcd_i2c_t lcd;
    uint32_t last_switches = 0xffffffffu;
    uint32_t last_timer_count = 0xffffffffu;
    uint32_t last_gpio_count = 0xffffffffu;
    uint16_t i2c_prescaler =
        (uint16_t)((SOC_CPU_HZ / (2u * 100000u)) - 1u);

    uart_init(SOC_UART_BASE, SOC_CPU_HZ, SOC_UART_BAUD);
    uart_puts(SOC_UART_BASE, "Kyber SoC peripheral demo\n");

    gpio_set_dir(SOC_GPIO0_BASE, 0xffu);
    gpio_write(SOC_GPIO0_BASE, 0u);
    gpio_set_dir(SOC_GPIO1_BASE, 0u);
    gpio_irq_config(SOC_GPIO1_BASE, 0xffu, 0xffu, 0xffu);

    pic_clear(SOC_PIC_BASE, 0xffffffffu);
    pic_enable(SOC_PIC_BASE, PIC_IRQ_GPIO1 | PIC_IRQ_TIMER);

    timer_start(SOC_TIMER_BASE, 0u, 999u,
                (uint16_t)((SOC_CPU_HZ / 10000u) - 1u),
                TIMER_CTRL_IRQ_ENABLE | TIMER_CTRL_AUTO_RELOAD |
                TIMER_CTRL_PRESCALER);

    if (lcd_i2c_init(&lcd, SOC_I2C_BASE, LCD_ADDRESS, i2c_prescaler) == 0) {
        lcd_i2c_puts(&lcd, "Kyber SoC ready");
        lcd_i2c_set_cursor(&lcd, 0u, 1u);
        lcd_i2c_puts(&lcd, "IRQ + GPIO + I2C");
        uart_puts(SOC_UART_BASE, "LCD I2C ready\n");
    } else {
        uart_puts(SOC_UART_BASE, "LCD I2C not detected; continuing\n");
    }

    irq_global_enable();

    for (;;) {
        uint32_t switches = gpio_read(SOC_GPIO1_BASE) & 0xffu;

        if ((switches != last_switches) ||
            (timer_irq_count != last_timer_count) ||
            (gpio_irq_count != last_gpio_count)) {
            uart_puts(SOC_UART_BASE, "GPIO1=");
            uart_puthex32(SOC_UART_BASE, switches);
            uart_puts(SOC_UART_BASE, " timer_irq=");
            uart_put_u32(timer_irq_count);
            uart_puts(SOC_UART_BASE, " gpio_irq=");
            uart_put_u32(gpio_irq_count);
            uart_puts(SOC_UART_BASE, "\n");
            last_switches = switches;
            last_timer_count = timer_irq_count;
            last_gpio_count = gpio_irq_count;
        }
    }
}

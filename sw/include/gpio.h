#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>

void gpio_set_dir(uint32_t base, uint32_t mask);
uint32_t gpio_get_dir(uint32_t base);
void gpio_write(uint32_t base, uint32_t value);
uint32_t gpio_read(uint32_t base);
void gpio_set(uint32_t base, uint32_t mask);
void gpio_clear(uint32_t base, uint32_t mask);
void gpio_irq_config(uint32_t base, uint32_t enable, uint32_t edge_mask, uint32_t high_or_rising_mask);
uint32_t gpio_irq_status(uint32_t base);
void gpio_irq_clear(uint32_t base, uint32_t mask);

#endif

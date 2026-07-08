#include "gpio.h"
#include "soc_memory_map.h"
#include "soc_mmio.h"

void gpio_set_dir(uint32_t base, uint32_t mask)
{
    mmio_write32(base + GPIO_IO_DIR_OFFSET, mask);
}

uint32_t gpio_get_dir(uint32_t base)
{
    return mmio_read32(base + GPIO_IO_DIR_OFFSET);
}

void gpio_write(uint32_t base, uint32_t value)
{
    mmio_write32(base + GPIO_IO_VAL_OFFSET, value);
}

uint32_t gpio_read(uint32_t base)
{
    return mmio_read32(base + GPIO_IO_VAL_OFFSET);
}

void gpio_set(uint32_t base, uint32_t mask)
{
    mmio_write32(base + GPIO_SET_OFFSET, mask);
}

void gpio_clear(uint32_t base, uint32_t mask)
{
    mmio_write32(base + GPIO_CLR_OFFSET, mask);
}

void gpio_irq_config(uint32_t base, uint32_t enable, uint32_t edge_mask, uint32_t high_or_rising_mask)
{
    mmio_write32(base + GPIO_INT_ENABLE_OFFSET, 0u);
    mmio_write32(base + GPIO_INT_TYPE_OFFSET, edge_mask);
    mmio_write32(base + GPIO_INT_METHOD_OFFSET, high_or_rising_mask);
    mmio_write32(base + GPIO_INT_STATUS_OFFSET, 0xffffffffu);
    mmio_write32(base + GPIO_INT_ENABLE_OFFSET, enable);
}

uint32_t gpio_irq_status(uint32_t base)
{
    return mmio_read32(base + GPIO_INT_STATUS_OFFSET);
}

void gpio_irq_clear(uint32_t base, uint32_t mask)
{
    mmio_write32(base + GPIO_INT_STATUS_OFFSET, mask);
}

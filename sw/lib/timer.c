#include "timer.h"
#include "soc_memory_map.h"
#include "soc_mmio.h"

void timer_stop(uint32_t base)
{
    mmio_write32(base + TIMER_CTRL_OFFSET, 0u);
}

void timer_start(uint32_t base, uint16_t count, uint16_t period, uint16_t prescaler, uint32_t control)
{
    timer_stop(base);
    mmio_write32(base + TIMER_COUNT_OFFSET, count);
    mmio_write32(base + TIMER_PERIOD_OFFSET, period);
    mmio_write32(base + TIMER_PRESCALER_OFFSET, prescaler);
    mmio_write32(base + TIMER_STATUS_OFFSET, 0xffffu);
    mmio_write32(base + TIMER_CTRL_OFFSET, control | TIMER_CTRL_ENABLE);
}

uint16_t timer_count(uint32_t base)
{
    return (uint16_t)mmio_read32(base + TIMER_COUNT_OFFSET);
}

uint16_t timer_status(uint32_t base)
{
    return (uint16_t)mmio_read32(base + TIMER_STATUS_OFFSET);
}

void timer_clear(uint32_t base, uint16_t mask)
{
    mmio_write32(base + TIMER_STATUS_OFFSET, mask);
}

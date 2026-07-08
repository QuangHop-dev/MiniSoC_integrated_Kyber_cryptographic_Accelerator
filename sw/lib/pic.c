#include "pic.h"
#include "soc_memory_map.h"
#include "soc_mmio.h"

void pic_enable(uint32_t base, uint32_t mask)
{
    mmio_write32(base + PIC_ENABLE_OFFSET, mask);
}

uint32_t pic_enabled(uint32_t base)
{
    return mmio_read32(base + PIC_ENABLE_OFFSET);
}

uint32_t pic_pending(uint32_t base)
{
    return mmio_read32(base + PIC_STATUS_OFFSET);
}

uint32_t pic_raw(uint32_t base)
{
    return mmio_read32(base + PIC_RAW_OFFSET);
}

void pic_clear(uint32_t base, uint32_t mask)
{
    mmio_write32(base + PIC_STATUS_OFFSET, mask);
}

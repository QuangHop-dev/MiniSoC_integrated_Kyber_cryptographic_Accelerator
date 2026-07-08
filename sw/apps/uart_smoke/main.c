#include <stdint.h>

#include "soc_memory_map.h"
#include "soc_mmio.h"

int main(void)
{
    mmio_write32(SOC_GPIO0_BASE + GPIO_IO_DIR_OFFSET, 0xffu);
    mmio_write32(SOC_GPIO0_BASE + GPIO_IO_VAL_OFFSET, 0xa5u);

    for (;;) {
    }
}

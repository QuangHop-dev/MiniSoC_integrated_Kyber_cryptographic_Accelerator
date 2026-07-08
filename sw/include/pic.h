#ifndef PIC_H
#define PIC_H

#include <stdint.h>
#include "soc_memory_map.h"

void pic_enable(uint32_t base, uint32_t mask);
uint32_t pic_enabled(uint32_t base);
uint32_t pic_pending(uint32_t base);
uint32_t pic_raw(uint32_t base);
void pic_clear(uint32_t base, uint32_t mask);

#endif

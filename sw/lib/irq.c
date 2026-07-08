#include "irq.h"
#include "pic.h"
#include "soc_memory_map.h"

void irq_global_enable(void)
{
    uint32_t mask = 1u << 11;

    __asm__ volatile ("csrs mie, %0" : : "r"(mask) : "memory");
    mask = 1u << 3;
    __asm__ volatile ("csrs mstatus, %0" : : "r"(mask) : "memory");
}

void irq_global_disable(void)
{
    uint32_t mask = 1u << 3;

    __asm__ volatile ("csrc mstatus, %0" : : "r"(mask) : "memory");
}

uint32_t irq_mcause(void)
{
    uint32_t value;

    __asm__ volatile ("csrr %0, mcause" : "=r"(value));
    return value;
}

__attribute__((weak)) void soc_irq_handler(void)
{
    uint32_t pending = pic_pending(SOC_PIC_BASE);

    pic_clear(SOC_PIC_BASE, pending);
}

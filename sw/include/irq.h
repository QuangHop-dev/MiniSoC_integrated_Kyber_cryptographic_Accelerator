#ifndef IRQ_H
#define IRQ_H

#include <stdint.h>

void irq_global_enable(void);
void irq_global_disable(void);
uint32_t irq_mcause(void);
void soc_irq_handler(void);

#endif

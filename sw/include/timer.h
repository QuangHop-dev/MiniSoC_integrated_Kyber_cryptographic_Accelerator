#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

#define TIMER_CTRL_ENABLE      (1u << 0)
#define TIMER_CTRL_DOWN        (1u << 1)
#define TIMER_CTRL_IRQ_ENABLE  (1u << 2)
#define TIMER_CTRL_AUTO_RELOAD (1u << 3)
#define TIMER_CTRL_PRESCALER   (1u << 4)

#define TIMER_STATUS_MATCH     (1u << 0)
#define TIMER_STATUS_OVERFLOW  (1u << 1)
#define TIMER_STATUS_UNDERFLOW (1u << 2)

void timer_stop(uint32_t base);
void timer_start(uint32_t base, uint16_t count, uint16_t period, uint16_t prescaler, uint32_t control);
uint16_t timer_count(uint32_t base);
uint16_t timer_status(uint32_t base);
void timer_clear(uint32_t base, uint16_t mask);

#endif

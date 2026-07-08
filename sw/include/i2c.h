#ifndef I2C_H
#define I2C_H

#include <stdint.h>

#define I2C_CTR_ENABLE         (1u << 7)
#define I2C_CTR_IRQ_ENABLE     (1u << 6)

#define I2C_CMD_START          (1u << 7)
#define I2C_CMD_STOP           (1u << 6)
#define I2C_CMD_READ           (1u << 5)
#define I2C_CMD_WRITE          (1u << 4)
#define I2C_CMD_ACK            (1u << 3)
#define I2C_CMD_IACK           (1u << 0)

#define I2C_STATUS_RXACK       (1u << 7)
#define I2C_STATUS_BUSY        (1u << 6)
#define I2C_STATUS_ARB_LOST    (1u << 5)
#define I2C_STATUS_TIP         (1u << 1)
#define I2C_STATUS_IRQ         (1u << 0)

void i2c_init(uint32_t base, uint16_t prescaler, int irq_enable);
uint8_t i2c_status(uint32_t base);
void i2c_irq_clear(uint32_t base);
int i2c_wait_idle(uint32_t base, uint32_t timeout);
int i2c_write_cmd(uint32_t base, uint8_t data, uint8_t command, uint32_t timeout);
int i2c_read_cmd(uint32_t base, uint8_t command, uint32_t timeout, uint8_t *data);

#endif

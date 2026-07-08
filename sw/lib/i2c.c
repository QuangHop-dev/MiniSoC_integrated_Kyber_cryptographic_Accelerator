#include "i2c.h"
#include "soc_memory_map.h"
#include "soc_mmio.h"

static uint8_t i2c_read_reg(uint32_t base, uint32_t offset)
{
    return mmio_read8(base + offset);
}

static void i2c_write_reg(uint32_t base, uint32_t offset, uint8_t value)
{
    mmio_write8(base + offset, value);
}

void i2c_init(uint32_t base, uint16_t prescaler, int irq_enable)
{
    i2c_write_reg(base, I2C_CTR_OFFSET, 0u);
    i2c_write_reg(base, I2C_PRER_LO_OFFSET, (uint8_t)prescaler);
    i2c_write_reg(base, I2C_PRER_HI_OFFSET, (uint8_t)(prescaler >> 8));
    i2c_write_reg(base, I2C_CTR_OFFSET, I2C_CTR_ENABLE |
                                      (irq_enable ? I2C_CTR_IRQ_ENABLE : 0u));
}

uint8_t i2c_status(uint32_t base)
{
    return i2c_read_reg(base, I2C_CR_SR_OFFSET);
}

void i2c_irq_clear(uint32_t base)
{
    i2c_write_reg(base, I2C_CR_SR_OFFSET, I2C_CMD_IACK);
}

int i2c_wait_idle(uint32_t base, uint32_t timeout)
{
    while (i2c_status(base) & I2C_STATUS_TIP) {
        if (timeout != 0u) {
            timeout--;
            if (timeout == 0u)
                return -1;
        }
    }
    return 0;
}

int i2c_write_cmd(uint32_t base, uint8_t data, uint8_t command, uint32_t timeout)
{
    uint8_t status;

    i2c_write_reg(base, I2C_TXR_RXR_OFFSET, data);
    i2c_write_reg(base, I2C_CR_SR_OFFSET, command | I2C_CMD_WRITE);
    if (i2c_wait_idle(base, timeout) != 0)
        return -1;

    status = i2c_status(base);
    if (status & I2C_STATUS_ARB_LOST)
        return -2;
    if (status & I2C_STATUS_RXACK)
        return -3;
    return 0;
}

int i2c_read_cmd(uint32_t base, uint8_t command, uint32_t timeout, uint8_t *data)
{
    uint8_t status;

    if (data == 0)
        return -4;

    i2c_write_reg(base, I2C_CR_SR_OFFSET, command | I2C_CMD_READ);
    if (i2c_wait_idle(base, timeout) != 0)
        return -1;

    status = i2c_status(base);
    if (status & I2C_STATUS_ARB_LOST)
        return -2;

    *data = i2c_read_reg(base, I2C_TXR_RXR_OFFSET);
    return 0;
}

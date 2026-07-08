#include "kyber.h"
#include "soc_mmio.h"

static uint32_t pack_le32(const uint8_t *data, size_t len)
{
    uint32_t value = 0u;
    size_t i;

    for (i = 0; i < len; i++)
        value |= ((uint32_t)data[i]) << ((uint32_t)i << 3);
    return value;
}

static void unpack_le32(uint32_t value, uint8_t *data, size_t len)
{
    size_t i;

    for (i = 0; i < len; i++)
        data[i] = (uint8_t)(value >> ((uint32_t)i << 3));
}

void kyber_soft_reset(void)
{
    mmio_write32(SOC_KYBER_BASE + KYBER_CTRL_OFFSET, KYBER_CTRL_SOFT_RESET);
    mmio_barrier();
}

void kyber_irq_enable(int enable)
{
    mmio_write32(SOC_KYBER_BASE + KYBER_IRQ_EN_OFFSET, enable ? 1u : 0u);
}

uint32_t kyber_status(void)
{
    return mmio_read32(SOC_KYBER_BASE + KYBER_STATUS_OFFSET);
}

uint32_t kyber_cycle_count(void)
{
    return mmio_read32(SOC_KYBER_BASE + KYBER_CYCLE_COUNT_OFFSET);
}

void kyber_write_region(uint32_t offset, const uint8_t *data, size_t len)
{
    size_t pos = 0u;

    while (pos < len) {
        size_t chunk = len - pos;
        uint32_t addr = SOC_KYBER_BASE + offset + (uint32_t)pos;
        uint32_t value;

        if (chunk > 4u)
            chunk = 4u;
        value = pack_le32(&data[pos], chunk);
        if (chunk != 4u) {
            uint32_t keep = 0xffffffffu << ((uint32_t)chunk << 3);
            value = (mmio_read32(addr) & keep) | value;
        }
        mmio_write32(addr, value);
        pos += chunk;
    }
}

void kyber_read_region(uint32_t offset, uint8_t *data, size_t len)
{
    size_t pos = 0u;

    while (pos < len) {
        size_t chunk = len - pos;
        uint32_t addr = SOC_KYBER_BASE + offset + (uint32_t)pos;
        uint32_t value;

        if (chunk > 4u)
            chunk = 4u;
        value = mmio_read32(addr);
        unpack_le32(value, &data[pos], chunk);
        pos += chunk;
    }
}

void kyber_write_seed(const uint8_t seed[KYBER_SEED_BYTES])
{
    kyber_write_region(KYBER_SEED_OFFSET, seed, KYBER_SEED_BYTES);
}

void kyber_start(uint32_t opcode)
{
    uint32_t ctrl = KYBER_CTRL_START |
                    ((opcode << KYBER_CTRL_OPCODE_SHIFT) & KYBER_CTRL_OPCODE_MASK);
    mmio_write32(SOC_KYBER_BASE + KYBER_CTRL_OFFSET, ctrl);
}

int kyber_wait_done(uint32_t timeout)
{
    for (;;) {
        uint32_t status = kyber_status();

        if (status & KYBER_STATUS_ERROR)
            return KYBER_ERR_HW;
        if (status & KYBER_STATUS_DONE) {
            mmio_write32(SOC_KYBER_BASE + KYBER_IRQ_STATUS_OFFSET, 1u);
            return KYBER_OK;
        }
        if (timeout != 0u) {
            timeout--;
            if (timeout == 0u)
                return KYBER_ERR_TIMEOUT;
        }
    }
}

int kyber_keygen(const uint8_t seed[KYBER_SEED_BYTES], uint8_t *pk, uint8_t *sk, uint32_t timeout)
{
    int ret;

    if (seed == 0)
        return KYBER_ERR_ARG;

    kyber_soft_reset();
    kyber_write_seed(seed);
    kyber_start(KYBER_OPCODE_KEYGEN);
    ret = kyber_wait_done(timeout);
    if (ret != KYBER_OK)
        return ret;

    if (pk != 0)
        kyber_read_region(KYBER_PK_OFFSET, pk, KYBER_PK_BYTES);
    if (sk != 0)
        kyber_read_region(KYBER_SK_OFFSET, sk, KYBER_SK_BYTES);
    return KYBER_OK;
}

int kyber_encaps(const uint8_t seed[KYBER_SEED_BYTES], const uint8_t *pk, uint8_t *ct, uint8_t *ss, uint32_t timeout)
{
    int ret;

    if ((seed == 0) || (pk == 0))
        return KYBER_ERR_ARG;

    kyber_soft_reset();
    kyber_write_region(KYBER_PK_OFFSET, pk, KYBER_PK_BYTES);
    kyber_write_seed(seed);
    kyber_start(KYBER_OPCODE_ENCAPS);
    ret = kyber_wait_done(timeout);
    if (ret != KYBER_OK)
        return ret;

    if (ct != 0)
        kyber_read_region(KYBER_CT_OFFSET, ct, KYBER_CT_BYTES);
    if (ss != 0)
        kyber_read_region(KYBER_SS_OFFSET, ss, KYBER_SS_BYTES);
    return KYBER_OK;
}

int kyber_decaps(const uint8_t *ct, const uint8_t *sk, uint8_t *ss, uint32_t timeout)
{
    int ret;

    if ((ct == 0) || (sk == 0))
        return KYBER_ERR_ARG;

    kyber_soft_reset();
    kyber_write_region(KYBER_SK_OFFSET, sk, KYBER_SK_BYTES);
    kyber_write_region(KYBER_CT_OFFSET, ct, KYBER_CT_BYTES);
    kyber_start(KYBER_OPCODE_DECAPS);
    ret = kyber_wait_done(timeout);
    if (ret != KYBER_OK)
        return ret;

    if (ss != 0)
        kyber_read_region(KYBER_SS_OFFSET, ss, KYBER_SS_BYTES);
    return KYBER_OK;
}

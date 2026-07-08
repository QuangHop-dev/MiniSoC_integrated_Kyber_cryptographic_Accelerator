#ifndef KYBER_H
#define KYBER_H

#include <stdint.h>
#include <stddef.h>
#include "soc_memory_map.h"

#define KYBER_OK              0
#define KYBER_ERR_TIMEOUT    -1
#define KYBER_ERR_HW         -2
#define KYBER_ERR_ARG        -3

void kyber_soft_reset(void);
void kyber_irq_enable(int enable);
uint32_t kyber_status(void);
uint32_t kyber_cycle_count(void);
void kyber_write_region(uint32_t offset, const uint8_t *data, size_t len);
void kyber_read_region(uint32_t offset, uint8_t *data, size_t len);
void kyber_write_seed(const uint8_t seed[KYBER_SEED_BYTES]);
void kyber_start(uint32_t opcode);
int kyber_wait_done(uint32_t timeout);
int kyber_keygen(const uint8_t seed[KYBER_SEED_BYTES], uint8_t *pk, uint8_t *sk, uint32_t timeout);
int kyber_encaps(const uint8_t seed[KYBER_SEED_BYTES], const uint8_t *pk, uint8_t *ct, uint8_t *ss, uint32_t timeout);
int kyber_decaps(const uint8_t *ct, const uint8_t *sk, uint8_t *ss, uint32_t timeout);

#endif

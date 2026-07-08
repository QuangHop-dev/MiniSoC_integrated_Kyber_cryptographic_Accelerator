#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "../kem.h"
#include "../params.h"
#include "cpucycles.h"
#include "speed_print.h"

#define NTESTS 10000

static uint64_t timestamps[NTESTS];
static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
static uint8_t sk[CRYPTO_SECRETKEYBYTES];
static uint8_t ct_valid[CRYPTO_CIPHERTEXTBYTES];
static uint8_t ct_invalid[CRYPTO_CIPHERTEXTBYTES];
static uint8_t ss[CRYPTO_BYTES];
static uint8_t keypair_coins[2 * KYBER_SYMBYTES];
static uint8_t encaps_coins[KYBER_SYMBYTES];

int main(void)
{
  unsigned int i;

  for(i = 0; i < sizeof(keypair_coins); i++)
    keypair_coins[i] = (uint8_t)i;
  for(i = 0; i < sizeof(encaps_coins); i++)
    encaps_coins[i] = (uint8_t)(0x80U + i);

  for(i = 0; i < NTESTS; i++) {
    timestamps[i] = cpucycles();
    crypto_kem_keypair_derand(pk, sk, keypair_coins);
  }
  print_results("keygen_derand", timestamps, NTESTS);

  crypto_kem_keypair_derand(pk, sk, keypair_coins);
  for(i = 0; i < NTESTS; i++) {
    timestamps[i] = cpucycles();
    crypto_kem_enc_derand(ct_valid, ss, pk, encaps_coins);
  }
  print_results("encaps_derand", timestamps, NTESTS);

  crypto_kem_enc_derand(ct_valid, ss, pk, encaps_coins);
  memcpy(ct_invalid, ct_valid, sizeof(ct_invalid));
  ct_invalid[0] ^= 1U;

  for(i = 0; i < NTESTS; i++) {
    timestamps[i] = cpucycles();
    crypto_kem_dec(ss, ct_valid, sk);
  }
  print_results("decaps_valid", timestamps, NTESTS);

  for(i = 0; i < NTESTS; i++) {
    timestamps[i] = cpucycles();
    crypto_kem_dec(ss, ct_invalid, sk);
  }
  print_results("decaps_invalid", timestamps, NTESTS);

  return 0;
}

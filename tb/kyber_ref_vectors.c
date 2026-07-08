#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "kem.h"
#include "params.h"
#include "randombytes.h"

static uint64_t rng_state = UINT64_C(0x123456789abcdef0);

void randombytes(uint8_t *out, size_t outlen)
{
    memset(out, 0, outlen);
}

static uint8_t next_random_byte(void)
{
    uint64_t x = rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    rng_state = x;
    return (uint8_t)((x * UINT64_C(0x2545f4914f6cdd1d)) >> 56);
}

static FILE *open_output(const char *dir, const char *name)
{
    char path[1024];
    int n = snprintf(path, sizeof(path), "%s/%s", dir, name);
    if (n < 0 || (size_t)n >= sizeof(path)) {
        fprintf(stderr, "Path too long for %s/%s\n", dir, name);
        exit(2);
    }

    FILE *fp = fopen(path, "w");
    if (fp == NULL) {
        fprintf(stderr, "Cannot open %s: %s\n", path, strerror(errno));
        exit(2);
    }
    return fp;
}

static void write_hex_bytes(FILE *fp, const uint8_t *buf, size_t len)
{
    for (size_t i = 0; i < len; i++) {
        fprintf(fp, "%02x\n", buf[i]);
    }
}

int main(int argc, char **argv)
{
    const char *out_dir;
    int num_tests = 100;

    if (argc < 2 || argc > 4) {
        fprintf(stderr, "usage: %s <out_dir> [num_tests] [rng_seed]\n", argv[0]);
        return 2;
    }

    out_dir = argv[1];

    if (argc >= 3) {
        num_tests = atoi(argv[2]);
        if (num_tests <= 0) {
            fprintf(stderr, "num_tests must be positive\n");
            return 2;
        }
    }

    if (argc >= 4) {
        rng_state = strtoull(argv[3], NULL, 0);
        if (rng_state == 0) {
            rng_state = UINT64_C(0x123456789abcdef0);
        }
    }

    FILE *seed_fp = open_output(out_dir, "seed.hex");
    FILE *pk_fp = open_output(out_dir, "pk.hex");
    FILE *sk_fp = open_output(out_dir, "sk.hex");
    FILE *ct_fp = open_output(out_dir, "ct.hex");
    FILE *ss_enc_fp = open_output(out_dir, "ss_enc.hex");
    FILE *ss_dec_fp = open_output(out_dir, "ss_dec.hex");
    FILE *manifest_fp = open_output(out_dir, "manifest.txt");

    uint8_t seed[2 * KYBER_SYMBYTES];
    uint8_t pk[CRYPTO_PUBLICKEYBYTES];
    uint8_t sk[CRYPTO_SECRETKEYBYTES];
    uint8_t ct[CRYPTO_CIPHERTEXTBYTES];
    uint8_t ss_enc[CRYPTO_BYTES];
    uint8_t ss_dec[CRYPTO_BYTES];

    for (int test = 0; test < num_tests; test++) {
        for (size_t i = 0; i < sizeof(seed); i++) {
            seed[i] = next_random_byte();
        }

        if (crypto_kem_keypair_derand(pk, sk, seed) != 0) {
            fprintf(stderr, "crypto_kem_keypair_derand failed at test %d\n", test);
            return 1;
        }

        if (crypto_kem_enc_derand(ct, ss_enc, pk, seed) != 0) {
            fprintf(stderr, "crypto_kem_enc_derand failed at test %d\n", test);
            return 1;
        }

        if (crypto_kem_dec(ss_dec, ct, sk) != 0) {
            fprintf(stderr, "crypto_kem_dec failed at test %d\n", test);
            return 1;
        }

        if (memcmp(ss_enc, ss_dec, CRYPTO_BYTES) != 0) {
            fprintf(stderr, "C reference encaps/decaps shared secret mismatch at test %d\n", test);
            return 1;
        }

        write_hex_bytes(seed_fp, seed, sizeof(seed));
        write_hex_bytes(pk_fp, pk, sizeof(pk));
        write_hex_bytes(sk_fp, sk, sizeof(sk));
        write_hex_bytes(ct_fp, ct, sizeof(ct));
        write_hex_bytes(ss_enc_fp, ss_enc, sizeof(ss_enc));
        write_hex_bytes(ss_dec_fp, ss_dec, sizeof(ss_dec));
    }

    fprintf(manifest_fp, "algorithm=Kyber512\n");
    fprintf(manifest_fp, "num_tests=%d\n", num_tests);
    fprintf(manifest_fp, "seed_bytes=%llu\n", (unsigned long long)sizeof(seed));
    fprintf(manifest_fp, "pk_bytes=%d\n", CRYPTO_PUBLICKEYBYTES);
    fprintf(manifest_fp, "sk_bytes=%d\n", CRYPTO_SECRETKEYBYTES);
    fprintf(manifest_fp, "ct_bytes=%d\n", CRYPTO_CIPHERTEXTBYTES);
    fprintf(manifest_fp, "ss_bytes=%d\n", CRYPTO_BYTES);

    fclose(seed_fp);
    fclose(pk_fp);
    fclose(sk_fp);
    fclose(ct_fp);
    fclose(ss_enc_fp);
    fclose(ss_dec_fp);
    fclose(manifest_fp);

    return 0;
}

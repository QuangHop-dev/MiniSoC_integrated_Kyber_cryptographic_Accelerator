#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "params.h"
#include "indcpa.h"
#include "poly.h"
#include "polyvec.h"
#include "symmetric.h"

static void read_hex_bytes(const char *path, uint8_t *out, size_t count)
{
    FILE *fp = fopen(path, "r");
    size_t i;
    unsigned value;
    if (fp == NULL) {
        perror(path);
        exit(2);
    }
    for (i = 0; i < count; ++i) {
        if (fscanf(fp, "%2x", &value) != 1) {
            fprintf(stderr, "Cannot read byte %zu from %s\n", i, path);
            exit(2);
        }
        out[i] = (uint8_t)value;
    }
    fclose(fp);
}

static void dump_pair(const char *name, const poly *p)
{
    printf("%s[0]=%d %s[1]=%d\n",
           name, p->coeffs[0], name, p->coeffs[1]);
    printf("%s[2]=%d %s[3]=%d\n",
           name, p->coeffs[2], name, p->coeffs[3]);
    printf("%s[254]=%d %s[255]=%d\n",
           name, p->coeffs[254], name, p->coeffs[255]);
}

int main(int argc, char **argv)
{
    uint8_t coins[2 * KYBER_SYMBYTES];
    uint8_t seedbuf[2 * KYBER_SYMBYTES];
    uint8_t nonce = 0;
    polyvec a[KYBER_K];
    polyvec s;
    polyvec e;
    poly tprime[KYBER_K];
    poly t[KYBER_K];
    unsigned i;

    if (argc != 2) {
        fprintf(stderr, "usage: %s keygen_seed.hex\n", argv[0]);
        return 2;
    }

    read_hex_bytes(argv[1], coins, sizeof(coins));
    memcpy(seedbuf, coins, KYBER_SYMBYTES);
    seedbuf[KYBER_SYMBYTES] = KYBER_K;
    hash_g(seedbuf, seedbuf, KYBER_SYMBYTES + 1);
    gen_matrix(a, seedbuf, 0);

    for (i = 0; i < KYBER_K; ++i)
        poly_getnoise_eta1(&s.vec[i], seedbuf + KYBER_SYMBYTES, nonce++);
    for (i = 0; i < KYBER_K; ++i)
        poly_getnoise_eta1(&e.vec[i], seedbuf + KYBER_SYMBYTES, nonce++);

    polyvec_ntt(&s);
    polyvec_ntt(&e);

    for (i = 0; i < KYBER_K; ++i) {
        polyvec_basemul_acc_montgomery(&tprime[i], &a[i], &s);
        poly_tomont(&tprime[i]);
        t[i] = tprime[i];
        poly_add(&t[i], &t[i], &e.vec[i]);
        poly_reduce(&t[i]);
    }

    dump_pair("s0", &s.vec[0]);
    dump_pair("s1", &s.vec[1]);
    dump_pair("e0", &e.vec[0]);
    dump_pair("e1", &e.vec[1]);
    dump_pair("a00", &a[0].vec[0]);
    dump_pair("a01", &a[0].vec[1]);
    dump_pair("a10", &a[1].vec[0]);
    dump_pair("a11", &a[1].vec[1]);
    dump_pair("tprime0", &tprime[0]);
    dump_pair("tprime1", &tprime[1]);
    dump_pair("t0", &t[0]);
    dump_pair("t1", &t[1]);
    for (unsigned p = 0; p < KYBER_K; ++p) {
        for (i = 0; i < KYBER_N; i += 2) {
            int c0 = e.vec[p].coeffs[i];
            int c1 = e.vec[p].coeffs[i + 1];
            if (c0 < 0) c0 += KYBER_Q;
            if (c1 < 0) c1 += KYBER_Q;
            if (c0 == 3129 && c1 == 2921)
                printf("e%u target pair index=%u\n", p, i / 2);
            c0 = s.vec[p].coeffs[i];
            c1 = s.vec[p].coeffs[i + 1];
            if (c0 < 0) c0 += KYBER_Q;
            if (c1 < 0) c1 += KYBER_Q;
            if ((c0 == 902 && c1 == 922) ||
                (c0 == 865 && c1 == 277))
                printf("s%u observed pair index=%u value=(%d,%d)\n",
                       p, i / 2, c0, c1);
        }
    }
    return 0;
}

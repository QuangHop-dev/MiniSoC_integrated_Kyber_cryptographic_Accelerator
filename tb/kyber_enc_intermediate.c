#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "params.h"
#include "poly.h"
#include "polyvec.h"
#include "indcpa.h"
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

static void dump_poly(const char *name, const poly *p)
{
    printf("%s: [0]=%d [1]=%d [2]=%d [3]=%d [254]=%d [255]=%d\n",
           name, p->coeffs[0], p->coeffs[1], p->coeffs[2], p->coeffs[3],
           p->coeffs[254], p->coeffs[255]);
}

int main(int argc, char **argv)
{
    uint8_t pk[KYBER_INDCPA_PUBLICKEYBYTES];
    uint8_t enc_seed[2 * KYBER_SYMBYTES];
    uint8_t buf[2 * KYBER_SYMBYTES];
    uint8_t kr[2 * KYBER_SYMBYTES];
    uint8_t seed[KYBER_SYMBYTES];
    uint8_t nonce = 0;
    polyvec sp, pkpv, ep, at[KYBER_K], b;
    poly v, k, epp;
    unsigned i;

    if (argc != 3) {
        fprintf(stderr, "usage: %s pk.hex enc_seed.hex\n", argv[0]);
        return 2;
    }

    read_hex_bytes(argv[1], pk, sizeof(pk));
    read_hex_bytes(argv[2], enc_seed, sizeof(enc_seed));
    memcpy(buf, enc_seed, KYBER_SYMBYTES);
    hash_h(buf + KYBER_SYMBYTES, pk, sizeof(pk));
    hash_g(kr, buf, sizeof(buf));

    polyvec_frombytes(&pkpv, pk);
    memcpy(seed, pk + KYBER_POLYVECBYTES, KYBER_SYMBYTES);
    poly_frommsg(&k, buf);
    gen_matrix(at, seed, 1);

    for (i = 0; i < KYBER_K; ++i)
        poly_getnoise_eta1(&sp.vec[i], kr + KYBER_SYMBYTES, nonce++);
    for (i = 0; i < KYBER_K; ++i)
        poly_getnoise_eta2(&ep.vec[i], kr + KYBER_SYMBYTES, nonce++);
    poly_getnoise_eta2(&epp, kr + KYBER_SYMBYTES, nonce++);
    polyvec_ntt(&sp);

    for (i = 0; i < KYBER_K; ++i)
        polyvec_basemul_acc_montgomery(&b.vec[i], &at[i], &sp);
    polyvec_basemul_acc_montgomery(&v, &pkpv, &sp);

    dump_poly("b0_ntt", &b.vec[0]);
    dump_poly("b1_ntt", &b.vec[1]);
    dump_poly("v_ntt", &v);

    polyvec_invntt_tomont(&b);
    poly_invntt_tomont(&v);
    dump_poly("b0_intt", &b.vec[0]);
    dump_poly("b1_intt", &b.vec[1]);

    polyvec_add(&b, &b, &ep);
    poly_add(&v, &v, &epp);
    poly_add(&v, &v, &k);
    polyvec_reduce(&b);
    poly_reduce(&v);

    dump_poly("u0", &b.vec[0]);
    dump_poly("u1", &b.vec[1]);
    dump_poly("v", &v);
    return 0;
}

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "params.h"
#include "poly.h"
#include "polyvec.h"

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
    uint8_t sk[KYBER_INDCPA_SECRETKEYBYTES];
    uint8_t ct[KYBER_INDCPA_BYTES];
    uint8_t msg[KYBER_INDCPA_MSGBYTES];
    polyvec skpv, b;
    poly v, mp;

    if (argc != 3) {
        fprintf(stderr, "usage: %s sk.hex ct.hex\n", argv[0]);
        return 2;
    }
    read_hex_bytes(argv[1], sk, sizeof(sk));
    read_hex_bytes(argv[2], ct, sizeof(ct));

    polyvec_frombytes(&skpv, sk);
    polyvec_decompress(&b, ct);
    poly_decompress(&v, ct + KYBER_POLYVECCOMPRESSEDBYTES);
    polyvec_ntt(&b);
    dump_poly("u0_ntt", &b.vec[0]);
    dump_poly("u1_ntt", &b.vec[1]);
    polyvec_basemul_acc_montgomery(&mp, &skpv, &b);
    dump_poly("mp_ntt", &mp);
    poly_invntt_tomont(&mp);
    dump_poly("mp_intt", &mp);
    poly_sub(&mp, &v, &mp);
    poly_reduce(&mp);
    dump_poly("diff", &mp);
    poly_tomsg(msg, &mp);
    printf("msg=");
    for (unsigned i = 0; i < sizeof(msg); ++i)
        printf("%02x", msg[i]);
    printf("\n");
    return 0;
}

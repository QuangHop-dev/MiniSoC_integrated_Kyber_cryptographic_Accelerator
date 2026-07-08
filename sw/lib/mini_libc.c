#include <stdint.h>
#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t n)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;

    while (n != 0u) {
        *d = *s;
        d++;
        s++;
        n--;
    }
    return dst;
}

void *memset(void *dst, int value, size_t n)
{
    uint8_t *d = (uint8_t *)dst;

    while (n != 0u) {
        *d = (uint8_t)value;
        d++;
        n--;
    }
    return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const uint8_t *pa = (const uint8_t *)a;
    const uint8_t *pb = (const uint8_t *)b;

    while (n != 0u) {
        if (*pa != *pb)
            return (int)*pa - (int)*pb;
        pa++;
        pb++;
        n--;
    }
    return 0;
}

uint32_t __mulsi3(uint32_t a, uint32_t b)
{
    uint32_t result = 0u;

    while (b != 0u) {
        if (b & 1u)
            result += a;
        a <<= 1;
        b >>= 1;
    }
    return result;
}

uint32_t __udivsi3(uint32_t n, uint32_t d)
{
    uint32_t q = 0u;
    uint32_t r = 0u;
    int i;

    if (d == 0u)
        return 0xffffffffu;

    for (i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> (uint32_t)i) & 1u);
        if (r >= d) {
            r -= d;
            q |= 1u << (uint32_t)i;
        }
    }
    return q;
}

uint32_t __umodsi3(uint32_t n, uint32_t d)
{
    if (d == 0u)
        return n;
    return n - (__udivsi3(n, d) * d);
}

static uint32_t abs32(int32_t v)
{
    uint32_t u = (uint32_t)v;

    return (v < 0) ? (~u + 1u) : u;
}

int32_t __divsi3(int32_t n, int32_t d)
{
    uint32_t q;
    int neg;

    if (d == 0)
        return -1;

    neg = ((n < 0) != (d < 0));
    q = __udivsi3(abs32(n), abs32(d));
    return neg ? -(int32_t)q : (int32_t)q;
}

int32_t __modsi3(int32_t n, int32_t d)
{
    if (d == 0)
        return n;
    return n - (__divsi3(n, d) * d);
}

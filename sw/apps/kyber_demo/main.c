#include <stdint.h>
#include <stddef.h>
#include "gpio.h"
#include "kyber.h"
#include "soc_memory_map.h"
#include "soc_platform.h"
#include "uart.h"
#include "kyber_demo_ref.h"

extern int memcmp(const void *a, const void *b, size_t n);
extern void *memcpy(void *dst, const void *src, size_t n);

static uint8_t pk[KYBER_PK_BYTES];
static uint8_t sk[KYBER_SK_BYTES];
static uint8_t ct[KYBER_CT_BYTES];
static uint8_t ss_enc[KYBER_SS_BYTES];
static uint8_t ss_dec[KYBER_SS_BYTES];
static uint8_t ss_bad[KYBER_SS_BYTES];
static uint8_t seed_keygen[KYBER_SEED_BYTES];
static uint8_t seed_encaps[KYBER_SEED_BYTES];

static void mark(uint32_t value)
{
    gpio_write(SOC_GPIO0_BASE, value & 0xffu);
}

static void fail(uint32_t code)
{
    mark(code);
    uart_puts(SOC_UART_BASE, "ERR ");
    uart_puthex32(SOC_UART_BASE, code);
    uart_puts(SOC_UART_BASE, "\n");
    for (;;) {
    }
}

static void uart_put_u32_dec(uint32_t value)
{
    char buf[11];
    int i = 0;

    if (value == 0u) {
        uart_putc(SOC_UART_BASE, '0');
        return;
    }

    while (value != 0u && i < 10) {
        buf[i++] = (char)('0' + (value % 10u));
        value /= 10u;
    }

    while (i > 0) {
        uart_putc(SOC_UART_BASE, buf[--i]);
    }
}

static void uart_put_hex_byte(uint8_t value)
{
    static const char hex[] = "0123456789abcdef";
    uart_putc(SOC_UART_BASE, hex[(value >> 4) & 0x0fu]);
    uart_putc(SOC_UART_BASE, hex[value & 0x0fu]);
}

static void uart_dump_bytes_full(const char *name, const uint8_t *buf, size_t len)
{
    size_t i;

    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " len=");
    uart_put_u32_dec((uint32_t)len);
    uart_puts(SOC_UART_BASE, "\n");

    for (i = 0; i < len; i++) {
        uart_put_hex_byte(buf[i]);

        if (((i + 1u) % 32u) == 0u) {
            uart_puts(SOC_UART_BASE, "\n");
        }
    }

    if ((len % 32u) != 0u) {
        uart_puts(SOC_UART_BASE, "\n");
    }
}

/*static void uart_print_perf(const char *name, uint32_t cycles)
{
    uint64_t ns;
    uint32_t us;
    uint32_t ns_rem;

    ns = ((uint64_t)cycles * 1000000000ull) / (uint64_t)SOC_CPU_HZ;
    us = (uint32_t)(ns / 1000ull);
    ns_rem = (uint32_t)(ns % 1000ull);

    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " cycles=");
    uart_put_u32_dec(cycles);
    uart_puts(SOC_UART_BASE, " time=");
    uart_put_u32_dec(us);
    uart_puts(SOC_UART_BASE, ".");
    if (ns_rem < 100u) uart_putc(SOC_UART_BASE, '0');
    if (ns_rem < 10u) uart_putc(SOC_UART_BASE, '0');
    uart_put_u32_dec(ns_rem);
    uart_puts(SOC_UART_BASE, " us\n");
}*/

static void uart_print_perf(const char *name, uint32_t cycles)
{
    uint32_t cycles_per_us;
    uint32_t us;
    uint32_t rem;
    uint32_t frac_ns;

    cycles_per_us = SOC_CPU_HZ / 1000000u;

    if (cycles_per_us == 0u) {
        cycles_per_us = 1u;
    }

    us = cycles / cycles_per_us;
    rem = cycles % cycles_per_us;

    /*
     * Fractional part in ns:
     * SOC_CPU_HZ determines the integer cycles per microsecond.
     */
    frac_ns = (rem * 1000u) / cycles_per_us;

    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " cycles=");
    uart_put_u32_dec(cycles);
    uart_puts(SOC_UART_BASE, " time=");
    uart_put_u32_dec(us);
    uart_puts(SOC_UART_BASE, ".");

    if (frac_ns < 100u)
        uart_putc(SOC_UART_BASE, '0');
    if (frac_ns < 10u)
        uart_putc(SOC_UART_BASE, '0');

    uart_put_u32_dec(frac_ns);
    uart_puts(SOC_UART_BASE, " us\n");
}

static void compare_ref_or_fail(const char *name,
                                const uint8_t *got,
                                const uint8_t *ref,
                                size_t len,
                                uint32_t err_code)
{
    uart_puts(SOC_UART_BASE, "CREF ");
    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " ");

    if (memcmp(got, ref, len) == 0) {
        uart_puts(SOC_UART_BASE, "PASS\n");
    } else {
        uart_puts(SOC_UART_BASE, "FAIL\n");
        fail(err_code);
    }
}

int main(void)
{
    int ret;
    uint32_t cyc;

    gpio_set_dir(SOC_GPIO0_BASE, 0xffu);
    mark(SOC_DEMO_BOOT_MARK);

    uart_init_div(SOC_UART_BASE, (uint16_t)SOC_UART_DIV);
    uart_puts(SOC_UART_BASE, "Kyber SoC PL demo\n");

    memcpy(seed_keygen, ref_keygen_seed, KYBER_SEED_BYTES);
    memcpy(seed_encaps, ref_enc_seed, KYBER_SEED_BYTES);

    ret = kyber_keygen(seed_keygen, pk, sk, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK)
        fail(SOC_DEMO_ERR_KEYGEN);
    mark(SOC_DEMO_KEYGEN_MARK);
    uart_puts(SOC_UART_BASE, "keygen ok\n");

    cyc = kyber_cycle_count();

    uart_print_perf("keygen", cyc);
    compare_ref_or_fail("pk", pk, ref_pk, KYBER_PK_BYTES, SOC_DEMO_ERR_COMPARE);
    compare_ref_or_fail("sk", sk, ref_sk, KYBER_SK_BYTES, SOC_DEMO_ERR_COMPARE);

    uart_dump_bytes_full("pk", pk, KYBER_PK_BYTES);
    uart_dump_bytes_full("sk", sk, KYBER_SK_BYTES);

    ret = kyber_encaps(seed_encaps, pk, ct, ss_enc, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK)
        fail(SOC_DEMO_ERR_ENCAPS);
    mark(SOC_DEMO_ENCAPS_MARK);
    uart_puts(SOC_UART_BASE, "encaps ok\n");

    cyc = kyber_cycle_count();

    uart_print_perf("encaps", cyc);
    compare_ref_or_fail("ct", ct, ref_ct, KYBER_CT_BYTES, SOC_DEMO_ERR_COMPARE);
    compare_ref_or_fail("ss_enc", ss_enc, ref_ss_enc, KYBER_SS_BYTES, SOC_DEMO_ERR_COMPARE);

    uart_dump_bytes_full("ct", ct, KYBER_CT_BYTES);
    uart_dump_bytes_full("ss_enc", ss_enc, KYBER_SS_BYTES);

    ret = kyber_decaps(ct, sk, ss_dec, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK)
        fail(SOC_DEMO_ERR_DECAPS);
    if (memcmp(ss_enc, ss_dec, KYBER_SS_BYTES) != 0)
        fail(SOC_DEMO_ERR_COMPARE);
    mark(SOC_DEMO_DECAPS_MARK);
    uart_puts(SOC_UART_BASE, "decaps valid ok\n");

    cyc = kyber_cycle_count();

    uart_print_perf("decaps_valid", cyc);
    compare_ref_or_fail("ss_dec", ss_dec, ref_ss_dec_valid, KYBER_SS_BYTES, SOC_DEMO_ERR_COMPARE);

    uart_dump_bytes_full("ss_dec", ss_dec, KYBER_SS_BYTES);

    ct[0] ^= 1u;
    ret = kyber_decaps(ct, sk, ss_bad, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK)
        fail(SOC_DEMO_ERR_REJECT);
    if (memcmp(ss_enc, ss_bad, KYBER_SS_BYTES) == 0)
        fail(SOC_DEMO_ERR_REJECT);
    mark(SOC_DEMO_REJECT_MARK);
    uart_puts(SOC_UART_BASE, "decaps invalid ok\n");

    cyc = kyber_cycle_count();

    uart_print_perf("decaps_invalid", cyc);
    compare_ref_or_fail("ss_bad", ss_bad, ref_ss_dec_invalid, KYBER_SS_BYTES, SOC_DEMO_ERR_REJECT);

    uart_dump_bytes_full("ss_bad", ss_bad, KYBER_SS_BYTES);

    mark(SOC_DEMO_DONE_MARK);
    uart_puts(SOC_UART_BASE, "done\n");

    for (;;) {
    }
}

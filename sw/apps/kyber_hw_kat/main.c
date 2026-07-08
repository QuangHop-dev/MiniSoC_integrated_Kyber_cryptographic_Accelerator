#include <stdint.h>
#include <stddef.h>

#include "gpio.h"
#include "kyber.h"
#include "soc_memory_map.h"
#include "soc_platform.h"
#include "uart.h"

#define KAT_MAX_BATCH_TESTS 100u

extern int memcmp(const void *a, const void *b, size_t n);

static uint8_t keygen_seed[KYBER_SEED_BYTES];
static uint8_t enc_seed[KYBER_SEED_BYTES];
static uint8_t pk[KYBER_PK_BYTES];
static uint8_t sk[KYBER_SK_BYTES];
static uint8_t ct[KYBER_CT_BYTES];
static uint8_t ss_enc[KYBER_SS_BYTES];
static uint8_t ss_dec[KYBER_SS_BYTES];
static uint8_t ss_bad[KYBER_SS_BYTES];
static uint8_t exp_pk[KYBER_PK_BYTES];
static uint8_t exp_sk[KYBER_SK_BYTES];
static uint8_t exp_ct[KYBER_CT_BYTES];
static uint8_t exp_ss_enc[KYBER_SS_BYTES];
static uint8_t exp_ss_dec[KYBER_SS_BYTES];
static uint8_t exp_ct_bad[KYBER_CT_BYTES];
static uint8_t exp_ss_bad[KYBER_SS_BYTES];

static void uart_put_u32_dec(uint32_t value)
{
    char buf[11];
    int i = 0;

    if (value == 0u) {
        uart_putc(SOC_UART_BASE, '0');
        return;
    }

    while ((value != 0u) && (i < 10)) {
        buf[i++] = (char)('0' + (value % 10u));
        value /= 10u;
    }

    while (i > 0)
        uart_putc(SOC_UART_BASE, buf[--i]);
}

static void uart_put_s32_dec(int32_t value)
{
    if (value < 0) {
        uart_putc(SOC_UART_BASE, '-');
        uart_put_u32_dec((uint32_t)(-value));
    } else {
        uart_put_u32_dec((uint32_t)value);
    }
}

static void uart_put_hex_byte(uint8_t value)
{
    static const char hex[] = "0123456789abcdef";

    uart_putc(SOC_UART_BASE, hex[(value >> 4) & 0x0fu]);
    uart_putc(SOC_UART_BASE, hex[value & 0x0fu]);
}

static void uart_put_line_repeat(char ch, uint32_t count)
{
    while (count != 0u) {
        uart_putc(SOC_UART_BASE, ch);
        count--;
    }
    uart_puts(SOC_UART_BASE, "\n");
}

static int recv_byte(void)
{
    int value;

    do {
        value = uart_getc(SOC_UART_BASE);
    } while (value < 0);
    return value & 0xff;
}

static void recv_bytes(uint8_t *dst, size_t len)
{
    size_t i;

    for (i = 0u; i < len; i++)
        dst[i] = (uint8_t)recv_byte();
}

static uint16_t recv_le16(void)
{
    uint16_t value = (uint16_t)recv_byte();

    value |= (uint16_t)((uint16_t)recv_byte() << 8);
    return value;
}

static uint32_t recv_le32(void)
{
    uint32_t value = (uint32_t)recv_byte();

    value |= (uint32_t)recv_byte() << 8;
    value |= (uint32_t)recv_byte() << 16;
    value |= (uint32_t)recv_byte() << 24;
    return value;
}

static void wait_magic(void)
{
    uint8_t state = 0u;

    uart_puts(SOC_UART_BASE, "READY: kyber_hw_kat waiting for KHV1 stream\n");
    for (;;) {
        uint8_t ch = (uint8_t)recv_byte();

        if ((state == 0u && ch == 'K') ||
            (state == 1u && ch == 'H') ||
            (state == 2u && ch == 'V') ||
            (state == 3u && ch == '1')) {
            state++;
            if (state == 4u)
                return;
        } else {
            state = (ch == 'K') ? 1u : 0u;
        }
    }
}

static void recv_vector_payload(void)
{
    recv_bytes(keygen_seed, KYBER_SEED_BYTES);
    recv_bytes(enc_seed, KYBER_SEED_BYTES);
    recv_bytes(exp_pk, KYBER_PK_BYTES);
    recv_bytes(exp_sk, KYBER_SK_BYTES);
    recv_bytes(exp_ct, KYBER_CT_BYTES);
    recv_bytes(exp_ss_enc, KYBER_SS_BYTES);
    recv_bytes(exp_ss_dec, KYBER_SS_BYTES);
    recv_bytes(exp_ct_bad, KYBER_CT_BYTES);
    recv_bytes(exp_ss_bad, KYBER_SS_BYTES);
}

static int compare_region(const char *name,
                          const uint8_t *got,
                          const uint8_t *exp,
                          size_t len)
{
    size_t i;
    uint32_t mismatches = 0u;

    for (i = 0u; i < len; i++) {
        if (got[i] != exp[i]) {
            if (mismatches < 8u) {
                uart_puts(SOC_UART_BASE, "Mismatch ");
                uart_puts(SOC_UART_BASE, name);
                uart_puts(SOC_UART_BASE, " byte=");
                uart_put_u32_dec((uint32_t)i);
                uart_puts(SOC_UART_BASE, " got=");
                uart_put_hex_byte(got[i]);
                uart_puts(SOC_UART_BASE, " exp=");
                uart_put_hex_byte(exp[i]);
                uart_puts(SOC_UART_BASE, "\n");
            }
            mismatches++;
        }
    }

    if (mismatches != 0u) {
        uart_puts(SOC_UART_BASE, "| FAIL | ");
        uart_puts(SOC_UART_BASE, name);
        uart_puts(SOC_UART_BASE, " | mismatches=");
        uart_put_u32_dec(mismatches);
        uart_puts(SOC_UART_BASE, "\n");
        gpio_write(SOC_GPIO0_BASE, SOC_DEMO_ERR_COMPARE);
        return 0;
    }

    uart_puts(SOC_UART_BASE, "| PASS | ");
    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " | compared ");
    uart_put_u32_dec((uint32_t)len);
    uart_puts(SOC_UART_BASE, " bytes against C reference\n");
    return 1;
}

static void log_done(const char *name, uint32_t cycles)
{
    uart_puts(SOC_UART_BASE, "| DONE | ");
    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " | cycles=");
    uart_put_u32_dec(cycles);
    uart_puts(SOC_UART_BASE, " | status=");
    uart_puthex32(SOC_UART_BASE, kyber_status());
    uart_puts(SOC_UART_BASE, "\n");
}

static int log_hw_error(const char *name, int ret)
{
    uart_puts(SOC_UART_BASE, "| FAIL | ");
    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " | hw_ret=");
    uart_put_s32_dec(ret);
    uart_puts(SOC_UART_BASE, " | status=");
    uart_puthex32(SOC_UART_BASE, kyber_status());
    uart_puts(SOC_UART_BASE, "\n");
    gpio_write(SOC_GPIO0_BASE, SOC_DEMO_ERR_COMPARE);
    return 0;
}

static int run_one_vector(uint32_t global_index)
{
    int ret;
    int pass;
    uint32_t cycles;

    uart_puts(SOC_UART_BASE, "//////////////////////////// KEY GENERATION ///////////////////////////////\n");
    ret = kyber_keygen(keygen_seed, pk, sk, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK)
        return log_hw_error("keygen", ret);
    cycles = kyber_cycle_count();
    log_done("keygen", cycles);
    pass = compare_region("pk", pk, exp_pk, KYBER_PK_BYTES);
    pass &= compare_region("sk", sk, exp_sk, KYBER_SK_BYTES);
    if (!pass)
        return 0;

    uart_puts(SOC_UART_BASE, "//////////////////////////// ENCAPSULATION ////////////////////////////////\n");
    ret = kyber_encaps(enc_seed, pk, ct, ss_enc, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK)
        return log_hw_error("encaps", ret);
    cycles = kyber_cycle_count();
    log_done("encaps", cycles);
    pass = compare_region("ct", ct, exp_ct, KYBER_CT_BYTES);
    pass &= compare_region("ss_enc", ss_enc, exp_ss_enc, KYBER_SS_BYTES);
    if (!pass)
        return 0;

    uart_puts(SOC_UART_BASE, "//////////////////////////// VALID DECAPSULATION //////////////////////////\n");
    ret = kyber_decaps(ct, sk, ss_dec, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK)
        return log_hw_error("decaps_valid", ret);
    cycles = kyber_cycle_count();
    log_done("decaps_valid", cycles);
    pass = compare_region("ss_dec_valid", ss_dec, exp_ss_dec, KYBER_SS_BYTES);
    if (memcmp(ss_enc, ss_dec, KYBER_SS_BYTES) != 0) {
        uart_puts(SOC_UART_BASE, "| FAIL | ss_enc != ss_dec_valid\n");
        pass = 0;
    }
    if (!pass)
        return 0;

    uart_puts(SOC_UART_BASE, "//////////////////////////// INVALID DECAPSULATION ////////////////////////\n");
    ret = kyber_decaps(exp_ct_bad, sk, ss_bad, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK)
        return log_hw_error("decaps_invalid", ret);
    cycles = kyber_cycle_count();
    log_done("decaps_invalid", cycles);
    pass = compare_region("ss_dec_invalid", ss_bad, exp_ss_bad, KYBER_SS_BYTES);
    if (memcmp(ss_enc, ss_bad, KYBER_SS_BYTES) == 0) {
        uart_puts(SOC_UART_BASE, "| FAIL | invalid decaps reused valid shared secret\n");
        pass = 0;
    }

    if (pass) {
        gpio_write(SOC_GPIO0_BASE, (global_index + 1u) & 0xffu);
        return 1;
    }

    return 0;
}

static void run_batch(void)
{
    uint32_t start_test;
    uint16_t num_tests;
    uint16_t flags;
    uint32_t local;
    uint32_t pass_count = 0u;
    uint8_t batch_failed = 0u;

    start_test = recv_le32();
    num_tests = recv_le16();
    flags = recv_le16();
    (void)flags;

    uart_puts(SOC_UART_BASE, "REPORT-BEGIN: KYBER-HW\n\n");
    uart_put_line_repeat('=', 78u);
    uart_puts(SOC_UART_BASE, "* KYBER512 HARDWARE IP - UART STREAMED KAT\n");
    uart_put_line_repeat('=', 78u);
    uart_puts(SOC_UART_BASE, "| Vectors=");
    uart_put_u32_dec(num_tests);
    uart_puts(SOC_UART_BASE, " | Global range=");
    uart_put_u32_dec(start_test);
    uart_puts(SOC_UART_BASE, "..");
    uart_put_u32_dec(start_test + (uint32_t)num_tests - 1u);
    uart_puts(SOC_UART_BASE, "\n");
    uart_puts(SOC_UART_BASE, "| PK=800 B | SK=1632 B | CT=768 B | SS=32 B\n");

    if ((num_tests == 0u) || (num_tests > KAT_MAX_BATCH_TESTS)) {
        uart_puts(SOC_UART_BASE, "RESULT: FAIL - invalid batch size\n");
        uart_puts(SOC_UART_BASE, "REPORT-END: KYBER-HW\n");
        return;
    }

    for (local = 0u; local < (uint32_t)num_tests; local++) {
        uint32_t global_index;

        uart_puts(SOC_UART_BASE, "READY-VECTOR\n");
        global_index = recv_le32();
        recv_vector_payload();

        uart_puts(SOC_UART_BASE, "\n-------------------- KAT VECTOR ");
        uart_put_u32_dec(global_index);
        uart_puts(SOC_UART_BASE, " / ");
        uart_put_u32_dec(start_test + (uint32_t)num_tests - 1u);
        uart_puts(SOC_UART_BASE, " ---------------------------\n");

        if (global_index != (start_test + local)) {
            uart_puts(SOC_UART_BASE, "RESULT: FAIL - unexpected global index ");
            uart_put_u32_dec(global_index);
            uart_puts(SOC_UART_BASE, "\n");
            batch_failed = 1u;
            break;
        }

        if (run_one_vector(global_index)) {
            pass_count++;
        } else {
            uart_puts(SOC_UART_BASE, "RESULT: FAIL at KAT count ");
            uart_put_u32_dec(global_index);
            uart_puts(SOC_UART_BASE, "\n");
            batch_failed = 1u;
            break;
        }
    }

    uart_put_line_repeat('=', 78u);
    if (!batch_failed && pass_count == (uint32_t)num_tests) {
        gpio_write(SOC_GPIO0_BASE, SOC_DEMO_DONE_MARK);
        uart_puts(SOC_UART_BASE, "* RESULT: PASS - HARDWARE OUTPUT MATCHES KYBER512 C REFERENCE.\n");
        uart_put_line_repeat('=', 78u);
        uart_puts(SOC_UART_BASE, "REPORT-END: KYBER-HW\n");
        uart_puts(SOC_UART_BASE, "PASS: kyber_hw_kat matched Kyber512 KAT C reference for ");
        uart_put_u32_dec(num_tests);
        uart_puts(SOC_UART_BASE, " test(s), global range ");
        uart_put_u32_dec(start_test);
        uart_puts(SOC_UART_BASE, "..");
        uart_put_u32_dec(start_test + (uint32_t)num_tests - 1u);
        uart_puts(SOC_UART_BASE, "\n");
    } else {
        gpio_write(SOC_GPIO0_BASE, SOC_DEMO_ERR_COMPARE);
        uart_puts(SOC_UART_BASE, "* RESULT: FAIL - HARDWARE KAT MISMATCH.\n");
        uart_put_line_repeat('=', 78u);
        uart_puts(SOC_UART_BASE, "REPORT-END: KYBER-HW\n");
    }
}

int main(void)
{
    uart_init_div(SOC_UART_BASE, (uint16_t)SOC_UART_DIV);
    gpio_set_dir(SOC_GPIO0_BASE, 0xffu);
    gpio_write(SOC_GPIO0_BASE, SOC_DEMO_BOOT_MARK);

    uart_puts(SOC_UART_BASE, "\n");
    uart_put_line_repeat('=', 78u);
    uart_puts(SOC_UART_BASE, " Kyber hardware KAT firmware\n");
    uart_puts(SOC_UART_BASE, " Stream protocol: KHV1 + batch header + one vector at a time\n");
    uart_put_line_repeat('=', 78u);

    for (;;) {
        wait_magic();
        run_batch();
    }
}

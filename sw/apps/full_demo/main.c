#include <stdint.h>
#include <stddef.h>

#include "gpio.h"
#include "irq.h"
#include "kyber.h"
#include "kyber_demo_ref.h"
#include "lcd_i2c.h"
#include "pic.h"
#include "soc_memory_map.h"
#include "soc_platform.h"
#include "timer.h"
#include "uart.h"

#define LCD_ADDRESS 0x27u
#define LCD_COLS    20u

#define EV_DIP0_LED_TIMER (1u << 0)
#define EV_DIP1_LCD_TOGGLE (1u << 1)
#define EV_DIP2_UART_MSG  (1u << 2)
#define EV_DIP3_RESET     (1u << 3)
#define EV_DIP4_KEYGEN    (1u << 4)
#define EV_DIP5_ENCAPS    (1u << 5)
#define EV_DIP6_DECAPS    (1u << 6)
#define EV_DIP7_DEBUG     (1u << 7)
#define EV_EXT0_LED_BLINK (1u << 8)
#define EV_EXT1_LED_SWEEP (1u << 9)

#define DIP_STATE_MASK    (EV_DIP0_LED_TIMER | EV_DIP1_LCD_TOGGLE | EV_DIP7_DEBUG)
#define DIP_ACTION_MASK   (EV_DIP2_UART_MSG | EV_DIP3_RESET | EV_DIP4_KEYGEN | \
                           EV_DIP5_ENCAPS | EV_DIP6_DECAPS)
#define EXT_EVENT_MASK    (EV_EXT0_LED_BLINK | EV_EXT1_LED_SWEEP)
#define DIP_DEBOUNCE_LOOPS 800000u
#define LED_BLINK_LOOPS   2500000u
#define DIP_ACTIVE_LOW    0u

extern int memcmp(const void *a, const void *b, size_t n);
extern void *memcpy(void *dst, const void *src, size_t n);

static lcd_i2c_t lcd;
static uint8_t lcd_ok;
static uint8_t lcd_enabled;
static uint8_t led_timer_run;
static uint8_t debug_mode;
static uint8_t have_keypair;
static uint8_t have_capsule;

static volatile uint32_t irq_events;
static volatile uint32_t timer_irq_count;
static volatile uint32_t gpio_irq_count;
static volatile uint32_t ext0_irq_count;
static volatile uint32_t ext1_irq_count;
static volatile uint32_t led_counter;
static volatile uint8_t dip_sample_request;
static volatile uint32_t pic_enable_mask;
static uint32_t dip_shadow;

static uint8_t pk[KYBER_PK_BYTES];
static uint8_t sk[KYBER_SK_BYTES];
static uint8_t ct[KYBER_CT_BYTES];
static uint8_t ss_enc[KYBER_SS_BYTES];
static uint8_t ss_dec[KYBER_SS_BYTES];
static uint8_t ss_bad[KYBER_SS_BYTES];
static uint8_t seed_keygen[KYBER_SEED_BYTES];
static uint8_t seed_encaps[KYBER_SEED_BYTES];

static void dip_debounce_delay(void)
{
    volatile uint32_t i;

    for (i = 0u; i < DIP_DEBOUNCE_LOOPS; i++) {
    }
}

static void led_blink_delay(void)
{
    volatile uint32_t i;

    for (i = 0u; i < LED_BLINK_LOOPS; i++) {
    }
}

static uint32_t dip_active_mask(uint32_t raw)
{
    raw &= 0xffu;
#if DIP_ACTIVE_LOW
    raw = (~raw) & 0xffu;
#endif
    return raw;
}

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

static void uart_put_hex_byte(uint8_t value)
{
    static const char hex[] = "0123456789abcdef";

    uart_putc(SOC_UART_BASE, hex[(value >> 4) & 0x0fu]);
    uart_putc(SOC_UART_BASE, hex[value & 0x0fu]);
}

static void uart_dump_bytes(const char *name, const uint8_t *buf, size_t len)
{
    size_t i;

    uart_puts(SOC_UART_BASE, "----- ");
    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " len=");
    uart_put_u32_dec((uint32_t)len);
    uart_puts(SOC_UART_BASE, " -----\n");

    for (i = 0u; i < len; i++) {
        uart_put_hex_byte(buf[i]);
        if (((i + 1u) % 32u) == 0u)
            uart_puts(SOC_UART_BASE, "\n");
    }

    if ((len % 32u) != 0u)
        uart_puts(SOC_UART_BASE, "\n");
    uart_puts(SOC_UART_BASE, "\n");
}

static void uart_print_perf(const char *name, uint32_t cycles)
{
    uint32_t cycles_per_us = SOC_CPU_HZ / 1000000u;
    uint32_t us;
    uint32_t rem;
    uint32_t frac_ns;

    if (cycles_per_us == 0u)
        cycles_per_us = 1u;

    us = cycles / cycles_per_us;
    rem = cycles % cycles_per_us;
    frac_ns = (rem * 1000u) / cycles_per_us;

    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " cycles=");
    uart_put_u32_dec(cycles);
    uart_puts(SOC_UART_BASE, " time=");
    uart_put_u32_dec(us);
    uart_putc(SOC_UART_BASE, '.');
    if (frac_ns < 100u)
        uart_putc(SOC_UART_BASE, '0');
    if (frac_ns < 10u)
        uart_putc(SOC_UART_BASE, '0');
    uart_put_u32_dec(frac_ns);
    uart_puts(SOC_UART_BASE, " us\n");
}

static void lcd_line(uint8_t row, const char *text)
{
    uint8_t col;

    if (!lcd_ok || !lcd_enabled)
        return;

    lcd_i2c_set_cursor(&lcd, 0u, row);
    for (col = 0u; col < LCD_COLS; col++) {
        char ch = text[col];
        if (ch == '\0') {
            while (col < LCD_COLS) {
                lcd_i2c_putc(&lcd, ' ');
                col++;
            }
            return;
        }
        lcd_i2c_putc(&lcd, ch);
    }
}

static void lcd_screen(const char *line0, const char *line1,
                       const char *line2, const char *line3)
{
    if (!lcd_ok || !lcd_enabled)
        return;

    lcd_i2c_clear(&lcd);
    lcd_line(0u, line0);
    lcd_line(1u, line1);
    lcd_line(2u, line2);
    lcd_line(3u, line3);
}

static void append_char(char *buf, uint8_t *pos, char ch)
{
    if (*pos < LCD_COLS)
        buf[(*pos)++] = ch;
}

static void append_text(char *buf, uint8_t *pos, const char *text)
{
    while (*text != '\0')
        append_char(buf, pos, *text++);
}

static void append_u32_dec(char *buf, uint8_t *pos, uint32_t value)
{
    char tmp[10];
    uint8_t i = 0u;

    if (value == 0u) {
        append_char(buf, pos, '0');
        return;
    }

    while ((value != 0u) && (i < sizeof(tmp))) {
        tmp[i++] = (char)('0' + (value % 10u));
        value /= 10u;
    }

    while (i != 0u)
        append_char(buf, pos, tmp[--i]);
}

static void lcd_line_cycles(uint8_t row, const char *name, uint32_t cycles)
{
    char buf[LCD_COLS + 1u];
    uint8_t pos = 0u;

    append_text(buf, &pos, name);
    append_char(buf, &pos, ':');
    append_char(buf, &pos, ' ');
    append_u32_dec(buf, &pos, cycles);
    while (pos < LCD_COLS)
        buf[pos++] = ' ';
    buf[LCD_COLS] = '\0';
    lcd_line(row, buf);
}

static void lcd_boot(void)
{
    if (!lcd_ok || !lcd_enabled)
        return;

    lcd_screen("SoC demo ready",
               "IRQ/GPIO ready",
               "I2C LCD ready",
               "Kyber IP ready");
}

static void lcd_event(const char *line0, const char *line1,
                      const char *line2, const char *line3)
{
    lcd_screen(line0, line1, line2, line3);
}

static void log_event(const char *dip, const char *msg)
{
    uart_puts(SOC_UART_BASE, "IRQ EVENT ");
    uart_puts(SOC_UART_BASE, dip);
    uart_puts(SOC_UART_BASE, ": ");
    uart_puts(SOC_UART_BASE, msg);
    uart_puts(SOC_UART_BASE, "\n");
}

static int compare_ref(const char *name, const uint8_t *got,
                       const uint8_t *ref, size_t len)
{
    uart_puts(SOC_UART_BASE, "CREF ");
    uart_puts(SOC_UART_BASE, name);
    uart_puts(SOC_UART_BASE, " ");

    if (memcmp(got, ref, len) == 0) {
        uart_puts(SOC_UART_BASE, "PASS\n");
        return 1;
    }

    uart_puts(SOC_UART_BASE, "FAIL\n");
    gpio_write(SOC_GPIO0_BASE, SOC_DEMO_ERR_COMPARE);
    return 0;
}

static int dump_and_compare(const char *name,
                            const uint8_t *hw,
                            const uint8_t *sw_ref,
                            size_t len)
{
    char hw_name[20];
    char sw_name[20];
    uint8_t i = 0u;
    uint8_t pos = 0u;

    hw_name[pos++] = 'H';
    hw_name[pos++] = 'W';
    hw_name[pos++] = ' ';
    while ((name[i] != '\0') && (pos < (sizeof(hw_name) - 1u)))
        hw_name[pos++] = name[i++];
    hw_name[pos] = '\0';

    i = 0u;
    pos = 0u;
    sw_name[pos++] = 'S';
    sw_name[pos++] = 'W';
    sw_name[pos++] = '_';
    sw_name[pos++] = 'R';
    sw_name[pos++] = 'E';
    sw_name[pos++] = 'F';
    sw_name[pos++] = ' ';
    while ((name[i] != '\0') && (pos < (sizeof(sw_name) - 1u)))
        sw_name[pos++] = name[i++];
    sw_name[pos] = '\0';

    uart_dump_bytes(hw_name, hw, len);
    uart_dump_bytes(sw_name, sw_ref, len);
    return compare_ref(name, hw, sw_ref, len);
}

static int run_keygen_demo(void)
{
    int ret;
    uint32_t cycles;
    int pass;

    log_event("DIP4", "Kyber keygen start");
    lcd_screen("Kyber KeyGen",
               "Running HW IP...",
               "Compare to CREF",
               "Please wait");

    memcpy(seed_keygen, ref_keygen_seed, KYBER_SEED_BYTES);
    ret = kyber_keygen(seed_keygen, pk, sk, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK) {
        uart_puts(SOC_UART_BASE, "keygen FAIL ret=");
        uart_put_u32_dec((uint32_t)(0 - ret));
        uart_puts(SOC_UART_BASE, "\n");
        lcd_screen("Kyber KeyGen",
                   "HW operation FAIL",
                   "Check UART log",
                   "LED shows error");
        gpio_write(SOC_GPIO0_BASE, SOC_DEMO_ERR_KEYGEN);
        have_keypair = 0u;
        return 0;
    }

    cycles = kyber_cycle_count();
    uart_print_perf("keygen", cycles);
    pass = dump_and_compare("pk", pk, ref_pk, KYBER_PK_BYTES);
    pass &= dump_and_compare("sk", sk, ref_sk, KYBER_SK_BYTES);

    have_keypair = (uint8_t)pass;
    gpio_write(SOC_GPIO0_BASE, pass ? SOC_DEMO_KEYGEN_MARK : SOC_DEMO_ERR_COMPARE);
    lcd_screen("Kyber KeyGen",
               pass ? "Compare CREF: PASS" : "Compare CREF: FAIL",
               "",
               pass ? "KeyGen complete" : "KeyGen error");
    lcd_line_cycles(2u, "Cycles", cycles);
    return pass;
}

static int ensure_keypair(void)
{
    if (have_keypair)
        return 1;

    uart_puts(SOC_UART_BASE, "Auto keygen prerequisite\n");
    return run_keygen_demo();
}

static int run_encaps_demo(void)
{
    int ret;
    uint32_t cycles;
    int pass;

    if (!ensure_keypair())
        return 0;

    log_event("DIP5", "Kyber encaps start");
    lcd_screen("Kyber Encaps",
               "Running HW IP...",
               "Compare to CREF",
               "Please wait");

    memcpy(seed_encaps, ref_enc_seed, KYBER_SEED_BYTES);
    ret = kyber_encaps(seed_encaps, pk, ct, ss_enc, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK) {
        uart_puts(SOC_UART_BASE, "encaps FAIL ret=");
        uart_put_u32_dec((uint32_t)(0 - ret));
        uart_puts(SOC_UART_BASE, "\n");
        lcd_screen("Kyber Encaps",
                   "HW operation FAIL",
                   "Check UART log",
                   "LED shows error");
        gpio_write(SOC_GPIO0_BASE, SOC_DEMO_ERR_ENCAPS);
        have_capsule = 0u;
        return 0;
    }

    cycles = kyber_cycle_count();
    uart_print_perf("encaps", cycles);
    pass = dump_and_compare("ct", ct, ref_ct, KYBER_CT_BYTES);
    pass &= dump_and_compare("ss_enc", ss_enc, ref_ss_enc, KYBER_SS_BYTES);

    have_capsule = (uint8_t)pass;
    gpio_write(SOC_GPIO0_BASE, pass ? SOC_DEMO_ENCAPS_MARK : SOC_DEMO_ERR_COMPARE);
    lcd_screen("Kyber Encaps",
               pass ? "Compare CREF: PASS" : "Compare CREF: FAIL",
               "",
               pass ? "Encaps complete" : "Encaps error");
    lcd_line_cycles(2u, "Cycles", cycles);
    return pass;
}

static int ensure_capsule(void)
{
    if (have_capsule)
        return 1;

    uart_puts(SOC_UART_BASE, "Auto encaps prerequisite\n");
    return run_encaps_demo();
}

static int run_decaps_demo(void)
{
    int ret;
    uint32_t cycles_valid;
    uint32_t cycles_invalid;
    int pass;

    if (!ensure_capsule())
        return 0;

    log_event("DIP6", "Kyber decaps start");
    lcd_screen("Kyber Decaps",
               "Valid ct running",
               "Compare to CREF",
               "Please wait");

    ret = kyber_decaps(ct, sk, ss_dec, SOC_KYBER_TIMEOUT);
    if (ret != KYBER_OK) {
        uart_puts(SOC_UART_BASE, "decaps valid FAIL ret=");
        uart_put_u32_dec((uint32_t)(0 - ret));
        uart_puts(SOC_UART_BASE, "\n");
        lcd_screen("Kyber Decaps",
                   "Valid ct HW FAIL",
                   "Check UART log",
                   "LED shows error");
        gpio_write(SOC_GPIO0_BASE, SOC_DEMO_ERR_DECAPS);
        return 0;
    }

    cycles_valid = kyber_cycle_count();
    pass = dump_and_compare("ss_dec", ss_dec, ref_ss_dec_valid, KYBER_SS_BYTES);
    pass &= (memcmp(ss_enc, ss_dec, KYBER_SS_BYTES) == 0);
    uart_puts(SOC_UART_BASE, pass ? "shared-secret match PASS\n" :
                                "shared-secret match FAIL\n");
    uart_print_perf("decaps_valid", cycles_valid);

    ct[0] ^= 1u;
    lcd_screen("Kyber Decaps",
               "Invalid ct running",
               "Reject path check",
               "Please wait");
    ret = kyber_decaps(ct, sk, ss_bad, SOC_KYBER_TIMEOUT);
    ct[0] ^= 1u;

    if (ret != KYBER_OK) {
        uart_puts(SOC_UART_BASE, "decaps invalid FAIL ret=");
        uart_put_u32_dec((uint32_t)(0 - ret));
        uart_puts(SOC_UART_BASE, "\n");
        lcd_screen("Kyber Decaps",
                   "Invalid ct HW FAIL",
                   "Check UART log",
                   "LED shows error");
        gpio_write(SOC_GPIO0_BASE, SOC_DEMO_ERR_REJECT);
        return 0;
    }

    cycles_invalid = kyber_cycle_count();
    pass &= dump_and_compare("ss_bad", ss_bad, ref_ss_dec_invalid, KYBER_SS_BYTES);
    pass &= (memcmp(ss_enc, ss_bad, KYBER_SS_BYTES) != 0);
    uart_puts(SOC_UART_BASE, pass ? "reject path PASS\n" : "reject path FAIL\n");
    uart_print_perf("decaps_invalid", cycles_invalid);
    gpio_write(SOC_GPIO0_BASE, pass ? SOC_DEMO_DECAPS_MARK : SOC_DEMO_ERR_COMPARE);
    lcd_screen("Kyber Decaps",
               pass ? "CREF valid: PASS" : "CREF valid: FAIL",
               pass ? "Reject path: PASS" : "Reject path: FAIL",
               "");
    lcd_line_cycles(3u, "Invalid cyc", cycles_invalid);
    lcd_line_cycles(2u, "Valid cycles", cycles_valid);
    return pass;
}

static void print_debug_state(uint32_t events)
{
    uint32_t raw_dip = gpio_read(SOC_GPIO1_BASE) & 0xffu;

    uart_puts(SOC_UART_BASE, "DEBUG events=");
    uart_puthex32(SOC_UART_BASE, events);
    uart_puts(SOC_UART_BASE, " dip_raw=");
    uart_puthex32(SOC_UART_BASE, raw_dip);
    uart_puts(SOC_UART_BASE, " dip_active=");
    uart_puthex32(SOC_UART_BASE, dip_active_mask(raw_dip));
    uart_puts(SOC_UART_BASE, " timer_irq=");
    uart_put_u32_dec(timer_irq_count);
    uart_puts(SOC_UART_BASE, " gpio_irq=");
    uart_put_u32_dec(gpio_irq_count);
    uart_puts(SOC_UART_BASE, " ext0_irq=");
    uart_put_u32_dec(ext0_irq_count);
    uart_puts(SOC_UART_BASE, " ext1_irq=");
    uart_put_u32_dec(ext1_irq_count);
    uart_puts(SOC_UART_BASE, " led=");
    uart_put_u32_dec(led_counter);
    uart_puts(SOC_UART_BASE, "\n");
}

static uint32_t take_events(void)
{
    uint32_t events;

    irq_global_disable();
    events = irq_events;
    irq_events = 0u;
    irq_global_enable();
    return events;
}

static uint8_t take_dip_sample_request(void)
{
    uint8_t request;

    irq_global_disable();
    request = dip_sample_request;
    dip_sample_request = 0u;
    irq_global_enable();
    return request;
}

static uint32_t sample_dip_events(uint32_t mask)
{
    uint32_t dip = dip_active_mask(gpio_read(SOC_GPIO1_BASE));
    uint32_t changed;
    uint32_t stable;
    uint32_t rising;
    uint32_t events;

    mask &= 0xffu;
    if (mask == 0u)
        return 0u;

    changed = (dip ^ dip_shadow) & mask;
    if (changed == 0u)
        return 0u;

    dip_debounce_delay();
    stable = dip_active_mask(gpio_read(SOC_GPIO1_BASE));
    changed = (stable ^ dip_shadow) & mask;
    if (changed == 0u)
        return 0u;

    rising = changed & stable;
    events = (changed & DIP_STATE_MASK) | (rising & DIP_ACTION_MASK);
    dip_shadow = (dip_shadow & ~changed) | (stable & changed);
    return events;
}

static void led_effect_begin(uint8_t *saved_timer_run)
{
    irq_global_disable();
    *saved_timer_run = led_timer_run;
    led_timer_run = 0u;
    pic_enable_mask &= ~PIC_IRQ_TIMER;
    pic_enable(SOC_PIC_BASE, pic_enable_mask);
    timer_clear(SOC_TIMER_BASE, 0xffffu);
    pic_clear(SOC_PIC_BASE, PIC_IRQ_TIMER);
    irq_global_enable();
}

static void led_effect_end(uint8_t saved_timer_run)
{
    irq_global_disable();
    timer_clear(SOC_TIMER_BASE, 0xffffu);
    pic_clear(SOC_PIC_BASE, PIC_IRQ_TIMER);
    led_timer_run = saved_timer_run;
    pic_enable_mask |= PIC_IRQ_TIMER;
    pic_enable(SOC_PIC_BASE, pic_enable_mask);
    if (led_timer_run)
        gpio_write(SOC_GPIO0_BASE, led_counter);
    irq_global_enable();
}

void soc_irq_handler(void)
{
    uint32_t pending = pic_pending(SOC_PIC_BASE);

    if (pending & PIC_IRQ_TIMER) {
        timer_clear(SOC_TIMER_BASE, 0xffffu);
        timer_irq_count++;
        if (led_timer_run) {
            led_counter++;
            gpio_write(SOC_GPIO0_BASE, led_counter);
        }
        dip_sample_request = 1u;
    }

    if (pending & PIC_IRQ_GPIO1) {
        uint32_t status = gpio_irq_status(SOC_GPIO1_BASE) & 0xffu;
        gpio_irq_clear(SOC_GPIO1_BASE, status);
        gpio_irq_count++;
        irq_events |= status;
        dip_sample_request = 1u;
    }

    if (pending & PIC_IRQ_EXT0) {
        ext0_irq_count++;
        irq_events |= EV_EXT0_LED_BLINK;
    }

    if (pending & PIC_IRQ_EXT1) {
        ext1_irq_count++;
        irq_events |= EV_EXT1_LED_SWEEP;
    }

    pic_clear(SOC_PIC_BASE, pending);
}

static void blink_all_leds(void)
{
    uint8_t saved_timer_run;
    uint8_t i;

    led_effect_begin(&saved_timer_run);
    for (i = 0u; i < 3u; i++) {
        gpio_write(SOC_GPIO0_BASE, 0xffu);
        led_blink_delay();
        gpio_write(SOC_GPIO0_BASE, 0x00u);
        led_blink_delay();
    }
    led_effect_end(saved_timer_run);
}

static void led_sweep_inner_outer_inner(void)
{
    static const uint8_t seq[] = {
        0x18u, 0x24u, 0x42u, 0x81u,
        0x42u, 0x24u, 0x18u
    };
    uint8_t saved_timer_run;
    uint8_t i;

    led_effect_begin(&saved_timer_run);
    for (i = 0u; i < sizeof(seq); i++) {
        gpio_write(SOC_GPIO0_BASE, seq[i]);
        led_blink_delay();
    }
    gpio_write(SOC_GPIO0_BASE, 0x00u);
    led_blink_delay();
    led_effect_end(saved_timer_run);
}

static void process_events(uint32_t events)
{
    if (events & EV_EXT0_LED_BLINK) {
        log_event("EXT0", "flash all 8 LEDs");
        lcd_event("EXT0 external IRQ",
                  "LED flash",
                  "PB0 pressed",
                  "RTL one-shot event");
        blink_all_leds();
    }

    if (events & EV_EXT1_LED_SWEEP) {
        log_event("EXT1", "LED sweep in-out-in");
        lcd_event("EXT1 external IRQ",
                  "LED sweep pattern",
                  "In -> out -> in",
                  "RTL one-shot event");
        led_sweep_inner_outer_inner();
    }

    if (events & EV_DIP0_LED_TIMER) {
        led_timer_run = (dip_shadow & EV_DIP0_LED_TIMER) ? 1u : 0u;
        if (!led_timer_run)
            gpio_write(SOC_GPIO0_BASE, 0u);
        log_event("DIP0", led_timer_run ? "timer LED enabled" :
                                             "timer LED disabled");
        lcd_event("DIP0 LED timer",
                  led_timer_run ? "Switch state: ON" : "Switch state: OFF",
                  led_timer_run ? "Timer drives LEDs" : "LED timer stopped",
                  led_timer_run ? "LED count running" : "LED output cleared");
    }

    if (events & EV_DIP1_LCD_TOGGLE) {
        if (lcd_ok) {
            lcd_enabled = (dip_shadow & EV_DIP1_LCD_TOGGLE) ? 1u : 0u;
            log_event("DIP1", lcd_enabled ? "LCD enabled" : "LCD disabled");
            if (lcd_enabled) {
                lcd_i2c_backlight(&lcd, 1);
                lcd_i2c_display(&lcd, 1);
                lcd_event("DIP1 LCD",
                          "Switch state: ON",
                          "Display enabled",
                          "Ready for events");
            } else {
                lcd_i2c_display(&lcd, 0);
                lcd_i2c_backlight(&lcd, 0);
            }
        } else {
            log_event("DIP1", "LCD not detected");
        }
    }

    if (events & EV_DIP2_UART_MSG) {
        log_event("DIP2", "manual UART message");
        uart_puts(SOC_UART_BASE, "UART demo message from DIP2\n");
        lcd_event("DIP2 UART",
                  "Message sent",
                  "Baud: 115200",
                  "Check serial log");
    }

    if (events & EV_DIP3_RESET) {
        timer_irq_count = 0u;
        gpio_irq_count = 0u;
        ext0_irq_count = 0u;
        ext1_irq_count = 0u;
        led_counter = 0u;
        have_keypair = 0u;
        have_capsule = 0u;
        gpio_write(SOC_GPIO0_BASE, 0u);
        log_event("DIP3", "counters and Kyber cache reset");
        lcd_screen("DIP3 reset",
                   "Counters cleared",
                   "Kyber cache cleared",
                   "Ready");
    }

    if (events & EV_DIP7_DEBUG) {
        debug_mode = (dip_shadow & EV_DIP7_DEBUG) ? 1u : 0u;
        log_event("DIP7", debug_mode ? "debug enabled" : "debug disabled");
        lcd_event("DIP7 debug",
                  debug_mode ? "Switch state: ON" : "Switch state: OFF",
                  debug_mode ? "UART debug enabled" : "UART debug disabled",
                  debug_mode ? "State log active" : "State log muted");
    }

    if (events & EV_DIP4_KEYGEN)
        (void)run_keygen_demo();

    if (events & EV_DIP5_ENCAPS)
        (void)run_encaps_demo();

    if (events & EV_DIP6_DECAPS)
        (void)run_decaps_demo();

    if (debug_mode)
        print_debug_state(events);
}

int main(void)
{
    uint16_t i2c_prescaler =
        (uint16_t)((SOC_CPU_HZ / (2u * 100000u)) - 1u);

    uart_init_div(SOC_UART_BASE, (uint16_t)SOC_UART_DIV);
    uart_puts(SOC_UART_BASE, "\n");
    uart_puts(SOC_UART_BASE, "========================================\n");
    uart_puts(SOC_UART_BASE, " Kyber SoC full peripheral demo\n");
    uart_puts(SOC_UART_BASE, "========================================\n");

    gpio_set_dir(SOC_GPIO0_BASE, 0xffu);
    gpio_write(SOC_GPIO0_BASE, SOC_DEMO_BOOT_MARK);
    gpio_set_dir(SOC_GPIO1_BASE, 0u);
    gpio_irq_config(SOC_GPIO1_BASE, 0xffu, 0xffu, 0xffu);
    dip_shadow = dip_active_mask(gpio_read(SOC_GPIO1_BASE));
    led_timer_run = (dip_shadow & EV_DIP0_LED_TIMER) ? 1u : 0u;
    debug_mode = (dip_shadow & EV_DIP7_DEBUG) ? 1u : 0u;
    if (!led_timer_run)
        gpio_write(SOC_GPIO0_BASE, 0u);

    pic_clear(SOC_PIC_BASE, 0xffffffffu);
    pic_enable_mask = PIC_IRQ_GPIO1 | PIC_IRQ_TIMER | PIC_IRQ_EXT0 | PIC_IRQ_EXT1;
    pic_enable(SOC_PIC_BASE, pic_enable_mask);

    timer_start(SOC_TIMER_BASE, 0u, 999u,
                (uint16_t)((SOC_CPU_HZ / 10000u) - 1u),
                TIMER_CTRL_IRQ_ENABLE | TIMER_CTRL_AUTO_RELOAD |
                TIMER_CTRL_PRESCALER);

    lcd_ok = (lcd_i2c_init(&lcd, SOC_I2C_BASE, LCD_ADDRESS,
                           i2c_prescaler) == 0) ? 1u : 0u;
    lcd_enabled = (lcd_ok && (dip_shadow & EV_DIP1_LCD_TOGGLE)) ? 1u : 0u;
    if (lcd_ok) {
        uart_puts(SOC_UART_BASE, "LCD I2C ready at 0x27\n");
        if (lcd_enabled) {
            lcd_i2c_backlight(&lcd, 1);
            lcd_i2c_display(&lcd, 1);
            lcd_boot();
        } else {
            lcd_i2c_display(&lcd, 0);
            lcd_i2c_backlight(&lcd, 0);
            uart_puts(SOC_UART_BASE, "LCD is OFF because DIP1 is low\n");
        }
    } else {
        uart_puts(SOC_UART_BASE, "LCD I2C not detected; UART demo continues\n");
    }

    memcpy(seed_keygen, ref_keygen_seed, KYBER_SEED_BYTES);
    memcpy(seed_encaps, ref_enc_seed, KYBER_SEED_BYTES);
    kyber_soft_reset();

    uart_puts(SOC_UART_BASE, "IRQ ready\n");
    uart_puts(SOC_UART_BASE, "GPIO ready\n");
    uart_puts(SOC_UART_BASE, "I2C ready\n");
    uart_puts(SOC_UART_BASE, "Kyber IP ready with C reference compare\n");
    uart_puts(SOC_UART_BASE, "EXT IRQ: PB0 x3, PB1 sweep\n");
    uart_puts(SOC_UART_BASE, "DIP map:\n");
    uart_puts(SOC_UART_BASE, "  DIP0 LED timer switch: up=ON, down=OFF\n");
    uart_puts(SOC_UART_BASE, "  DIP1 LCD switch: up=ON, down=OFF\n");
    uart_puts(SOC_UART_BASE, "  DIP2 UART message: run on OFF->ON only\n");
    uart_puts(SOC_UART_BASE, "  DIP3 reset counters/cache: run on OFF->ON only\n");
    uart_puts(SOC_UART_BASE, "  DIP4 Kyber keygen + CREF: run on OFF->ON only\n");
    uart_puts(SOC_UART_BASE, "  DIP5 Kyber encaps + CREF: run on OFF->ON only\n");
    uart_puts(SOC_UART_BASE, "  DIP6 Kyber decaps + CREF: run on OFF->ON only\n");
    uart_puts(SOC_UART_BASE, "  DIP7 debug switch: up=ON, down=OFF\n");
    uart_puts(SOC_UART_BASE, "External IRQ map:\n");
    uart_puts(SOC_UART_BASE, "  PB0/EXT0: blink 8 LEDs x3\n");
    uart_puts(SOC_UART_BASE, "  PB1/EXT1: sweep in-out-in\n");
    uart_puts(SOC_UART_BASE, "DIP0/DIP1/DIP7 follow switch level.\n");
    uart_puts(SOC_UART_BASE, "DIP2..DIP6 run on OFF->ON; return OFF to re-arm.\n");
    uart_puts(SOC_UART_BASE, "========================================\n");

    gpio_irq_clear(SOC_GPIO1_BASE, 0xffffffffu);
    pic_clear(SOC_PIC_BASE, 0xffffffffu);
    irq_global_enable();

    for (;;) {
        uint32_t irq_bits = take_events();
        uint32_t events = 0u;

        events |= irq_bits & EXT_EVENT_MASK;
        if ((irq_bits & 0xffu) != 0u)
            events |= sample_dip_events(irq_bits & 0xffu);
        if (take_dip_sample_request())
            events |= sample_dip_events(0xffu);
        if (events != 0u)
            process_events(events);
    }
}

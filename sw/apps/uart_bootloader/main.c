#include <stdint.h>
#include <stddef.h>

#include "soc_memory_map.h"
#include "soc_mmio.h"
#include "soc_platform.h"
#include "uart.h"

#define BOOTLOADER_IMEM_BASE      SOC_IMEM_BASE
#define BOOTLOADER_BOOT_END       (SOC_BOOT_BASE + SOC_BOOT_BYTES)
#define BOOTLOADER_SRAM_END       (SOC_SRAM_BASE + SOC_SRAM_BYTES)

#define BOOTLOADER_MARK_READY     0xB0u
#define BOOTLOADER_MARK_LOADING   0xB1u
#define BOOTLOADER_MARK_LOADED    0xB2u
#define BOOTLOADER_MARK_JUMP      0xB3u
#define BOOTLOADER_MARK_ERROR     0xE0u

static void gpio0_mark(uint8_t value)
{
    mmio_write32(SOC_GPIO0_BASE + GPIO_IO_DIR_OFFSET, 0xffu);
    mmio_write32(SOC_GPIO0_BASE + GPIO_IO_VAL_OFFSET, value);
}

static int recv_byte(void)
{
    int c;

    do {
        c = uart_getc(SOC_UART_BASE);
    } while (c < 0);
    return c & 0xff;
}

static void report_error(uint32_t code)
{
    gpio0_mark((uint8_t)(BOOTLOADER_MARK_ERROR | (code & 0x0fu)));
    uart_puts(SOC_UART_BASE, "ERR ");
    uart_puthex32(SOC_UART_BASE, code);
    uart_puts(SOC_UART_BASE, "\n");
}

static int is_space(int c)
{
    return (c == ' ') || (c == '\r') || (c == '\n') || (c == '\t');
}

static int hex_nibble(int c)
{
    if ((c >= '0') && (c <= '9'))
        return c - '0';
    if ((c >= 'a') && (c <= 'f'))
        return c - 'a' + 10;
    if ((c >= 'A') && (c <= 'F'))
        return c - 'A' + 10;
    return -1;
}

static int read_hex_byte(uint8_t *value)
{
    int hi = hex_nibble(recv_byte());
    int lo = hex_nibble(recv_byte());

    if ((hi < 0) || (lo < 0))
        return -1;
    *value = (uint8_t)(((uint32_t)hi << 4) | (uint32_t)lo);
    return 0;
}

static uint32_t read_u32_le(void)
{
    uint32_t value = 0u;
    uint32_t i;

    for (i = 0; i < 4u; i++)
        value |= (uint32_t)(uint8_t)recv_byte() << (i << 3);
    return value;
}

static int range_valid(uint32_t addr, uint32_t len)
{
    uint32_t end;

    if (len == 0u)
        return 1;
    end = addr + len - 1u;
    if (end < addr)
        return 0;

    if ((addr >= BOOTLOADER_IMEM_BASE) && (end < BOOTLOADER_BOOT_END))
        return 1;
    if ((addr >= SOC_SRAM_BASE) && (end < BOOTLOADER_SRAM_END))
        return 1;
    return 0;
}

static int write_payload_byte(uint32_t addr, uint8_t value)
{
    if (!range_valid(addr, 1u))
        return -1;
    mmio_write8(addr, value);
    return 0;
}

static void jump_to(uint32_t entry)
{
    void (*entry_fn)(void) = (void (*)(void))(uintptr_t)(entry & ~1u);

    gpio0_mark(BOOTLOADER_MARK_JUMP);
    uart_puts(SOC_UART_BASE, "JMP ");
    uart_puthex32(SOC_UART_BASE, entry & ~1u);
    uart_puts(SOC_UART_BASE, "\n");
    uart_wait_tx_idle(SOC_UART_BASE);
    mmio_barrier();
    entry_fn();

    for (;;) {
    }
}

static void handle_binary_packet(void)
{
    uint32_t dst;
    uint32_t len;
    uint32_t entry;
    uint32_t expected_sum;
    uint32_t actual_sum = 0u;
    uint32_t i;

    if ((recv_byte() != 'B') || (recv_byte() != 'L') || (recv_byte() != '1')) {
        report_error(0x10u);
        return;
    }

    dst = read_u32_le();
    len = read_u32_le();
    entry = read_u32_le();
    expected_sum = read_u32_le();

    if (!range_valid(dst, len) || !range_valid(entry, 1u)) {
        report_error(0x11u);
        return;
    }

    gpio0_mark(BOOTLOADER_MARK_LOADING);
    for (i = 0; i < len; i++) {
        uint8_t value = (uint8_t)recv_byte();

        actual_sum += value;
        if (write_payload_byte(dst + i, value) != 0) {
            report_error(0x12u);
            return;
        }
    }

    if (actual_sum != expected_sum) {
        report_error(0x13u);
        return;
    }

    gpio0_mark(BOOTLOADER_MARK_LOADED);
    uart_puts(SOC_UART_BASE, "OK BIN ");
    uart_puthex32(SOC_UART_BASE, len);
    uart_puts(SOC_UART_BASE, "\n");
    jump_to(entry);
}

static int wait_ihex_colon(int first_colon_seen)
{
    int c;

    if (first_colon_seen)
        return 0;

    do {
        c = recv_byte();
    } while (is_space(c));

    return (c == ':') ? 0 : -1;
}

static void handle_ihex_stream(void)
{
    uint32_t upper = 0u;
    uint32_t entry = 0u;
    uint32_t first_addr = 0u;
    int entry_seen = 0;
    int first_data_seen = 0;
    int first_colon_seen = 1;

    gpio0_mark(BOOTLOADER_MARK_LOADING);

    for (;;) {
        uint8_t len;
        uint8_t addr_hi;
        uint8_t addr_lo;
        uint8_t type;
        uint8_t checksum;
        uint8_t data[256];
        uint32_t sum;
        uint32_t addr;
        uint32_t i;

        if (wait_ihex_colon(first_colon_seen) != 0) {
            report_error(0x20u);
            return;
        }
        first_colon_seen = 0;

        if ((read_hex_byte(&len) != 0) ||
            (read_hex_byte(&addr_hi) != 0) ||
            (read_hex_byte(&addr_lo) != 0) ||
            (read_hex_byte(&type) != 0)) {
            report_error(0x21u);
            return;
        }

        sum = (uint32_t)len + (uint32_t)addr_hi + (uint32_t)addr_lo + (uint32_t)type;
        for (i = 0; i < len; i++) {
            if (read_hex_byte(&data[i]) != 0) {
                report_error(0x22u);
                return;
            }
            sum += data[i];
        }
        if (read_hex_byte(&checksum) != 0) {
            report_error(0x23u);
            return;
        }
        sum += checksum;
        if ((sum & 0xffu) != 0u) {
            report_error(0x24u);
            return;
        }

        addr = upper | (((uint32_t)addr_hi << 8) | (uint32_t)addr_lo);

        if (type == 0x00u) {
            if (!range_valid(addr, len)) {
                report_error(0x25u);
                return;
            }
            for (i = 0; i < len; i++) {
                if (write_payload_byte(addr + i, data[i]) != 0) {
                    report_error(0x26u);
                    return;
                }
            }
            if (!first_data_seen) {
                first_addr = addr;
                first_data_seen = 1;
            }
        } else if (type == 0x01u) {
            uint32_t target = entry_seen ? entry : first_addr;

            if (!first_data_seen || !range_valid(target, 1u)) {
                report_error(0x27u);
                return;
            }
            gpio0_mark(BOOTLOADER_MARK_LOADED);
            uart_puts(SOC_UART_BASE, "OK IHEX\n");
            jump_to(target);
        } else if (type == 0x04u) {
            if (len != 2u) {
                report_error(0x28u);
                return;
            }
            upper = (((uint32_t)data[0] << 8) | (uint32_t)data[1]) << 16;
        } else if (type == 0x05u) {
            if (len != 4u) {
                report_error(0x29u);
                return;
            }
            entry = ((uint32_t)data[0] << 24) |
                    ((uint32_t)data[1] << 16) |
                    ((uint32_t)data[2] << 8) |
                    (uint32_t)data[3];
            entry_seen = 1;
        }
    }
}

int main(void)
{
    uart_init_div(SOC_UART_BASE, (uint16_t)SOC_UART_DIV);
    gpio0_mark(BOOTLOADER_MARK_READY);
    uart_puts(SOC_UART_BASE, "KBL1 ready\n");

    for (;;) {
        int c = recv_byte();

        if (is_space(c))
            continue;
        if (c == 'K') {
            handle_binary_packet();
        } else if (c == ':') {
            handle_ihex_stream();
        } else {
            report_error(0x01u);
        }
    }
}

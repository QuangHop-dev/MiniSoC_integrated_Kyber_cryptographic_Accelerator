#include "lcd_i2c.h"
#include "i2c.h"

#define LCD_RS          0x01u
#define LCD_ENABLE      0x04u
#define LCD_BACKLIGHT   0x08u
#define LCD_TIMEOUT     1000000u

static void lcd_delay(volatile uint32_t count)
{
    while (count != 0u) {
        __asm__ volatile ("nop");
        count--;
    }
}

static int lcd_expander_write(lcd_i2c_t *lcd, uint8_t value)
{
    uint8_t address_byte = (uint8_t)(lcd->address << 1);
    int ret;

    ret = i2c_write_cmd(lcd->i2c_base, address_byte,
                        I2C_CMD_START, LCD_TIMEOUT);
    if (ret != 0)
        return ret;
    return i2c_write_cmd(lcd->i2c_base,
                         value | (lcd->backlight ? LCD_BACKLIGHT : 0u),
                         I2C_CMD_STOP, LCD_TIMEOUT);
}

static int lcd_pulse_enable(lcd_i2c_t *lcd, uint8_t value)
{
    int ret = lcd_expander_write(lcd, value | LCD_ENABLE);

    if (ret != 0)
        return ret;
    lcd_delay(200u);
    return lcd_expander_write(lcd, value & (uint8_t)~LCD_ENABLE);
}

static int lcd_write_nibble(lcd_i2c_t *lcd, uint8_t nibble, uint8_t mode)
{
    uint8_t value = (uint8_t)((nibble & 0x0fu) << 4) | mode;
    int ret = lcd_expander_write(lcd, value);

    if (ret != 0)
        return ret;
    return lcd_pulse_enable(lcd, value);
}

static int lcd_send(lcd_i2c_t *lcd, uint8_t value, uint8_t mode)
{
    int ret = lcd_write_nibble(lcd, (uint8_t)(value >> 4), mode);

    if (ret != 0)
        return ret;
    return lcd_write_nibble(lcd, value, mode);
}

static int lcd_command(lcd_i2c_t *lcd, uint8_t command)
{
    int ret = lcd_send(lcd, command, 0u);

    if ((command == 0x01u) || (command == 0x02u))
        lcd_delay(100000u);
    return ret;
}

int lcd_i2c_init(lcd_i2c_t *lcd, uint32_t i2c_base, uint8_t address,
                 uint16_t prescaler)
{
    int ret;

    if (lcd == 0)
        return -10;

    lcd->i2c_base = i2c_base;
    lcd->address = address;
    lcd->backlight = 1u;
    i2c_init(i2c_base, prescaler, 0);
    lcd_delay(500000u);

    ret = lcd_write_nibble(lcd, 0x03u, 0u);
    if (ret != 0) return ret;
    lcd_delay(200000u);
    ret = lcd_write_nibble(lcd, 0x03u, 0u);
    if (ret != 0) return ret;
    ret = lcd_write_nibble(lcd, 0x03u, 0u);
    if (ret != 0) return ret;
    ret = lcd_write_nibble(lcd, 0x02u, 0u);
    if (ret != 0) return ret;

    if (lcd_command(lcd, 0x28u) != 0) return -1;
    if (lcd_command(lcd, 0x08u) != 0) return -2;
    if (lcd_command(lcd, 0x01u) != 0) return -3;
    if (lcd_command(lcd, 0x06u) != 0) return -4;
    if (lcd_command(lcd, 0x0cu) != 0) return -5;
    return 0;
}

int lcd_i2c_clear(lcd_i2c_t *lcd)
{
    return lcd_command(lcd, 0x01u);
}

int lcd_i2c_home(lcd_i2c_t *lcd)
{
    return lcd_command(lcd, 0x02u);
}

int lcd_i2c_display(lcd_i2c_t *lcd, int enable)
{
    return lcd_command(lcd, enable ? 0x0cu : 0x08u);
}

int lcd_i2c_backlight(lcd_i2c_t *lcd, int enable)
{
    if (lcd == 0)
        return -10;
    lcd->backlight = enable ? 1u : 0u;
    return lcd_expander_write(lcd, 0u);
}

int lcd_i2c_set_cursor(lcd_i2c_t *lcd, uint8_t column, uint8_t row)
{
    static const uint8_t row_offsets[4] = {0x00u, 0x40u, 0x14u, 0x54u};

    if (row > 3u)
        row = 3u;
    return lcd_command(lcd, (uint8_t)(0x80u | (column + row_offsets[row])));
}

int lcd_i2c_putc(lcd_i2c_t *lcd, char value)
{
    return lcd_send(lcd, (uint8_t)value, LCD_RS);
}

int lcd_i2c_puts(lcd_i2c_t *lcd, const char *text)
{
    int ret;

    while (*text != '\0') {
        ret = lcd_i2c_putc(lcd, *text++);
        if (ret != 0)
            return ret;
    }
    return 0;
}

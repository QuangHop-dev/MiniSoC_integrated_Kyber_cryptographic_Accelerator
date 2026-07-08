#ifndef LCD_I2C_H
#define LCD_I2C_H

#include <stdint.h>

typedef struct {
    uint32_t i2c_base;
    uint8_t address;
    uint8_t backlight;
} lcd_i2c_t;

int lcd_i2c_init(lcd_i2c_t *lcd, uint32_t i2c_base, uint8_t address,
                 uint16_t prescaler);
int lcd_i2c_clear(lcd_i2c_t *lcd);
int lcd_i2c_home(lcd_i2c_t *lcd);
int lcd_i2c_display(lcd_i2c_t *lcd, int enable);
int lcd_i2c_backlight(lcd_i2c_t *lcd, int enable);
int lcd_i2c_set_cursor(lcd_i2c_t *lcd, uint8_t column, uint8_t row);
int lcd_i2c_putc(lcd_i2c_t *lcd, char value);
int lcd_i2c_puts(lcd_i2c_t *lcd, const char *text);

#endif

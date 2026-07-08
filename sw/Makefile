APP ?= kyber_demo
BUILD_DIR ?= build/$(APP)
LINKER ?= linker.ld
CROSS ?= riscv64-unknown-elf-
CC := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
SIZE := $(CROSS)size
PYTHON ?= python

TARGET := $(BUILD_DIR)/firmware

ARCH := rv32i
ABI := ilp32

CFLAGS := -march=$(ARCH) -mabi=$(ABI) -mstrict-align -msmall-data-limit=0
CFLAGS += -Os -g3 -ffreestanding -fno-builtin -fno-common
CFLAGS += -fdata-sections -ffunction-sections -Wall -Wextra -Werror
CFLAGS += -Iinclude

ASFLAGS := $(CFLAGS)
LDFLAGS := -T $(LINKER) -nostdlib -Wl,--gc-sections -Wl,-Map,$(TARGET).map

COMMON_SRCS := \
	crt0.S \
	trap.S \
	lib/gpio.c \
	lib/i2c.c \
	lib/irq.c \
	lib/kyber.c \
	lib/lcd_i2c.c \
	lib/mini_libc.c \
	lib/pic.c \
	lib/timer.c \
	lib/uart.c

APP_SRCS := apps/$(APP)/main.c
SRCS := $(COMMON_SRCS) $(APP_SRCS)
OBJS := $(patsubst %.c,$(BUILD_DIR)/%.o,$(patsubst %.S,$(BUILD_DIR)/%.o,$(SRCS)))
DEPS := $(OBJS:.o=.d)

.PHONY: all clean

all: $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).ihex $(TARGET).lst
	$(SIZE) $(TARGET).elf

$(TARGET).elf: $(OBJS) $(LINKER)
	$(CC) $(CFLAGS) $(OBJS) $(LDFLAGS) -o $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).hex: $(TARGET).bin tools/bin_to_memh.py
	$(PYTHON) tools/bin_to_memh.py $< $@

$(TARGET).ihex: $(TARGET).elf
	$(OBJCOPY) -O ihex $< $@

$(TARGET).lst: $(TARGET).elf
	$(OBJDUMP) -drwC $< > $@

$(BUILD_DIR)/%.o: %.c
	@$(PYTHON) -c "import os,sys; os.makedirs(sys.argv[1], exist_ok=True)" $(dir $@)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/%.o: %.S
	@$(PYTHON) -c "import os,sys; os.makedirs(sys.argv[1], exist_ok=True)" $(dir $@)
	$(CC) $(ASFLAGS) -MMD -MP -c $< -o $@

clean:
	$(PYTHON) -c "import shutil; shutil.rmtree('build', ignore_errors=True)"

-include $(DEPS)

CROSS_COMPILE ?= /home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-
HOSTCC ?= cc
CC := $(CROSS_COMPILE)gcc
STRIP := $(CROSS_COMPILE)strip
TARGET := lcd_tetris

CFLAGS := -Os -std=gnu99 -Wall -Wextra -ffunction-sections -fdata-sections
LDFLAGS := -Wl,--gc-sections

.PHONY: all clean check host-test

all: $(TARGET)

$(TARGET): main.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<
	$(STRIP) $@

check: $(TARGET)
	file $(TARGET)
	$(CROSS_COMPILE)readelf -h $(TARGET) | sed -n '1,24p'

host-test: main.c
	$(HOSTCC) -O2 -std=gnu99 -Wall -Wextra -o /tmp/lcd_tetris_host_test $<
	/tmp/lcd_tetris_host_test --self-test

clean:
	rm -f $(TARGET) /tmp/lcd_tetris_host_test

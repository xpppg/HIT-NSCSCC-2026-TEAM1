CROSS_COMPILE ?= /home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-
CC := $(CROSS_COMPILE)gcc
STRIP := $(CROSS_COMPILE)strip

CFLAGS := -O2 -Wall -Wextra
TARGET := i2s_irq_monitor

.PHONY: all clean

all: $(TARGET)

$(TARGET): main.c
	$(CC) $(CFLAGS) -static -o $@ $<
	$(STRIP) $@

clean:
	$(RM) $(TARGET)

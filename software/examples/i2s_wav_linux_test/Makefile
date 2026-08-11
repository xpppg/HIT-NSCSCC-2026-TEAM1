CROSS_COMPILE ?= /home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-
CC := $(CROSS_COMPILE)gcc
STRIP := $(CROSS_COMPILE)strip
TARGET := i2s_wav_test
.PHONY: all clean
all: $(TARGET)
$(TARGET): main.c
	$(CC) -Os -std=gnu99 -Wall -Wextra -o $@ $<
	$(STRIP) $@
clean:
	rm -f $(TARGET)

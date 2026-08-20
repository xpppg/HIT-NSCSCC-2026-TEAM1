CROSS_COMPILE ?= /home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-
CC := $(CROSS_COMPILE)gcc
STRIP := $(CROSS_COMPILE)strip

TARGET := touch_event_test

.PHONY: all clean check

all: $(TARGET)

$(TARGET): main.c
	$(CC) -Os -std=gnu99 -Wall -Wextra -o $@ $<
	$(STRIP) $@

check: $(TARGET)
	file $(TARGET)

clean:
	rm -f $(TARGET)

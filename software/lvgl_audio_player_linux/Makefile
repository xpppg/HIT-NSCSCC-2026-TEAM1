CROSS_COMPILE ?= /home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-
CC := $(CROSS_COMPILE)gcc
STRIP := $(CROSS_COMPILE)strip

TARGET := lvgl_audio_player
BUILD_DIR := build
LVGL_DIR ?= ../lvgl_test_linux/vendor
LVGL_SRCS := $(shell find $(LVGL_DIR)/src -type f -name '*.c')
SRCS := main.c $(LVGL_SRCS)
OBJS := $(addprefix $(BUILD_DIR)/,$(SRCS:.c=.o))

CPPFLAGS := -DLV_CONF_INCLUDE_SIMPLE -I. -I$(LVGL_DIR)
CFLAGS := -Os -std=gnu99 -ffunction-sections -fdata-sections \
	-Wall -Wextra -Wno-unused-parameter
LDFLAGS := -Wl,--gc-sections
LDLIBS := -lm

.PHONY: all clean check

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)
	$(STRIP) $@

$(BUILD_DIR)/%.o: %.c lv_conf.h
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

check: $(TARGET)
	file $(TARGET)
	readelf -h $(TARGET) | sed -n '1,24p'
	readelf -d $(TARGET) | grep NEEDED || true

clean:
	rm -rf $(BUILD_DIR) $(TARGET)

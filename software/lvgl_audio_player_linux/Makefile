CROSS_COMPILE ?= /home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-
CC := $(CROSS_COMPILE)gcc
STRIP := $(CROSS_COMPILE)strip

TARGET := lvgl_audio_player
BUILD_DIR := build
LVGL_DIR ?= ../lvgl_test_linux/vendor
BUILDROOT_STAGING ?= /home/xpg/chiplab-old/la32r-buildroot/output/staging
LVGL_SRCS := $(shell find $(LVGL_DIR)/src -type f -name '*.c')
SRCS := main.c $(LVGL_SRCS)
OBJS := $(addprefix $(BUILD_DIR)/,$(SRCS:.c=.o))

CPPFLAGS := -DLV_CONF_INCLUDE_SIMPLE -I. -I$(LVGL_DIR) \
	-I$(BUILDROOT_STAGING)/usr/include
CFLAGS := -Os -std=gnu99 -ffunction-sections -fdata-sections \
	-Wall -Wextra -Wno-unused-parameter
LDFLAGS := -Wl,--gc-sections \
	-Wl,-rpath-link,$(BUILDROOT_STAGING)/usr/lib
# Link the target shared object explicitly.  Adding the whole Buildroot staging
# lib directory with -L would make this standalone toolchain consume the
# staging libc linker script, whose absolute paths belong to Buildroot's
# sysroot and cannot be resolved by the standalone compiler driver.
LDLIBS := $(BUILDROOT_STAGING)/usr/lib/libasound.so.2.0.0 -lpthread -lm

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

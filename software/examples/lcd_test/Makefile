TARGET = lcd_test

CFLAGS += -O2 -g -Wall -Wextra

C_SRCS := $(wildcard ./*.c)

LCD_INIT_COE = ../../../IP/LCD/rst_rom.coe
LCD_INIT_HEADER = lcd_init_sequence.h
LCD_FONT_COE = ../../../IP/LCD/font_rom.coe
LCD_FONT_HEADER = lcd_font_16x32.h

OBJDIR = obj
COMMON_DIR = ../../bsp
GCC_DIR = ../../../toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0
PICOLIBC_DIR = ../../../toolchains/picolibc

include ../../bsp/common.mk

$(LCD_INIT_HEADER): $(LCD_INIT_COE) coe_to_c.awk
	awk -f coe_to_c.awk $(LCD_INIT_COE) > $@

$(LCD_FONT_HEADER): $(LCD_FONT_COE) font_coe_to_c.awk
	awk -f font_coe_to_c.awk $(LCD_FONT_COE) > $@

main.o main.uboot.o: $(LCD_INIT_HEADER) $(LCD_FONT_HEADER)

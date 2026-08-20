TARGET = i2s_wav
CFLAGS += -O2 -g -Wall -Wextra
C_SRCS := ./main.c
OBJDIR = obj
COMMON_DIR = ../../bsp
GCC_DIR = ../../../toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0
PICOLIBC_DIR = ../../../toolchains/picolibc

.PHONY: wav freq
wav: $(OBJDIR)/i2s_test_melody.wav

freq: $(OBJDIR)/i2s_frequency_test.wav

$(OBJDIR)/i2s_test_melody.wav: make_test_wav.c
	mkdir -p $(OBJDIR)
	gcc -O2 -Wall -Wextra -o $(OBJDIR)/make_test_wav make_test_wav.c
	$(OBJDIR)/make_test_wav $@

$(OBJDIR)/i2s_frequency_test.wav: make_test_wav.c
	mkdir -p $(OBJDIR)
	gcc -O2 -Wall -Wextra -o $(OBJDIR)/make_test_wav make_test_wav.c
	$(OBJDIR)/make_test_wav $@ freq

include ../../bsp/common.mk


LA32R_GCC     := loongarch32r-linux-gnusf-gcc
LA32R_AS      := loongarch32r-linux-gnusf-as
LA32R_GXX     := loongarch32r-linux-gnusf-g++
LA32R_OBJDUMP := loongarch32r-linux-gnusf-objdump
LA32R_GDB     := loongarch32r-linux-gnusf-gdb
LA32R_AR      := loongarch32r-linux-gnusf-ar
LA32R_OBJCOPY := loongarch32r-linux-gnusf-objcopy
LA32R_READELF := loongarch32r-linux-gnusf-readelf

.PHONY: all
all: $(TARGET)

#TODO: 根据Cache实际情况调整下述参数，以在start.S中生成正确的Cache初始化代码
CFLAGS += -Dhas_cache=1 -Dcache_index_depth=0x100 -Dcache_offset_width=0x4 -Dcache_way=2
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -nostartfiles -nostdlib -nostdinc -static -fno-builtin 
CFLAGS += -DCLOCKS_PER_SEC=CORE_CLOCKS_PER_SEC -D_CLOCKS_PER_SEC_=CORE_CLOCKS_PER_SEC -DCPU_COUNT_PER_US=100

#若使用 newlib , 将下面的 -lsemihost 替换为 -lgloss
LDFLAGS +=  	-T $(LINKER_SCRIPT) \
				-Wl,--gc-sections -Wl,--check-sections \
				-lc -lm -lg -lsemihost -lgcc -L$(PICOLIBC_DIR)/lib

QEMU_LDFLAGS +=	-T $(QEMU_LINKER_SCRIPT) \
				-Wl,--gc-sections -Wl,--check-sections \
				-lc -lm -lg -lsemihost -lgcc -L$(PICOLIBC_DIR)/lib

LINKER_SCRIPT := $(COMMON_DIR)/env/separate.lds
QEMU_LINKER_SCRIPT := $(COMMON_DIR)/env/qemu.lds
UBOOT_LINKER_SCRIPT := $(COMMON_DIR)/env/uboot_uncached.lds
UBOOT_START_SRC := $(COMMON_DIR)/env/start_uboot.S

APP_ASM_SRCS := $(ASM_SRCS)
ASM_SRCS += $(COMMON_DIR)/env/start.S 

C_SRCS   += $(COMMON_DIR)/drivers/confreg_time.c

INCLUDES += -I$(COMMON_DIR)/include \
			-I$(PICOLIBC_DIR)/include \
			-I$(GCC_DIR)/lib/gcc/loongarch32r-linux-gnusf/8.3.0/include \
			-I$(GCC_DIR)/lib/gcc/loongarch32r-linux-gnusf/8.3.0/include-fixed

ASM_OBJS := $(ASM_SRCS:.S=.o)
C_OBJS := $(C_SRCS:.c=.o)
QEMU_ASM_OBJS := $(ASM_SRCS:.S=.out)
QEMU_C_OBJS := $(C_SRCS:.c=.out)
UBOOT_APP_ASM_OBJS := $(APP_ASM_SRCS:.S=.uboot.o)
UBOOT_C_OBJS := $(C_SRCS:.c=.uboot.o)
UBOOT_START_OBJ := $(UBOOT_START_SRC:.S=.uboot.o)
UBOOT_LINK_OBJS := $(UBOOT_START_OBJ) $(UBOOT_APP_ASM_OBJS) $(UBOOT_C_OBJS)
UBOOT_CFLAGS := $(CFLAGS) -Uhas_cache -Dhas_cache=0 -DBOOT_FROM_UBOOT=1

LINK_OBJS += $(ASM_OBJS) $(C_OBJS)
LINK_DEPS += $(LINKER_SCRIPT)
QEMU_LINK_OBJS += $(QEMU_ASM_OBJS) $(QEMU_C_OBJS)

CLEAN_OBJS += $(OBJDIR)/$(TARGET).elf $(LINK_OBJS) $(OBJDIR)/$(TARGET).s $(OBJDIR)/$(TARGET).bin $(OBJDIR)/convert $(OBJDIR)/axi_ram.coe $(OBJDIR)/axi_ram.mif $(OBJDIR)/rom.vlog
CLEAN_OBJS += $(OBJDIR)/$(TARGET)_uboot.elf $(OBJDIR)/$(TARGET)_uboot.bin $(OBJDIR)/$(TARGET)_uboot.s $(UBOOT_LINK_OBJS)

$(TARGET): $(LINK_OBJS) $(LINK_DEPS) convert Makefile
	$(LA32R_GCC) $(CFLAGS) $(INCLUDES) $(LINK_OBJS) -o $(OBJDIR)/$@.elf $(LDFLAGS)
	$(LA32R_OBJCOPY) -O binary $(OBJDIR)/$@.elf $(OBJDIR)/$@.bin
	$(LA32R_OBJDUMP) --disassemble-all -S $(OBJDIR)/$@.elf > $(OBJDIR)/$@.s
	$(OBJDIR)/convert $@.bin $(OBJDIR)/
	rm -f $(LINK_OBJS)
	rm -f $(OBJDIR)/convert

$(ASM_OBJS): %.o: %.S
	$(LA32R_GCC) $(CFLAGS) $(INCLUDES) -c -o $@ $< 

$(C_OBJS): %.o: %.c
	$(LA32R_GCC) $(CFLAGS) $(INCLUDES) -c -o $@ $< 

.PHONY: uboot
uboot: $(OBJDIR)/$(TARGET)_uboot.elf

$(OBJDIR)/$(TARGET)_uboot.elf: $(UBOOT_LINK_OBJS) $(UBOOT_LINKER_SCRIPT) Makefile
	mkdir -p $(OBJDIR)/
	$(LA32R_GCC) $(UBOOT_CFLAGS) $(INCLUDES) $(UBOOT_LINK_OBJS) -o $@ \
		-T $(UBOOT_LINKER_SCRIPT) -Wl,--gc-sections -Wl,--check-sections \
		-lc -lm -lg -lsemihost -lgcc -L$(PICOLIBC_DIR)/lib
	$(LA32R_OBJCOPY) -O binary $@ $(OBJDIR)/$(TARGET)_uboot.bin
	$(LA32R_OBJDUMP) --disassemble-all -S $@ > $(OBJDIR)/$(TARGET)_uboot.s
	rm -f $(UBOOT_LINK_OBJS)

$(UBOOT_START_OBJ) $(UBOOT_APP_ASM_OBJS): %.uboot.o: %.S
	$(LA32R_GCC) $(UBOOT_CFLAGS) $(INCLUDES) -c -o $@ $<

$(UBOOT_C_OBJS): %.uboot.o: %.c
	$(LA32R_GCC) $(UBOOT_CFLAGS) $(INCLUDES) -c -o $@ $<

convert: $(COMMON_DIR)/env/convert.c
	mkdir -p $(OBJDIR)/
	gcc -o $(OBJDIR)/convert $(COMMON_DIR)/env/convert.c

.PHONY: qemu
qemu: $(QEMU_LINK_OBJS) $(LINK_DEPS) convert Makefile
	$(LA32R_GCC) $(CFLAGS) -DUSE_CPU_CLOCK_COUNT $(INCLUDES) $(QEMU_LINK_OBJS) -o $(OBJDIR)/$(TARGET).elf $(QEMU_LDFLAGS)
	$(LA32R_OBJCOPY) -O binary $(OBJDIR)/$(TARGET).elf $(OBJDIR)/$(TARGET).bin
	$(LA32R_OBJDUMP) --disassemble-all -S $(OBJDIR)/$(TARGET).elf > $(OBJDIR)/$(TARGET).s
	$(OBJDIR)/convert $(TARGET).bin $(OBJDIR)/
	rm -f $(QEMU_LINK_OBJS)
	rm -f $(OBJDIR)/convert
	qemu-system-loongarch32 \
        -M ls3a5k32 \
        -kernel  $(OBJDIR)/$(TARGET).elf\
        -nographic \
        -serial mon:stdio \
        -m 256 \
        -append "console=ttyS0,115200 rdinit=/init loglevel=9" \
        -monitor tcp::4278,server,nowait \
        -smp 1  \
        -gdb tcp::5295 

$(QEMU_ASM_OBJS): %.out: %.S
	$(LA32R_GCC) $(CFLAGS) -DUSE_CPU_CLOCK_COUNT $(INCLUDES) -c -o $@ $< 

$(QEMU_C_OBJS): %.out: %.c
	$(LA32R_GCC) $(CFLAGS) -DUSE_CPU_CLOCK_COUNT $(INCLUDES) -c -o $@ $< 

.PHONY: clean
clean:
	rm -f $(CLEAN_OBJS)

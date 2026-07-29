#!/bin/bash
# ============================================================
# U-Boot 仿真启动脚本
# 支持两种 uboot.bin 格式:
#   1. ELF 格式: 自动用 readelf 提取入口地址
#   2. 裸二进制: 需要手动指定 UBOOT_ENTRY_ADDRESS
# ============================================================

# 自动检测 u-boot.bin 或 uboot.bin
if [ -f "u-boot.bin" ]; then
    UBOOT_BIN="u-boot.bin"
elif [ -f "uboot.bin" ]; then
    UBOOT_BIN="uboot.bin"
else
    echo "=============================================="
    echo "  ERROR: 未找到 u-boot.bin 或 uboot.bin !"
    echo "  请将你的 U-Boot 文件复制到:"
    echo "  $(pwd)"
    echo "=============================================="
    exit 1
fi

echo "Using: $UBOOT_BIN"

# --- 判断是 ELF 还是裸二进制 ---
FILE_TYPE=$(file "$UBOOT_BIN" 2>/dev/null)

if echo "$FILE_TYPE" | grep -q "ELF"; then
    echo "检测到 ELF 格式的 U-Boot"
    KERNEL_ENTRY_INFO=$(loongarch32r-linux-gnusf-readelf -s "$UBOOT_BIN" 2>/dev/null | grep "_start\|uboot_entry\|start" | head -1)
    if [ -z "$KERNEL_ENTRY_INFO" ]; then
        # readelf -h 取 entry point
        ENTRY_ADDR=$(loongarch32r-linux-gnusf-readelf -h "$UBOOT_BIN" 2>/dev/null | grep "Entry point" | awk '{print $NF}')
    else
        ENTRY_ADDR=$(echo ${KERNEL_ENTRY_INFO: 8: 8})
    fi
    echo "U-Boot Entry: 0x$ENTRY_ADDR"
else
    echo "检测到裸二进制格式的 U-Boot"
    # 默认入口 = 加载基地址 (DMW1: 0xa0000000 映射到物理 0x0)
    # 若 uboot.bin 加载在物理 0x300000,则虚拟地址 = 0xa0300000
    if [ -n "$UBOOT_ENTRY_ADDRESS" ]; then
        ENTRY_ADDR="${UBOOT_ENTRY_ADDRESS#0x}"
    else
        # 默认: 加载到物理 0x300000, DMW1 映射 → 虚拟 0xa0300000
        ENTRY_ADDR="a0300000"
        echo "使用默认入口: 0x$ENTRY_ADDR (物理 0x300000)"
    fi
    # 裸二进制的物理加载地址
    UBOOT_LOAD_PHYS="${UBOOT_LOAD_ADDR:-0x300000}"
fi

ENTRY_ADDR_CLEAN="${ENTRY_ADDR#0x}"

echo "=============================================="
echo "  U-Boot Entry  : 0x$ENTRY_ADDR_CLEAN"
echo "  Load Address  : ${UBOOT_LOAD_PHYS:-0x300000} (物理)"
echo "=============================================="

# --- 编译 start.S (带入口地址宏) ---
loongarch32r-linux-gnusf-gcc -DUBOOT_ENTRY_ADDRESS=0x${ENTRY_ADDR_CLEAN} -c start.S -o start.o

loongarch32r-linux-gnusf-objdump -d start.o > start.s

loongarch32r-linux-gnusf-objcopy -O binary -j .text start.o start.bin

# --- 处理 U-Boot 二进制 ---
if echo "$FILE_TYPE" | grep -q "ELF"; then
    # ELF: 提取所有需要的 section
    loongarch32r-linux-gnusf-objcopy -O binary \
        -j .text -j __ex_table -j .notes -j .rodata -j __param -j .sdata \
        -j __modver -j .data -j .data..page_aligned -j .init.text -j .init.data \
        -j .exit.text "$UBOOT_BIN" uboot_raw.bin
else
    # 裸二进制: 直接复制
    cp "$UBOOT_BIN" uboot_raw.bin
fi

# --- 准备输出 ---
mkdir -p obj
mv start.s    ./obj/
mv start.bin  ./obj/
mv uboot_raw.bin ./obj/
cp init_5f.txt ./obj/
cp init_8f.txt ./obj/
rm -f start.o

# --- 编译 convert.c 并生成 rom.vlog ---
gcc ./convert.c -o convert
mv ./convert ./obj/
cd ./obj
./convert
cd ..

echo "=============================================="
echo "  rom.vlog 已生成在 ./obj/ 目录"
echo "=============================================="

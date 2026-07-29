#include "regdef.h"

.text
.globl _boot
_boot:

// ================================================================
// 1. 初始化 UART (基地址 0x1fe001e0)
// ================================================================
    li.w       t1, 0x1fe001e0

    // FIFO 控制: 启用 + 复位收发 FIFO + 触发级别 4
    li.w       t2, 0x47
    st.b       t2, t1, 2

    // 行控制: 使能波特率除数锁存
    li.w       t2, 0x80
    st.b       t2, t1, 3

    // 波特率除数 (115200 @ 33MHz → divisor=18=0x12)
    li.w       t2, 0x1
    st.b       t2, t1, 0       // LSB
    li.w       t2, 0x0
    st.b       t2, t1, 1       // MSB

    // 数据格式: 8N1
    li.w       t2, 0x3
    st.b       t2, t1, 3

    // Modem 控制
    li.w       t2, 0x0
    st.b       t2, t1, 4

// ================================================================
// 2. 打印启动信息 "U-Boot booting..."
// ================================================================
    li.w       t5, 0x0a        // \n
    bl         print_char
    li.w       t5, 0x55        // U
    bl         print_char
    li.w       t5, 0x2d        // -
    bl         print_char
    li.w       t5, 0x42        // B
    bl         print_char
    li.w       t5, 0x6f        // o
    bl         print_char
    li.w       t5, 0x6f        // o
    bl         print_char
    li.w       t5, 0x74        // t
    bl         print_char
    li.w       t5, 0x20        //
    bl         print_char
    li.w       t5, 0x62        // b
    bl         print_char
    li.w       t5, 0x6f        // o
    bl         print_char
    li.w       t5, 0x6f        // o
    bl         print_char
    li.w       t5, 0x74        // t
    bl         print_char
    li.w       t5, 0x69        // i
    bl         print_char
    li.w       t5, 0x6e        // n
    bl         print_char
    li.w       t5, 0x67        // g
    bl         print_char
    li.w       t5, 0x2e        // .
    bl         print_char
    li.w       t5, 0x2e        // .
    bl         print_char
    li.w       t5, 0x2e        // .
    bl         print_char
    li.w       t5, 0x0a        // \n
    bl         print_char

// ================================================================
// 3. 配置 CSR (与 Linux 示例相同的 DMW 映射)
//    DMW0: 0x19 → 映射 0x00000000 区域
//    DMW1: 0xa0000009 → 虚拟 0xa0000000 映射到物理 0x00000000
//    CSR 0x180=DMW0, CSR 0x181=DMW1, CSR 0x0=CRMD
// ================================================================
    // 使能 DA=1, PG=1 (直接地址翻译 + 页表使能)
    li.w       $r12, 0xa0000001
    csrwr      $r12, 0x180      // DMW0
    li.w       $r12, 0x00000001
    csrwr      $r12, 0x181      // DMW1 (备用)

    // CRMD: 设置 PLV=0, IE=0, DA=1, PG=1
    li.w       $r12, 0x10
    li.w       $r13, 0x18
    csrxchg    $r12, $r13, 0x0

// ================================================================
// 4. 跳转到 U-Boot 入口
//    UBOOT_ENTRY_ADDRESS 由 script.sh 通过 -D 传入
//    若为裸二进制, 默认 0xa0300000 (物理 0x300000)
// ================================================================
    li.w       $r12, UBOOT_ENTRY_ADDRESS
    jirl       $r0, $r12, 0     // 跳转到 U-Boot

// ================================================================
// 5. 打印字符辅助函数
// ================================================================
print_char:
    // 等待 UART 发送就绪 (LSR bit5=1)
1:
    ld.b       t2, t1, 5
    andi       t2, t2, 0x20
    beq        t2, zero, 1b
    st.b       t5, t1, 0        // 发送字符
    jirl       zero, ra, 0

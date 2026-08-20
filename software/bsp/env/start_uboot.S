#include "regdef.h"

/*
 * U-Boot bootelf entry for the uncached 0x8... DMW window.
 * U-Boot's address mapping and UART setup are deliberately preserved.
 */

    .section .init
    .globl _start_uboot
    .type _start_uboot, @function
    .extern main

_start_uboot:
    li.w      a0, 0x53              /* S: startup entered */
    bl        uboot_debug_char

    /* Copy initialized data from its ELF load address to the data area. */
    la.local t0, _data_lma
    la.local t1, _data
    la.local t2, _edata
    bgeu      t1, t2, 2f
1:
    ld.w      t3, t0, 0
    st.w      t3, t1, 0
    addi.w    t0, t0, 4
    addi.w    t1, t1, 4
    bltu      t1, t2, 1b
2:

    /* Clear BSS. */
    la.local t0, __bss_start
    la.local t1, _end
    bgeu      t0, t1, 2f
1:
    st.w      zero, t0, 0
    addi.w    t0, t0, 4
    bltu      t0, t1, 1b
2:

    li.w      a0, 0x44              /* D: data and BSS ready */
    bl        uboot_debug_char

    la.local  sp, _stack
    la.local  t0, uboot_trap_handler
    csrwr     t0, csr_eentry

    li.w      a0, 0x4d              /* M: entering main */
    bl        uboot_debug_char

    move      a0, zero
    move      a1, zero
    bl        main

    li.w      a0, 0x52              /* R: main returned */
    bl        uboot_debug_char
1:
    b         1b

uboot_trap_handler:
    li.w      a0, 0x45              /* E: unexpected exception */
    bl        uboot_debug_char
1:
    b         1b

uboot_debug_char:
    li.w      t0, 0x9fe001e0
1:
    ld.bu     t1, t0, 5
    andi      t1, t1, 0x20
    beq       t1, zero, 1b
    st.b      a0, t0, 0
    jirl      zero, ra, 0

    .size _start_uboot, .-_start_uboot

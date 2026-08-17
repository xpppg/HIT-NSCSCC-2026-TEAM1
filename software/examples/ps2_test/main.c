#include <stdint.h>
#include <stdio.h>

#include "confreg_time.h"

#ifdef BOOT_FROM_UBOOT
unsigned long UART_BASE = 0x9fe001e0UL;
unsigned long CONFREG_UART_BASE = 0x9fd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0x9fd0e000UL;
#define PS2_BASE 0x9fa40000UL
#else
unsigned long UART_BASE = 0xbfe001e0UL;
unsigned long CONFREG_UART_BASE = 0xbfd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0xbfd0e000UL;
#define PS2_BASE 0xbfa40000UL
#endif
unsigned long CONFREG_CLOCKS_PER_SEC = 33000000UL;
unsigned long CORE_CLOCKS_PER_SEC = 50000000UL;

#define REG32(offset) (*(volatile uint32_t *)(PS2_BASE + (offset)))
#define PS2_DATA      REG32(0x00)
#define PS2_STATUS    REG32(0x04)
#define PS2_CTRL      REG32(0x08)
#define PS2_DEBUG     REG32(0x10)
#define PS2_ERROR     0x01U
#define PS2_BUSY      0x02U
#define PS2_COUNT(v)  (((v) >> 8) & 0x1fU)

static void io_barrier(void)
{
    __asm__ volatile("dbar 0" ::: "memory");
}

static void delay_ms(uint32_t milliseconds)
{
    uint32_t start = (uint32_t)get_confreg_clock_count();
    uint32_t cycles = milliseconds *
                      (uint32_t)(CONFREG_CLOCKS_PER_SEC / 1000UL);

    while ((uint32_t)((uint32_t)get_confreg_clock_count() - start) < cycles)
        ;
}

static void print_debug(uint32_t status)
{
    uint32_t debug = PS2_DEBUG;

    printf("PS/2 error, STATUS=0x%08x\n", status);
    printf("DEBUG=0x%08x: reason=%u edges=%u busy=%u DATA=%u CLK=%u\n",
           debug, (unsigned int)((debug >> 8) & 3U),
           (unsigned int)((debug >> 3) & 0x1fU),
           (unsigned int)((debug >> 2) & 1U),
           (unsigned int)((debug >> 1) & 1U),
           (unsigned int)(debug & 1U));
}

static int wait_for_fa(uint32_t timeout_ms)
{
    uint32_t start = (uint32_t)get_confreg_clock_count();
    uint32_t cycles = timeout_ms *
                      (uint32_t)(CONFREG_CLOCKS_PER_SEC / 1000UL);

    while ((uint32_t)((uint32_t)get_confreg_clock_count() - start) < cycles) {
        uint32_t status = PS2_STATUS;

        while (PS2_COUNT(status) != 0U) {
            uint8_t value = (uint8_t)(PS2_DATA & 0xffU);
            printf("received = 0x%02x\n", (unsigned int)value);
            if (value == 0xfaU)
                return 0;
            status = PS2_STATUS;
        }
        if (status & PS2_ERROR) {
            print_debug(status);
            return -1;
        }
    }

    printf("Timed out waiting for keyboard response 0xfa\n");
    print_debug(PS2_STATUS);
    return -1;
}

static int send_byte(uint8_t value)
{
    uint32_t start = (uint32_t)get_confreg_clock_count();
    uint32_t timeout_cycles =
        100U * (uint32_t)(CONFREG_CLOCKS_PER_SEC / 1000UL);

    while (PS2_STATUS & PS2_BUSY) {
        if ((uint32_t)((uint32_t)get_confreg_clock_count() - start) >=
            timeout_cycles) {
            printf("PS/2 stayed busy before 0x%02x\n", (unsigned int)value);
            return -1;
        }
    }

    PS2_STATUS = 3U;
    PS2_DATA = value;
    io_barrier();
    printf("sent     = 0x%02x\n", (unsigned int)value);
    return wait_for_fa(100U);
}

int main(void)
{
    uint32_t status;

    printf("\nPS/2 raw scan-code input test\n");
    printf("PS/2 base: 0x%08lx\n", PS2_BASE);
    printf("Set-2: F0=release prefix, E0=extended-key prefix\n");

    /* Reset the local FIFO/status, then enable the bidirectional host. */
    PS2_CTRL = 2U;
    PS2_CTRL = 1U;
    io_barrier();
    delay_ms(20U);

    printf("Send F4 (enable scanning) and wait for FA ACK...\n");
    if (send_byte(0xf4U) == 0)
        printf("Keyboard scanning enabled; press and release keys.\n");
    else
        printf("F4 failed; continuing in receive-only diagnostic mode.\n");

    for (;;) {
        status = PS2_STATUS;

        while (PS2_COUNT(status) != 0U) {
            uint8_t value = (uint8_t)(PS2_DATA & 0xffU);

            if (value == 0xe0U)
                printf("scan = 0xe0  (extended prefix)\n");
            else if (value == 0xf0U)
                printf("scan = 0xf0  (release prefix)\n");
            else
                printf("scan = 0x%02x\n", (unsigned int)value);

            status = PS2_STATUS;
        }

        if (status & 3U) {
            print_debug(status);
            PS2_STATUS = status & 3U;
            io_barrier();
        }
    }
}

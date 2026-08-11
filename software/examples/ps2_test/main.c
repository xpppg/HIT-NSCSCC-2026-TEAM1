#include <stdint.h>
#include <stdio.h>

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
#define PS2_COUNT(v)  (((v) >> 8) & 0x1fU)

int main(void)
{
    uint32_t status;

    printf("\nPS/2 raw scan-code test\n");
    printf("PS/2 base: 0x%08lx\n", PS2_BASE);
    PS2_CTRL = 2U; /* clear FIFO and sticky errors */
    PS2_CTRL = 1U; /* enable bidirectional host */
    printf("Press and release keys; E0/F0 prefixes are intentionally raw.\n");

    for (;;) {
        status = PS2_STATUS;
        while (PS2_COUNT(status) != 0U) {
            printf("scan = 0x%02x\n", (unsigned int)(PS2_DATA & 0xffU));
            status = PS2_STATUS;
        }
        if (status & 1U) {
            printf("PS/2 protocol error, STATUS=0x%08x\n", status);
            PS2_STATUS = 1U;
        }
    }
}

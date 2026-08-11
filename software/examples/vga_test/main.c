#include <stdint.h>
#include <stdio.h>

#ifdef BOOT_FROM_UBOOT
unsigned long UART_BASE = 0x9fe001e0UL;
unsigned long CONFREG_UART_BASE = 0x9fd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0x9fd0e000UL;
#define VGA_BASE 0x9fa30000UL
#else
unsigned long UART_BASE = 0xbfe001e0UL;
unsigned long CONFREG_UART_BASE = 0xbfd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0xbfd0e000UL;
#define VGA_BASE 0xbfa30000UL
#endif
unsigned long CONFREG_CLOCKS_PER_SEC = 33000000UL;
unsigned long CORE_CLOCKS_PER_SEC = 50000000UL;

#define VGA_CTRL     (*(volatile uint32_t *)(VGA_BASE + 0x00))
#define VGA_STATUS   (*(volatile uint32_t *)(VGA_BASE + 0x04))
#define VGA_FB_ADDR  (*(volatile uint32_t *)(VGA_BASE + 0x08))
#define VGA_STRIDE   (*(volatile uint32_t *)(VGA_BASE + 0x0c))
#define WIDTH 640U
#define HEIGHT 480U

#define FRAMEBUFFER_VA 0x80400000UL

static uint16_t bar_color(unsigned int x)
{
    static const uint16_t colors[8] = {
        0xffffU, 0xffe0U, 0x07ffU, 0x07e0U,
        0xf81fU, 0xf800U, 0x001fU, 0x0000U
    };
    return colors[(x * 8U) / WIDTH];
}

int main(void)
{
    unsigned int x, y;
    uintptr_t physical;
    volatile uint16_t *framebuffer = (volatile uint16_t *)FRAMEBUFFER_VA;

    printf("\nVGA DMA test: 640x480 RGB565\n");
    VGA_CTRL = 2U;
    for (y = 0; y < HEIGHT; ++y) {
        for (x = 0; x < WIDTH; ++x) {
            uint16_t color = bar_color(x);
            /* A white row marker every 32 rows catches vertical wrapping. */
            if ((y & 31U) == 0U)
                color = 0xffffU;
            framebuffer[y * WIDTH + x] = color;
        }
    }
    __asm__ volatile("dbar 0" ::: "memory");

    physical = FRAMEBUFFER_VA & 0x1fffffffUL;
    VGA_FB_ADDR = (uint32_t)physical;
    VGA_STRIDE = WIDTH * 2U;
    VGA_CTRL = 1U;
    printf("Framebuffer VA=0x%08lx PA=0x%08lx STATUS=0x%08x\n",
           FRAMEBUFFER_VA, (unsigned long)physical, VGA_STATUS);
    printf("Color bars and 15 horizontal row markers should remain stable.\n");

    for (;;) {
        uint32_t status = VGA_STATUS;
        if (status & 3U) {
            printf("VGA error STATUS=0x%08x\n", status);
            VGA_STATUS = status & 3U;
        }
    }
}

#include <stdint.h>
#include <stdio.h>

#include "confreg_time.h"
#include "lcd_font_16x32.h"
#include "lcd_init_sequence.h"

/* BSP globals used by start.S, printf and confreg_time.c. */
#ifdef BOOT_FROM_UBOOT
/* U-Boot leaves the 0x8/0x9 segment configured as uncached MMIO. */
unsigned long UART_BASE = 0x9fe001e0UL;
unsigned long CONFREG_UART_BASE = 0x9fd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0x9fd0e000UL;
#define LCD_BASE          0x9fa00000UL
#else
unsigned long UART_BASE = 0xbfe001e0UL;
unsigned long CONFREG_UART_BASE = 0xbfd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0xbfd0e000UL;
#define LCD_BASE          0xbfa00000UL
#endif
unsigned long CONFREG_CLOCKS_PER_SEC = 33000000UL;
unsigned long CORE_CLOCKS_PER_SEC = 50000000UL;

/*
 * Hardware base: 0x1fa0_0000.
 * The standalone program uses the uncached DMW/KSEG alias.
 */
#define LCD_CTRL          (*(volatile uint32_t *)(LCD_BASE + 0x00))
#define LCD_STATUS        (*(volatile uint32_t *)(LCD_BASE + 0x04))
#define LCD_TIMING        (*(volatile uint32_t *)(LCD_BASE + 0x08))
#define LCD_WRITE_CMD     (*(volatile uint32_t *)(LCD_BASE + 0x10))
#define LCD_WRITE_DATA    (*(volatile uint32_t *)(LCD_BASE + 0x14))

#define LCD_STATUS_EMPTY  (1U << 0)
#define LCD_STATUS_FULL   (1U << 1)
#define LCD_STATUS_BUSY   (1U << 2)
#define LCD_STATUS_RESETN (1U << 3)
#define LCD_STATUS_BL     (1U << 4)

#define LCD_CTRL_SOFT_RESET (1U << 0)
#define LCD_CTRL_RESETN     (1U << 1)
#define LCD_CTRL_BL         (1U << 2)

/* Change these values if the connected panel has a different resolution. */
#ifndef LCD_WIDTH
#define LCD_WIDTH  480U
#endif

#ifndef LCD_HEIGHT
#define LCD_HEIGHT 800U
#endif

/* RGB565 colors. */
#define COLOR_BLACK   0x0000U
#define COLOR_BLUE    0x001fU
#define COLOR_GREEN   0x07e0U
#define COLOR_CYAN    0x07ffU
#define COLOR_RED     0xf800U
#define COLOR_MAGENTA 0xf81fU
#define COLOR_YELLOW  0xffe0U
#define COLOR_WHITE   0xffffU

static void io_barrier(void)
{
    __asm__ volatile("dbar 0" ::: "memory");
}

static void delay_ms(uint32_t milliseconds)
{
    uint32_t start = (uint32_t)get_cpu_clock_count();
    uint32_t cycles = milliseconds *
                      (uint32_t)(CORE_CLOCKS_PER_SEC / 1000UL);

    while ((uint32_t)((uint32_t)get_cpu_clock_count() - start) < cycles)
        ;
}

static void lcd_write_cmd(uint16_t command)
{
    /* WREADY provides hardware backpressure when the FIFO is full. */
    LCD_WRITE_CMD = command;
}

static void lcd_write_data(uint16_t data)
{
    LCD_WRITE_DATA = data;
}

static int lcd_wait_idle(uint32_t timeout_ms)
{
    uint32_t start = (uint32_t)get_cpu_clock_count();
    uint32_t cycles = timeout_ms *
                      (uint32_t)(CORE_CLOCKS_PER_SEC / 1000UL);

    while (LCD_STATUS & LCD_STATUS_BUSY) {
        if ((uint32_t)((uint32_t)get_cpu_clock_count() - start) >= cycles)
            return -1;
    }
    return 0;
}

static int lcd_register_test(void)
{
    uint32_t timing;
    uint32_t control;
    uint32_t status;

    LCD_TIMING = 0x00010101U;
    io_barrier();

    timing = LCD_TIMING;
    if (timing != 0x00010101U) {
        printf("ERROR: LCD_TIMING readback = 0x%08x\n", timing);
        return -1;
    }

    LCD_CTRL = 0U;
    io_barrier();
    control = LCD_CTRL;
    status = LCD_STATUS;

    if (control != 0U) {
        printf("ERROR: LCD_CTRL readback = 0x%08x\n", control);
        return -1;
    }

    if ((status & (LCD_STATUS_RESETN | LCD_STATUS_BL)) != 0U) {
        printf("ERROR: LCD_STATUS reset value = 0x%08x\n", status);
        return -1;
    }

    printf("LCD AXI register test passed, STATUS=0x%08x\n", status);
    return 0;
}

static void lcd_hardware_reset(void)
{
    /* Flush the command FIFO and assert the external LCD reset. */
    LCD_CTRL = LCD_CTRL_SOFT_RESET;
    io_barrier();
    delay_ms(20U);

    /* Release reset with the backlight still disabled. */
    LCD_CTRL = LCD_CTRL_RESETN;
    io_barrier();
    delay_ms(150U);
}

static int lcd_panel_init(void)
{
    uint32_t index;

    /*
     * Replay the original rst_rom.coe in software.  In each 17-bit ROM word,
     * bit 16 selects command/data and the low 16 bits are the LCD bus value.
     */
    for (index = 0U; index < LCD_INIT_SEQUENCE_COUNT; ++index) {
        uint32_t word = lcd_init_sequence[index];

        if (word & LCD_INIT_COMMAND_FLAG)
            lcd_write_cmd((uint16_t)word);
        else
            lcd_write_data((uint16_t)word);

        /* Entry 762 is 0x1100 (Sleep Out). */
        if ((index + 1U) == LCD_INIT_PRE_SLEEP_COUNT) {
            if (lcd_wait_idle(100U) != 0)
                return -1;
            delay_ms(120U);
        }
    }

    if (lcd_wait_idle(100U) != 0)
        return -1;
    delay_ms(20U);

    LCD_CTRL = LCD_CTRL_RESETN | LCD_CTRL_BL;
    io_barrier();
    return 0;
}

static void lcd_set_window(uint16_t left, uint16_t top,
                           uint16_t right, uint16_t bottom)
{
    /* This panel exposes the byte lanes as separate 16-bit registers. */
    lcd_write_cmd(0x2a00U);
    lcd_write_data((uint16_t)(left >> 8));
    lcd_write_cmd(0x2a01U);
    lcd_write_data((uint16_t)(left & 0xffU));
    lcd_write_cmd(0x2a02U);
    lcd_write_data((uint16_t)(right >> 8));
    lcd_write_cmd(0x2a03U);
    lcd_write_data((uint16_t)(right & 0xffU));

    lcd_write_cmd(0x2b00U);
    lcd_write_data((uint16_t)(top >> 8));
    lcd_write_cmd(0x2b01U);
    lcd_write_data((uint16_t)(top & 0xffU));
    lcd_write_cmd(0x2b02U);
    lcd_write_data((uint16_t)(bottom >> 8));
    lcd_write_cmd(0x2b03U);
    lcd_write_data((uint16_t)(bottom & 0xffU));

    lcd_write_cmd(0x2c00U);
}

static int lcd_fill(uint16_t color)
{
    uint32_t pixel_count = LCD_WIDTH * LCD_HEIGHT;
    uint32_t pixel;

    lcd_set_window(0U, 0U, (uint16_t)(LCD_WIDTH - 1U),
                   (uint16_t)(LCD_HEIGHT - 1U));

    for (pixel = 0U; pixel < pixel_count; ++pixel)
        lcd_write_data(color);

    return lcd_wait_idle(2000U);
}

static void lcd_draw_char(uint16_t left, uint16_t top, char character,
                          uint16_t foreground, uint16_t background)
{
    const uint16_t *glyph;
    uint32_t row;
    uint32_t column;
    uint8_t code = (uint8_t)character;

    if (code >= LCD_FONT_GLYPHS)
        code = (uint8_t)'?';
    glyph = lcd_font_16x32[code];

    lcd_set_window(left, top,
                   (uint16_t)(left + LCD_FONT_WIDTH - 1U),
                   (uint16_t)(top + LCD_FONT_HEIGHT - 1U));

    for (row = 0U; row < LCD_FONT_HEIGHT; ++row) {
        for (column = 0U; column < LCD_FONT_WIDTH; ++column) {
            uint16_t mask = (uint16_t)(0x8000U >> column);
            lcd_write_data((glyph[row] & mask) ? foreground : background);
        }
    }
}

static void lcd_draw_text(uint16_t left, uint16_t top, const char *text,
                          uint16_t foreground, uint16_t background)
{
    uint16_t x = left;
    uint16_t y = top;

    while (*text != '\0') {
        if (*text == '\n') {
            x = left;
            y = (uint16_t)(y + LCD_FONT_HEIGHT);
            ++text;
            continue;
        }

        if ((uint32_t)x + LCD_FONT_WIDTH > LCD_WIDTH) {
            x = left;
            y = (uint16_t)(y + LCD_FONT_HEIGHT);
        }
        if ((uint32_t)y + LCD_FONT_HEIGHT > LCD_HEIGHT)
            break;

        lcd_draw_char(x, y, *text, foreground, background);
        x = (uint16_t)(x + LCD_FONT_WIDTH);
        ++text;
    }
}

static int lcd_font_test(void)
{
    printf("Display software font test (16 x 32)\n");

    if (lcd_fill(COLOR_BLACK) != 0)
        return -1;

    lcd_draw_text(16U, 64U, "LOONGSON SOC LCD", COLOR_YELLOW, COLOR_BLACK);
    lcd_draw_text(16U, 128U, "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                  COLOR_CYAN, COLOR_BLACK);
    lcd_draw_text(16U, 192U, "abcdefghijklmnopqrstuvwxyz",
                  COLOR_GREEN, COLOR_BLACK);
    lcd_draw_text(16U, 256U, "0123456789 !@#$%^&*()",
                  COLOR_WHITE, COLOR_BLACK);

    return lcd_wait_idle(2000U);
}

static int lcd_color_bars(void)
{
    static const uint16_t colors[] = {
        COLOR_RED, COLOR_GREEN, COLOR_BLUE, COLOR_WHITE,
        COLOR_YELLOW, COLOR_CYAN, COLOR_MAGENTA, COLOR_BLACK
    };
    const uint32_t color_count = sizeof(colors) / sizeof(colors[0]);
    uint32_t x;
    uint32_t y;

    lcd_set_window(0U, 0U, (uint16_t)(LCD_WIDTH - 1U),
                   (uint16_t)(LCD_HEIGHT - 1U));

    for (y = 0U; y < LCD_HEIGHT; ++y) {
        for (x = 0U; x < LCD_WIDTH; ++x) {
            uint32_t index = (x * color_count) / LCD_WIDTH;
            lcd_write_data(colors[index]);
        }
    }

    return lcd_wait_idle(2000U);
}

static int show_solid(const char *name, uint16_t color)
{
    printf("Display solid %s (RGB565=0x%04x)\n", name, color);
    if (lcd_fill(color) != 0) {
        printf("ERROR: timeout while displaying %s\n", name);
        return -1;
    }
    delay_ms(1000U);
    return 0;
}

int main(int argc, char **argv)
{
    uint32_t status;

    (void)argc;
    (void)argv;

    printf("\nLCD standalone test\n");
    printf("Resolution: %u x %u\n", LCD_WIDTH, LCD_HEIGHT);
    printf("LCD register base: 0x%08x\n", (uint32_t)LCD_BASE);

    if (lcd_register_test() != 0)
        goto failed;

    lcd_hardware_reset();
    printf("LCD reset released\n");
    printf("Replay rst_rom.coe: %u command/data words\n",
           LCD_INIT_SEQUENCE_COUNT);

    if (lcd_panel_init() != 0) {
        printf("ERROR: LCD initialization timed out\n");
        goto failed;
    }

    status = LCD_STATUS;
    printf("LCD initialized, STATUS=0x%08x\n", status);

    for (;;) {
        if (show_solid("RED", COLOR_RED) != 0)
            break;
        if (show_solid("GREEN", COLOR_GREEN) != 0)
            break;
        if (show_solid("BLUE", COLOR_BLUE) != 0)
            break;
        if (show_solid("WHITE", COLOR_WHITE) != 0)
            break;
        if (show_solid("BLACK", COLOR_BLACK) != 0)
            break;

        printf("Display color bars\n");
        if (lcd_color_bars() != 0) {
            printf("ERROR: timeout while displaying color bars\n");
            break;
        }
        delay_ms(3000U);

        if (lcd_font_test() != 0) {
            printf("ERROR: timeout while displaying font test\n");
            break;
        }
        delay_ms(5000U);
    }

failed:
    LCD_CTRL = LCD_CTRL_RESETN | LCD_CTRL_BL;
    status = LCD_STATUS;
    printf("LCD test stopped, STATUS=0x%08x\n", status);
    for (;;)
        ;
}

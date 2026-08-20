#include <stdint.h>
#include <stdio.h>

#include "confreg_time.h"

/* BSP globals used by start.S, printf and confreg_time.c. */
#ifdef BOOT_FROM_UBOOT
unsigned long UART_BASE = 0x9fe001e0UL;
unsigned long CONFREG_UART_BASE = 0x9fd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0x9fd0e000UL;
#define I2C_BASE 0x9fa10000UL
#else
unsigned long UART_BASE = 0xbfe001e0UL;
unsigned long CONFREG_UART_BASE = 0xbfd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0xbfd0e000UL;
#define I2C_BASE 0xbfa10000UL
#endif

unsigned long CONFREG_CLOCKS_PER_SEC = 33000000UL;
unsigned long CORE_CLOCKS_PER_SEC = 50000000UL;

#define MMIO32(offset) (*(volatile uint32_t *)(I2C_BASE + (offset)))

#define OCI2C_PRER_LO  MMIO32(0x00)
#define OCI2C_PRER_HI  MMIO32(0x04)
#define OCI2C_CTR      MMIO32(0x08)
#define OCI2C_TXRX     MMIO32(0x0c)
#define OCI2C_CMD_STAT MMIO32(0x10)
#define TOUCH_CTRL     MMIO32(0x20)
#define TOUCH_STAT     MMIO32(0x24)

#define OCI2C_EN       0x80U
#define OCI2C_STA      0x80U
#define OCI2C_STO      0x40U
#define OCI2C_RD       0x20U
#define OCI2C_WR       0x10U
#define OCI2C_NACK     0x08U
#define OCI2C_IACK     0x01U

#define OCI2C_RXACK    0x80U
#define OCI2C_BUSY     0x40U
#define OCI2C_AL       0x20U
#define OCI2C_TIP      0x02U
#define OCI2C_IF       0x01U

static void delay_ms(uint32_t milliseconds)
{
    uint32_t start = (uint32_t)get_confreg_clock_count();
    uint32_t cycles = milliseconds *
                      (uint32_t)(CONFREG_CLOCKS_PER_SEC / 1000UL);

    while ((uint32_t)((uint32_t)get_confreg_clock_count() - start) < cycles)
        ;
}

static int i2c_command(uint8_t command)
{
    uint32_t timeout = 2000000U;
    uint32_t status;

    OCI2C_CMD_STAT = (uint32_t)(command | OCI2C_IACK);

    do {
        status = OCI2C_CMD_STAT;
        if (--timeout == 0U)
            return -1;
    } while ((status & OCI2C_TIP) != 0U || (status & OCI2C_IF) == 0U);

    if ((status & OCI2C_AL) != 0U)
        return -2;
    return (status & OCI2C_RXACK) ? 1 : 0;
}

static int i2c_write_byte(uint8_t value, uint8_t command)
{
    OCI2C_TXRX = value;
    return i2c_command(command | OCI2C_WR);
}

static int goodix_select_address(uint8_t address)
{
    /* Goodix samples INT while RESET_N is asserted/released.  Releasing the
     * open-drain INT selects 0x14; driving it low selects 0x5d. */
    uint32_t int_low = (address == 0x5dU) ? 2U : 0U;

    TOUCH_CTRL = int_low;        /* RESET_N=0 */
    delay_ms(20);
    TOUCH_CTRL = int_low | 1U;   /* RESET_N=1 */
    delay_ms(10);
    TOUCH_CTRL = 1U;             /* release INT for normal operation */
    delay_ms(60);

    return ((TOUCH_STAT & 0x6U) == 0x6U) ? 0 : -1;
}

static int i2c_probe(uint8_t address)
{
    int result;

    result = i2c_write_byte((uint8_t)(address << 1),
                            OCI2C_STA | OCI2C_STO);
    return result == 0 ? 0 : -1;
}

static int goodix_read(uint8_t address, uint16_t reg,
                       uint8_t *data, unsigned int length)
{
    unsigned int index;
    int result;

    result = i2c_write_byte((uint8_t)(address << 1), OCI2C_STA);
    if (result != 0)
        goto stop;
    result = i2c_write_byte((uint8_t)(reg >> 8), 0U);
    if (result != 0)
        goto stop;
    result = i2c_write_byte((uint8_t)reg, 0U);
    if (result != 0)
        goto stop;
    result = i2c_write_byte((uint8_t)((address << 1) | 1U), OCI2C_STA);
    if (result != 0)
        goto stop;

    for (index = 0; index < length; ++index) {
        uint8_t command = OCI2C_RD;
        if (index + 1U == length)
            command |= OCI2C_NACK | OCI2C_STO;

        result = i2c_command(command);
        if (result < 0)
            return result;
        data[index] = (uint8_t)OCI2C_TXRX;
    }
    return 0;

stop:
    (void)i2c_command(OCI2C_STO);
    return -1;
}

int main(void)
{
    static const uint8_t addresses[] = {0x5dU, 0x14U};
    uint8_t product_id[4];
    unsigned int index;

    printf("\nOpenCores I2C Goodix probe\n");
    printf("I2C base: 0x%08lx\n", I2C_BASE);

    OCI2C_CTR = 0U;
    /* 33 MHz / (5 * (65 + 1)) = 100 kHz. */
    OCI2C_PRER_LO = 65U;
    OCI2C_PRER_HI = 0U;
    OCI2C_CTR = OCI2C_EN;

    for (index = 0; index < sizeof(addresses); ++index) {
        uint8_t address = addresses[index];
        printf("Select and probe I2C address 0x%02x ... ", address);

        if (goodix_select_address(address) != 0) {
            printf("bus lines not released (LINES=0x%08x)\n", TOUCH_STAT);
            continue;
        }
        if (i2c_probe(address) != 0) {
            printf("no ACK\n");
            continue;
        }

        printf("ACK\n");
        if (goodix_read(address, 0x8140U, product_id,
                        sizeof(product_id)) == 0) {
            printf("Goodix product ID: %c%c%c%c\n",
                   product_id[0], product_id[1],
                   product_id[2], product_id[3]);
            printf("Raw ID: %02x %02x %02x %02x\n",
                   product_id[0], product_id[1],
                   product_id[2], product_id[3]);
        } else {
            printf("ACK received, but product-ID read failed\n");
        }
        return 0;
    }

    printf("No Goodix device found at 0x5d or 0x14\n");
    return 1;
}

#include <stdint.h>
#include <stdio.h>

#ifdef BOOT_FROM_UBOOT
unsigned long UART_BASE = 0x9fe001e0UL;
unsigned long CONFREG_UART_BASE = 0x9fd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0x9fd0e000UL;
#define I2S_BASE 0x9fa20000UL
#else
unsigned long UART_BASE = 0xbfe001e0UL;
unsigned long CONFREG_UART_BASE = 0xbfd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0xbfd0e000UL;
#define I2S_BASE 0xbfa20000UL
#endif
unsigned long CONFREG_CLOCKS_PER_SEC = 33000000UL;
unsigned long CORE_CLOCKS_PER_SEC = 50000000UL;

#define I2S_CTRL       (*(volatile uint32_t *)(I2S_BASE + 0x00))
#define I2S_STATUS     (*(volatile uint32_t *)(I2S_BASE + 0x04))
#define I2S_BUF_ADDR   (*(volatile uint32_t *)(I2S_BASE + 0x08))
#define I2S_BUF_BYTES  (*(volatile uint32_t *)(I2S_BASE + 0x0c))
#define I2S_PERIOD     (*(volatile uint32_t *)(I2S_BASE + 0x10))
#define I2S_PLAY_POS   (*(volatile uint32_t *)(I2S_BASE + 0x14))
#define FRAMES 44100U

static const int16_t sine64[64] = {
       0,  3212,  6393,  9512, 12539, 15446, 18204, 20787,
   23170, 25330, 27245, 28899, 30273, 31356, 32137, 32609,
   32767, 32609, 32137, 31356, 30273, 28899, 27245, 25330,
   23170, 20787, 18204, 15446, 12539,  9512,  6393,  3212,
       0, -3212, -6393, -9512,-12539,-15446,-18204,-20787,
  -23170,-25330,-27245,-28899,-30273,-31356,-32137,-32609,
  -32767,-32609,-32137,-31356,-30273,-28899,-27245,-25330,
  -23170,-20787,-18204,-15446,-12539, -9512, -6393, -3212
};

static uint32_t pcm[FRAMES] __attribute__((aligned(64)));

int main(void)
{
    uint32_t i;
    uint32_t left_phase = 0, right_phase = 0;
    const uint32_t left_step = (uint32_t)(((uint64_t)440U << 24) / 44100U);
    const uint32_t right_step = (uint32_t)(((uint64_t)660U << 24) / 44100U);
    uintptr_t physical;

    printf("\nI2S DMA test: 44.1 kHz, stereo, S16_LE\n");
    I2S_CTRL = 2U;
    for (i = 0; i < FRAMES; ++i) {
        int16_t left = sine64[left_phase >> 18];
        int16_t right = sine64[right_phase >> 18];
        pcm[i] = (uint16_t)left | ((uint32_t)(uint16_t)right << 16);
        left_phase = (left_phase + left_step) & 0x00ffffffU;
        right_phase = (right_phase + right_step) & 0x00ffffffU;
    }
    __asm__ volatile("dbar 0" ::: "memory");

    physical = ((uintptr_t)pcm) & 0x1fffffffUL;
    I2S_BUF_ADDR = (uint32_t)physical;
    I2S_BUF_BYTES = sizeof(pcm);
    I2S_PERIOD = 4410U * 4U; /* ten period events per second */
    I2S_CTRL = 1U;
    printf("PCM VA=0x%08lx PA=0x%08lx; left=440 Hz right=660 Hz\n",
           (unsigned long)pcm, (unsigned long)physical);

    for (;;) {
        uint32_t status = I2S_STATUS;
        if (status & 6U) {
            printf("I2S error STATUS=0x%08x PLAY_POS=%u\n",
                   status, I2S_PLAY_POS);
            I2S_STATUS = status & 7U;
        } else if (status & 1U) {
            I2S_STATUS = 1U;
        }
    }
}

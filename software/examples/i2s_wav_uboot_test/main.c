#include <stdint.h>
#include <stdio.h>

unsigned long UART_BASE = 0x9fe001e0UL;
unsigned long CONFREG_UART_BASE = 0x9fd0ff10UL;
unsigned long CONFREG_TIMER_BASE = 0x9fd0e000UL;
unsigned long CONFREG_CLOCKS_PER_SEC = 33000000UL;
unsigned long CORE_CLOCKS_PER_SEC = 50000000UL;

#define I2S_BASE       0x9fa20000UL
#define I2S_CTRL       (*(volatile uint32_t *)(I2S_BASE + 0x00))
#define I2S_STATUS     (*(volatile uint32_t *)(I2S_BASE + 0x04))
#define I2S_BUF_ADDR   (*(volatile uint32_t *)(I2S_BASE + 0x08))
#define I2S_BUF_BYTES  (*(volatile uint32_t *)(I2S_BASE + 0x0c))
#define I2S_PERIOD     (*(volatile uint32_t *)(I2S_BASE + 0x10))
#define I2S_PLAY_POS   (*(volatile uint32_t *)(I2S_BASE + 0x14))

/*
 * Keep large WAV files above the ELF staging area at 0xa3000000. Loading at
 * +4 makes the usual 44-byte PCM payload 8-byte aligned for the AXI DMA.
 */
#define WAV_LOAD_ADDR  0xa4000004UL
#define WAV_MAX_BYTES  (64U * 1024U * 1024U)

static uint16_t get_le16(const volatile uint8_t *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t get_le32(const volatile uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static int tag_is(const volatile uint8_t *p, const char *tag)
{
    return p[0] == (uint8_t)tag[0] && p[1] == (uint8_t)tag[1] &&
           p[2] == (uint8_t)tag[2] && p[3] == (uint8_t)tag[3];
}

int main(void)
{
    const volatile uint8_t *wav = (const volatile uint8_t *)WAV_LOAD_ADDR;
    const volatile uint8_t *pcm = 0;
    uint32_t riff_bytes, offset, pcm_bytes = 0;
    uint32_t sample_rate = 0;
    uint16_t format = 0, channels = 0, bits = 0, block_align = 0;
    int have_fmt = 0;

    printf("\nU-Boot WAV -> I2S DMA player\n");
    printf("WAV address: 0x%08lx\n", WAV_LOAD_ADDR);

    if (!tag_is(wav, "RIFF") || !tag_is(wav + 8, "WAVE")) {
        printf("Invalid WAV: load the file at exactly 0x%08lx\n",
               WAV_LOAD_ADDR);
        return 1;
    }

    riff_bytes = get_le32(wav + 4) + 8U;
    if (riff_bytes < 44U || riff_bytes > WAV_MAX_BYTES) {
        printf("Invalid RIFF size: %u bytes\n", riff_bytes);
        return 1;
    }

    offset = 12U;
    while (offset + 8U <= riff_bytes) {
        const volatile uint8_t *chunk = wav + offset;
        uint32_t chunk_bytes = get_le32(chunk + 4);
        uint32_t payload = offset + 8U;
        uint32_t next;

        if (chunk_bytes > riff_bytes - payload)
            break;
        if (tag_is(chunk, "fmt ") && chunk_bytes >= 16U) {
            format = get_le16(wav + payload + 0);
            channels = get_le16(wav + payload + 2);
            sample_rate = get_le32(wav + payload + 4);
            block_align = get_le16(wav + payload + 12);
            bits = get_le16(wav + payload + 14);
            have_fmt = 1;
        } else if (tag_is(chunk, "data")) {
            pcm = wav + payload;
            pcm_bytes = chunk_bytes;
        }

        next = payload + ((chunk_bytes + 1U) & ~1U);
        if (next <= offset)
            break;
        offset = next;
    }

    if (!have_fmt || !pcm) {
        printf("Invalid WAV: fmt/data chunk missing\n");
        return 1;
    }
    if (format != 1U || channels != 2U || sample_rate != 44100U ||
        bits != 16U || block_align != 4U) {
        printf("Unsupported WAV: format=%u channels=%u rate=%u bits=%u align=%u\n",
               format, channels, sample_rate, bits, block_align);
        printf("Required: PCM, 44100 Hz, stereo, S16_LE\n");
        return 1;
    }
    if (((uintptr_t)pcm & 7U) != 0U) {
        printf("PCM address 0x%08lx is not 8-byte aligned\n",
               (unsigned long)pcm);
        printf("Reload the WAV at 0x%08lx\n", WAV_LOAD_ADDR);
        return 1;
    }

    pcm_bytes &= ~7U;
    if (pcm_bytes == 0U) {
        printf("WAV contains no complete DMA words\n");
        return 1;
    }

    I2S_CTRL = 0U;
    I2S_CTRL = 2U;                 /* clear sticky status */
    I2S_BUF_ADDR = (uint32_t)((uintptr_t)pcm & 0x1fffffffUL);
    I2S_BUF_BYTES = pcm_bytes;
    I2S_PERIOD = 4410U * 4U;       /* 100 ms */
    __asm__ volatile("dbar 0" ::: "memory");
    I2S_CTRL = 1U;

    printf("PCM VA=0x%08lx PA=0x%08x bytes=%u duration=%u.%02u s\n",
           (unsigned long)pcm, I2S_BUF_ADDR, pcm_bytes,
           pcm_bytes / 176400U,
           ((pcm_bytes % 176400U) * 100U) / 176400U);
    printf("Playing in a loop; press board RESET to return to U-Boot.\n");

    for (;;) {
        uint32_t status = I2S_STATUS;
        if (status & 6U) {
            printf("I2S warning STATUS=0x%08x PLAY_POS=%u\n",
                   status, I2S_PLAY_POS);
            I2S_STATUS = status & 6U;
        } else if (status & 1U) {
            I2S_STATUS = 1U;
        }
    }
}

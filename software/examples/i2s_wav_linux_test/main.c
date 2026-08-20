#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

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

static void put16(FILE *file, uint16_t value)
{
    fputc(value & 0xff, file);
    fputc(value >> 8, file);
}

static void put32(FILE *file, uint32_t value)
{
    put16(file, value & 0xffff);
    put16(file, value >> 16);
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "/tmp/la32r-test.wav";
    const uint32_t frames = 44100U * 10U;
    const uint32_t data_bytes = frames * 4U;
    const uint32_t left_step = (uint32_t)(((uint64_t)440 << 24) / 44100);
    const uint32_t right_step = (uint32_t)(((uint64_t)660 << 24) / 44100);
    uint32_t left_phase = 0, right_phase = 0, i;
    FILE *file = fopen(path, "wb");

    if (!file) {
        perror(path);
        return 1;
    }
    fwrite("RIFF", 1, 4, file); put32(file, 36 + data_bytes);
    fwrite("WAVEfmt ", 1, 8, file); put32(file, 16);
    put16(file, 1); put16(file, 2); put32(file, 44100);
    put32(file, 44100 * 4); put16(file, 4); put16(file, 16);
    fwrite("data", 1, 4, file); put32(file, data_bytes);
    for (i = 0; i < frames; ++i) {
        put16(file, (uint16_t)sine64[left_phase >> 18]);
        put16(file, (uint16_t)sine64[right_phase >> 18]);
        left_phase = (left_phase + left_step) & 0x00ffffffU;
        right_phase = (right_phase + right_step) & 0x00ffffffU;
    }
    if (fclose(file)) {
        perror("fclose");
        return 1;
    }
    printf("Wrote %s: 10 s, 44.1 kHz, stereo S16_LE (440/660 Hz)\n", path);
    printf("Play with: aplay -D hw:0,0 %s\n", path);
    return 0;
}

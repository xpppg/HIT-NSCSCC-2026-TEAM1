#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define RATE 44100U
#define NOTE_FRAMES (RATE / 2U)
#define FREQ_TONE_FRAMES (RATE * 3U / 4U)
#define FREQ_GAP_FRAMES (RATE / 4U)

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

/* An original C-major test phrase: C E G C5, A G E D, repeated higher. */
static const uint16_t notes[] = {
    262, 330, 392, 523, 440, 392, 330, 294,
    330, 392, 523, 659, 523, 392, 330, 262
};

/* Each tone occupies one second: 750 ms tone followed by 250 ms silence. */
static const uint16_t frequency_test[] = {
    60, 100, 200, 262, 330, 440, 523, 659, 1000, 2000, 4000, 8000
};

static void put16(FILE *f, uint16_t v)
{
    fputc(v & 0xffU, f);
    fputc(v >> 8, f);
}

static void put32(FILE *f, uint32_t v)
{
    put16(f, v & 0xffffU);
    put16(f, v >> 16);
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "i2s_test_melody.wav";
    int frequency_mode = argc > 2 && strcmp(argv[2], "freq") == 0;
    const uint32_t note_count = sizeof(notes) / sizeof(notes[0]);
    const uint32_t frequency_count = sizeof(frequency_test) /
                                     sizeof(frequency_test[0]);
    const uint32_t frames = frequency_mode ?
        frequency_count * (FREQ_TONE_FRAMES + FREQ_GAP_FRAMES) :
        note_count * NOTE_FRAMES;
    const uint32_t data_bytes = frames * 4U;
    uint32_t note, i, phase = 0;
    FILE *f = fopen(path, "wb");

    if (!f) {
        perror(path);
        return 1;
    }

    fwrite("RIFF", 1, 4, f); put32(f, 36U + data_bytes);
    fwrite("WAVEfmt ", 1, 8, f); put32(f, 16U);
    put16(f, 1U); put16(f, 2U); put32(f, RATE);
    put32(f, RATE * 4U); put16(f, 4U); put16(f, 16U);
    fwrite("data", 1, 4, f); put32(f, data_bytes);

    for (note = 0; note < (frequency_mode ? frequency_count : note_count);
         ++note) {
        uint32_t frequency = frequency_mode ? frequency_test[note] : notes[note];
        uint32_t tone_frames = frequency_mode ? FREQ_TONE_FRAMES : NOTE_FRAMES;
        uint32_t step = (uint32_t)(((uint64_t)frequency << 32) / RATE);
        phase = 0;
        for (i = 0; i < tone_frames; ++i) {
            uint32_t envelope = 8192U;
            int32_t sample;

            if (i < 256U)
                envelope = i * 32U;
            else if (tone_frames - i <= 256U)
                envelope = (tone_frames - i - 1U) * 32U;
            sample = ((int32_t)sine64[phase >> 26] * (int32_t)envelope) >> 15;
            put16(f, (uint16_t)(int16_t)sample);
            put16(f, (uint16_t)(int16_t)sample);
            phase += step;
        }
        for (i = 0; i < (frequency_mode ? FREQ_GAP_FRAMES : 0U); ++i) {
            put16(f, 0U);
            put16(f, 0U);
        }
    }

    if (fclose(f) != 0) {
        perror("fclose");
        return 1;
    }
    if (frequency_mode) {
        printf("Wrote %s: %u s frequency-isolation test, PCM 44.1 kHz "
               "stereo S16_LE\n", path, frequency_count);
        for (note = 0; note < frequency_count; ++note)
            printf("  %2u-%2u s: %u Hz\n", note, note + 1U,
                   frequency_test[note]);
    } else {
        printf("Wrote %s: 8 s, PCM 44.1 kHz stereo S16_LE\n", path);
    }
    return 0;
}

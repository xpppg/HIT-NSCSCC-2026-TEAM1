#include <cstdint>
#include <cstdio>
#include <vector>
#include "Vavp_i2s.h"
#include "verilated.h"

static unsigned int period_events;
static unsigned int underflow_events;

static void bus_tick(Vavp_i2s &dut)
{
    dut.bus_clk = 0;
    dut.eval();
    dut.bus_clk = 1;
    dut.eval();
    if (dut.period_event)
        ++period_events;
    if (dut.underflow_event)
        ++underflow_events;
}

static void push_word(Vavp_i2s &dut, std::uint64_t value)
{
    dut.stream_data = value;
    dut.stream_valid = 1;
    do {
        bus_tick(dut);
    } while (!dut.stream_ready);
    dut.stream_valid = 0;
    bus_tick(dut);
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Vavp_i2s dut;
    dut.bus_clk = 0;
    dut.aud_clk = 0;
    dut.bus_resetn = 0;
    dut.aud_locked = 0;
    dut.enable = 0;
    dut.buffer_bytes = 16;
    dut.period_bytes = 8;
    dut.stream_valid = 0;
    for (unsigned int i = 0; i < 4; ++i)
        bus_tick(dut);
    dut.bus_resetn = 1;
    dut.enable = 1;
    dut.aud_locked = 1;
    bus_tick(dut);

    /* Each little-endian 64-bit beat contains two stereo S16_LE frames. */
    push_word(dut, UINT64_C(0xf0f00f0fabcd1234));
    push_word(dut, UINT64_C(0x55aaaa550ff0f00f));

    bool previous_bclk = dut.i2s_bclk;
    bool previous_lrclk = dut.i2s_lrclk;
    bool aligned = false;
    bool channel = false;
    unsigned int channel_bits = 0;
    std::uint16_t channel_word = 0;
    std::vector<std::uint16_t> samples;
    unsigned int aud_since_rise = 0;
    unsigned int checked_intervals = 0;

    for (unsigned int cycle = 0; cycle < 7000; ++cycle) {
        bus_tick(dut);
        dut.aud_clk = 0;
        dut.eval();
        dut.aud_clk = 1;
        dut.eval();
        ++aud_since_rise;

        if (!previous_bclk && dut.i2s_bclk) {
            if (checked_intervals && aud_since_rise != 16) {
                std::fprintf(stderr, "FAIL I2S BCLK interval=%u\n",
                             aud_since_rise);
                return 1;
            }
            aud_since_rise = 0;
            ++checked_intervals;

            if (dut.i2s_lrclk != previous_lrclk) {
                if (aligned) {
                    channel_word = static_cast<std::uint16_t>(
                        (channel_word << 1) | dut.i2s_data);
                    ++channel_bits;
                    if (channel_bits != 16) {
                        std::fprintf(stderr,
                                     "FAIL I2S channel has %u bits\n",
                                     channel_bits);
                        return 1;
                    }
                    samples.push_back(channel_word);
                }
                aligned = true;
                channel = dut.i2s_lrclk;
                channel_bits = 0;
                channel_word = 0;
                previous_lrclk = dut.i2s_lrclk;
            } else if (aligned) {
                channel_word = static_cast<std::uint16_t>(
                    (channel_word << 1) | dut.i2s_data);
                ++channel_bits;
            }
        }
        previous_bclk = dut.i2s_bclk;
    }

    const std::uint16_t expected[] = {
        0x1234, 0xabcd, 0x0f0f, 0xf0f0,
        0xf00f, 0x0ff0, 0xaa55, 0x55aa
    };
    bool sequence_found = false;
    for (std::size_t start = 0;
         start + sizeof(expected) / sizeof(expected[0]) <= samples.size();
         ++start) {
        bool match = true;
        for (std::size_t i = 0; i < sizeof(expected) / sizeof(expected[0]); ++i)
            match &= samples[start + i] == expected[i];
        sequence_found |= match;
    }

    if (!sequence_found || checked_intervals < 64 || period_events != 2 ||
        underflow_events == 0) {
        std::fprintf(stderr,
                     "FAIL I2S sequence=%u rises=%u period=%u underflow=%u\n",
                     sequence_found, checked_intervals, period_events,
                     underflow_events);
        return 1;
    }

    std::printf("PASS I2S S16_LE order, /16 BCLK, period IRQ and underrun\n");
    return 0;
}

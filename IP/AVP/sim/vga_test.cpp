#include <cstdint>
#include <cstdio>
#include <vector>
#include "Vavp_vga.h"
#include "verilated.h"

static unsigned int underflows;

static void bus_tick(Vavp_vga &dut)
{
    dut.bus_clk = 0;
    dut.eval();
    dut.bus_clk = 1;
    dut.eval();
    if (dut.underflow_event)
        ++underflows;
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Vavp_vga dut;
    dut.bus_clk = 0;
    dut.pix_clk = 0;
    dut.bus_resetn = 0;
    dut.pix_locked = 0;
    dut.enable = 0;
    dut.stream_valid = 0;
    dut.stream_data = 0;
    bus_tick(dut);
    bus_tick(dut);
    dut.bus_resetn = 1;
    dut.pix_locked = 1;
    dut.enable = 1;
    bus_tick(dut);

    /* Four RGB565 pixels: red, green, blue, white. */
    dut.stream_data = UINT64_C(0xffff001f07e0f800);
    dut.stream_valid = 1;
    bus_tick(dut);
    dut.stream_valid = 0;

    std::vector<unsigned int> colors;
    unsigned int hsync_edges = 0;
    bool previous_hsync = dut.vga_hsync;
    for (unsigned int cycle = 0; cycle < 50000; ++cycle) {
        bus_tick(dut);
        dut.pix_clk = 0;
        dut.eval();
        dut.pix_clk = 1;
        dut.eval();
        if (dut.vga_hsync != previous_hsync) {
            ++hsync_edges;
            previous_hsync = dut.vga_hsync;
        }
        unsigned int rgb = (dut.vga_r << 8) | (dut.vga_g << 4) | dut.vga_b;
        if (rgb && colors.size() < 4)
            colors.push_back(rgb);
    }

    const unsigned int expected[] = {0xf00, 0x0f0, 0x00f, 0xfff};
    bool good = colors.size() == 4;
    for (unsigned int i = 0; good && i < 4; ++i)
        good &= colors[i] == expected[i];
    if (!good || underflows == 0 || hsync_edges < 4) {
        std::fprintf(stderr,
                     "FAIL VGA colors=%zu underflows=%u hsync_edges=%u\n",
                     colors.size(), underflows, hsync_edges);
        return 1;
    }

    std::printf("PASS VGA RGB565 mapping, raster and black-on-underflow\n");
    return 0;
}

#include <cstdint>
#include <cstdio>
#include "Vdisplay_timings.h"
#include "verilated.h"

static void tick(Vdisplay_timings &dut)
{
    dut.i_pix_clk = 0;
    dut.eval();
    dut.i_pix_clk = 1;
    dut.eval();
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Vdisplay_timings dut;
    std::uint64_t active = 0, hsync_low = 0, vsync_low = 0, frames = 0;

    dut.i_rst = 1;
    tick(dut);
    tick(dut);
    dut.i_rst = 0;

    /* One complete 800x525 raster, starting at the first blanking pixel. */
    for (unsigned int cycle = 0; cycle < 800U * 525U; ++cycle) {
        if (dut.o_de)
            ++active;
        if (!dut.o_hs)
            ++hsync_low;
        if (!dut.o_vs)
            ++vsync_low;
        if (dut.o_frame)
            ++frames;
        tick(dut);
    }

    if (active != 640U * 480U || hsync_low != 96U * 525U ||
        vsync_low != 2U * 800U || frames != 1U) {
        std::fprintf(stderr,
            "FAIL active=%llu hs_low=%llu vs_low=%llu frames=%llu\n",
            static_cast<unsigned long long>(active),
            static_cast<unsigned long long>(hsync_low),
            static_cast<unsigned long long>(vsync_low),
            static_cast<unsigned long long>(frames));
        return 1;
    }

    std::printf("PASS 800x525, active 640x480, HS=96, VS=2\n");
    return 0;
}

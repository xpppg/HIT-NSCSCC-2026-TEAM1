#include <cstdint>
#include <cstdio>
#include "Vavp_stream_dma.h"
#include "verilated.h"

static void tick(Vavp_stream_dma &dut)
{
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
}

static bool wait_ar(Vavp_stream_dma &dut, std::uint32_t address,
                    unsigned int beats)
{
    for (unsigned int timeout = 0; timeout < 100; ++timeout) {
        tick(dut);
        if (dut.m_axi_arvalid) {
            if (dut.m_axi_araddr != address || dut.m_axi_arlen + 1 != beats)
                return false;
            dut.m_axi_arready = 1;
            tick(dut);
            dut.m_axi_arready = 0;
            return true;
        }
    }
    return false;
}

static bool return_burst(Vavp_stream_dma &dut, unsigned int beats,
                         bool inject_error)
{
    for (unsigned int beat = 0; beat < beats; ++beat) {
        dut.m_axi_rvalid = 1;
        dut.m_axi_rid = 5;
        dut.m_axi_rdata = beat;
        dut.m_axi_rresp = inject_error && beat == 0 ? 2 : 0;
        dut.m_axi_rlast = beat + 1 == beats;
        if (!dut.m_axi_rready)
            return false;
        tick(dut);
    }
    dut.m_axi_rvalid = 0;
    dut.m_axi_rlast = 0;
    dut.m_axi_rresp = 0;
    tick(dut);
    return true;
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Vavp_stream_dma dut;
    dut.resetn = 0;
    dut.enable = 0;
    dut.base_addr = 0x00001ff8;
    dut.byte_length = 17 * 8;
    dut.stream_ready = 1;
    dut.m_axi_arready = 0;
    dut.m_axi_rvalid = 0;
    dut.m_axi_rid = 5;
    dut.m_axi_rdata = 0;
    dut.m_axi_rresp = 0;
    dut.m_axi_rlast = 0;
    tick(dut);
    tick(dut);
    dut.resetn = 1;
    dut.enable = 1;
    tick(dut);

    if (!wait_ar(dut, 0x00001ff8, 1) || !return_burst(dut, 1, false) ||
        !wait_ar(dut, 0x00002000, 16) || !return_burst(dut, 16, false) ||
        dut.fetched_pos != 0 || !wait_ar(dut, 0x00001ff8, 1) ||
        !return_burst(dut, 1, true) || !dut.error || dut.running) {
        std::fprintf(stderr,
                     "FAIL DMA pos=%u running=%u error=%u addr=%08x len=%u\n",
                     dut.fetched_pos, dut.running, dut.error,
                     dut.m_axi_araddr, dut.m_axi_arlen + 1);
        return 1;
    }

    std::printf("PASS DMA 16-beat/4KiB limits, loop and AXI error stop\n");
    return 0;
}

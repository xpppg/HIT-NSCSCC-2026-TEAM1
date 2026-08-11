#include <cstdint>
#include <cstdio>
#include <vector>
#include "Vps2_host_sim_top.h"
#include "verilated.h"

static std::vector<unsigned int> received;
static unsigned int errors;

static void tick(Vps2_host_sim_top &dut)
{
    dut.sys_clk = 0;
    dut.eval();
    dut.sys_clk = 1;
    dut.eval();
    if (dut.ready)
        received.push_back(dut.rx_data);
    if (dut.error)
        ++errors;
}

static void ticks(Vps2_host_sim_top &dut, unsigned int count)
{
    while (count--)
        tick(dut);
}

static void device_bit(Vps2_host_sim_top &dut, bool value)
{
    dut.dev_data_low = !value;
    ticks(dut, 4);
    dut.dev_clk_low = 1;
    ticks(dut, 4);
    dut.dev_clk_low = 0;
    ticks(dut, 4);
}

static void device_byte(Vps2_host_sim_top &dut, std::uint8_t value,
                        bool corrupt_parity = false)
{
    bool parity = !(static_cast<unsigned int>(__builtin_popcount(value)) & 1U);

    device_bit(dut, false);
    for (unsigned int bit = 0; bit < 8; ++bit)
        device_bit(dut, (value >> bit) & 1U);
    device_bit(dut, parity ^ corrupt_parity);
    device_bit(dut, true);
    dut.dev_data_low = 0;
    ticks(dut, 8);
}

static void device_clock(Vps2_host_sim_top &dut)
{
    dut.dev_clk_low = 1;
    ticks(dut, 4);
    dut.dev_clk_low = 0;
    ticks(dut, 4);
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Vps2_host_sim_top dut;
    dut.sys_rst = 1;
    dut.dev_clk_low = 0;
    dut.dev_data_low = 0;
    dut.send_req = 0;
    dut.tx_data = 0;
    ticks(dut, 4);
    dut.sys_rst = 0;
    ticks(dut, 8);

    device_byte(dut, 0x1c);
    device_byte(dut, 0xe0);
    device_byte(dut, 0xf0);
    if (received.size() != 3 || received[0] != 0x1c ||
        received[1] != 0xe0 || received[2] != 0xf0) {
        std::fprintf(stderr, "FAIL PS/2 RX byte stream\n");
        return 1;
    }
    device_byte(dut, 0x55, true);
    if (errors == 0) {
        std::fprintf(stderr, "FAIL PS/2 parity error was not detected\n");
        return 1;
    }

    errors = 0;
    dut.tx_data = 0xed;
    dut.send_req = 1;
    tick(dut);
    dut.send_req = 0;
    for (unsigned int timeout = 0; timeout < 200 && !dut.ps2_clk_level;
         ++timeout)
        tick(dut);
    if (!dut.busy || !dut.ps2_clk_level || dut.ps2_data_level) {
        std::fprintf(stderr, "FAIL PS/2 request-to-send\n");
        return 1;
    }
    /* Let the host synchronizer observe the released clock before the
       keyboard starts producing its clock pulses. */
    ticks(dut, 8);

    unsigned int frame = 0;
    for (unsigned int bit = 0; bit < 11; ++bit) {
        dut.dev_clk_low = 1;
        ticks(dut, 4);
        frame |= static_cast<unsigned int>(dut.ps2_data_level) << bit;
        dut.dev_clk_low = 0;
        ticks(dut, 4);
    }
    dut.dev_data_low = 1;
    device_clock(dut);
    device_clock(dut);
    dut.dev_data_low = 0;
    ticks(dut, 8);

    const unsigned int expected = (0xedU << 1) |
        ((!(static_cast<unsigned int>(__builtin_popcount(0xed)) & 1U)) << 9) |
        (1U << 10);
    if (frame != expected || dut.busy || errors != 0) {
        std::fprintf(stderr,
                     "FAIL PS/2 TX frame=%03x expected=%03x busy=%u errors=%u\n",
                     frame, expected, dut.busy, errors);
        return 1;
    }

    std::printf("PASS PS/2 RX, E0/F0, parity error and host TX/ACK\n");
    return 0;
}

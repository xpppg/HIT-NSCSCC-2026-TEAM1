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
       keyboard starts producing its clock pulses.  This delay is longer than
       the old 0.2-ms watchdog at the simulation's 1-MHz system clock, so it
       also verifies that send_req reloads the extended TX watchdog. */
    ticks(dut, 1000);
    if (!dut.busy || errors != 0) {
        std::fprintf(stderr,
                     "FAIL PS/2 TX watchdog expired before device clock\n");
        return 1;
    }

    /* START is the request-to-send condition and is already asserted before
       the keyboard starts clocking.  Each of the next ten keyboard clocks
       transfers D0..D7, parity and stop; host-to-device data is prepared
       during the low phase and sampled by the keyboard on the rising edge. */
    if (dut.ps2_data_level) {
        std::fprintf(stderr, "FAIL PS/2 START was not held low\n");
        return 1;
    }

    unsigned int frame = 0;
    for (unsigned int bit = 0; bit < 10; ++bit) {
        dut.dev_clk_low = 1;
        ticks(dut, 4);
        frame |= static_cast<unsigned int>(dut.ps2_data_level) << bit;
        dut.dev_clk_low = 0;
        ticks(dut, 4);
    }
    dut.dev_data_low = 1;
    /* A keyboard supplies one additional clock while holding DATA low for
       ACK.  Allow input synchronization/setup time, then verify that the host
       completes the transfer on this single clock. */
    ticks(dut, 4);
    device_clock(dut);
    dut.dev_data_low = 0;
    ticks(dut, 8);

    const unsigned int expected = 0xedU |
        ((!(static_cast<unsigned int>(__builtin_popcount(0xed)) & 1U)) << 8) |
        (1U << 9);
    if (frame != expected || dut.busy || errors != 0) {
        std::fprintf(stderr,
                     "FAIL PS/2 TX frame=%03x expected=%03x busy=%u errors=%u\n",
                     frame, expected, dut.busy, errors);
        return 1;
    }

    std::printf("PASS PS/2 RX, E0/F0, parity error and host TX/ACK\n");
    return 0;
}

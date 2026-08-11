#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
OUT="$ROOT/IP/AVP/sim/obj_display"

verilator --cc "$ROOT/IP/VGA/projectf/display_timings.v" \
    --exe "$ROOT/IP/AVP/sim/display_timings_test.cpp" \
    --top-module display_timings --Mdir "$OUT"
make -C "$OUT" -f Vdisplay_timings.mk
"$OUT/Vdisplay_timings"

PS2_OUT="$ROOT/IP/AVP/sim/obj_ps2"
verilator --cc "$ROOT/IP/AVP/sim/ps2_host_sim_top.v" \
    "$ROOT/IP/PS2/opencores_host/ps2_host.v" \
    --exe "$ROOT/IP/AVP/sim/ps2_host_test.cpp" \
    --top-module ps2_host_sim_top --Mdir "$PS2_OUT"
make -C "$PS2_OUT" -f Vps2_host_sim_top.mk
"$PS2_OUT/Vps2_host_sim_top"

I2S_OUT="$ROOT/IP/AVP/sim/obj_i2s"
verilator --cc "$ROOT/IP/AVP/avp_i2s.v" \
    "$ROOT/IP/AVP/avp_async_fifo.v" \
    --exe "$ROOT/IP/AVP/sim/i2s_test.cpp" \
    --top-module avp_i2s --Mdir "$I2S_OUT"
make -C "$I2S_OUT" -f Vavp_i2s.mk
"$I2S_OUT/Vavp_i2s"

DMA_OUT="$ROOT/IP/AVP/sim/obj_dma"
verilator --cc "$ROOT/IP/AVP/avp_stream_dma.v" \
    --exe "$ROOT/IP/AVP/sim/stream_dma_test.cpp" \
    --top-module avp_stream_dma --Mdir "$DMA_OUT"
make -C "$DMA_OUT" -f Vavp_stream_dma.mk
"$DMA_OUT/Vavp_stream_dma"

VGA_OUT="$ROOT/IP/AVP/sim/obj_vga"
verilator --cc "$ROOT/IP/AVP/avp_vga.v" \
    "$ROOT/IP/AVP/avp_async_fifo.v" \
    "$ROOT/IP/VGA/projectf/display_timings.v" \
    --exe "$ROOT/IP/AVP/sim/vga_test.cpp" \
    --top-module avp_vga --Mdir "$VGA_OUT"
make -C "$VGA_OUT" -f Vavp_vga.mk
"$VGA_OUT/Vavp_vga"

verilator --lint-only -Wall -Wno-fatal -Wno-PINCONNECTEMPTY \
    "$ROOT/IP/AVP/avp_async_fifo.v" \
    "$ROOT/IP/AVP/avp_stream_dma.v" \
    "$ROOT/IP/VGA/projectf/display_timings.v" \
    "$ROOT/IP/AVP/avp_vga.v" \
    "$ROOT/IP/AVP/avp_i2s.v" \
    "$ROOT/IP/PS2/opencores_host/ps2_host.v" \
    "$ROOT/IP/AVP/avp_axi_controller.v"

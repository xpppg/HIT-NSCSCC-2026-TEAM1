`timescale 1ns / 1ps

module ps2_host_sim_top (
    input  wire       sys_clk,
    input  wire       sys_rst,
    input  wire       dev_clk_low,
    input  wire       dev_data_low,
    input  wire [7:0] tx_data,
    input  wire       send_req,
    output wire       busy,
    output wire [7:0] rx_data,
    output wire       ready,
    output wire       error,
    output wire       ps2_clk_level,
    output wire       ps2_data_level
);
    tri1 ps2_clk;
    tri1 ps2_data;
    wire [1:0] error_reason_unused;
    wire [4:0] tx_edge_count_unused;

    assign ps2_clk = dev_clk_low ? 1'b0 : 1'bz;
    assign ps2_data = dev_data_low ? 1'b0 : 1'bz;
    assign ps2_clk_level = ps2_clk;
    assign ps2_data_level = ps2_data;

    ps2_host #(.SYS_CLOCK_HZ(1_000_000)) dut (
        .sys_clk(sys_clk), .sys_rst(sys_rst),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .tx_data(tx_data), .send_req(send_req), .busy(busy),
        .rx_data(rx_data), .ready(ready), .error(error),
        .error_reason(error_reason_unused),
        .tx_edge_count(tx_edge_count_unused)
    );
endmodule

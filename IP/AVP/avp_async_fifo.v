`timescale 1ns / 1ps

// Dual-clock show-ahead FIFO.  Vivado uses the verified XPM implementation;
// the behavioral branch keeps Icarus/Verilator simulations self-contained.
module avp_async_fifo #(
    parameter integer DATA_WIDTH = 64,
    parameter integer DEPTH = 512,
    parameter integer COUNT_WIDTH = $clog2(DEPTH) + 1
)(
    input  wire                  rst,
    input  wire                  wr_clk,
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  wr_en,
    output wire                  full,
    input  wire                  rd_clk,
    output wire [DATA_WIDTH-1:0] dout,
    input  wire                  rd_en,
    output wire                  empty
);
`ifdef SYNTHESIS
    wire overflow_unused;
    wire underflow_unused;
    wire wr_busy_unused;
    wire rd_busy_unused;
    wire data_valid_unused;
    wire almost_full_unused;
    wire almost_empty_unused;
    wire prog_full_unused;
    wire prog_empty_unused;
    wire dbiterr_unused;
    wire sbiterr_unused;
    wire [COUNT_WIDTH-1:0] wr_count_unused;
    wire [COUNT_WIDTH-1:0] rd_count_unused;

    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .DOUT_RESET_VALUE("0"),
        .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("block"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(DEPTH),
        .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH(DEPTH-10),
        .RD_DATA_COUNT_WIDTH(COUNT_WIDTH),
        .READ_DATA_WIDTH(DATA_WIDTH),
        .READ_MODE("fwft"),
        .RELATED_CLOCKS(0),
        .USE_ADV_FEATURES("0000"),
        .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(DATA_WIDTH),
        .WR_DATA_COUNT_WIDTH(COUNT_WIDTH)
    ) u_fifo (
        .rst(rst),
        .wr_clk(wr_clk), .din(din), .wr_en(wr_en), .full(full),
        .overflow(overflow_unused), .wr_rst_busy(wr_busy_unused),
        .wr_data_count(wr_count_unused), .almost_full(almost_full_unused),
        .prog_full(prog_full_unused),
        .rd_clk(rd_clk), .dout(dout), .rd_en(rd_en), .empty(empty),
        .underflow(underflow_unused), .rd_rst_busy(rd_busy_unused),
        .rd_data_count(rd_count_unused), .data_valid(data_valid_unused),
        .almost_empty(almost_empty_unused), .prog_empty(prog_empty_unused),
        .sleep(1'b0), .injectdbiterr(1'b0), .injectsbiterr(1'b0),
        .dbiterr(dbiterr_unused), .sbiterr(sbiterr_unused)
    );
`else
    localparam integer ADDR_WIDTH = $clog2(DEPTH);
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wbin, rbin;
    reg [ADDR_WIDTH:0] wgray, rgray;
    reg [ADDR_WIDTH:0] rgray_w1, rgray_w2;
    reg [ADDR_WIDTH:0] wgray_r1, wgray_r2;
    wire [ADDR_WIDTH:0] wbin_next = wbin + {{ADDR_WIDTH{1'b0}},
                                            (wr_en && !full)};
    wire [ADDR_WIDTH:0] rbin_next = rbin + {{ADDR_WIDTH{1'b0}},
                                            (rd_en && !empty)};
    wire [ADDR_WIDTH:0] wgray_next = (wbin_next >> 1) ^ wbin_next;
    wire [ADDR_WIDTH:0] rgray_next = (rbin_next >> 1) ^ rbin_next;
    wire [ADDR_WIDTH:0] full_compare =
        {~rgray_w2[ADDR_WIDTH:ADDR_WIDTH-1], rgray_w2[ADDR_WIDTH-2:0]};
    reg full_reg, empty_reg;
    assign full = full_reg;
    assign empty = empty_reg;
    assign dout = memory[rbin[ADDR_WIDTH-1:0]];

    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            wbin <= 0; wgray <= 0; rgray_w1 <= 0; rgray_w2 <= 0;
            full_reg <= 1'b0;
        end else begin
            rgray_w1 <= rgray; rgray_w2 <= rgray_w1;
            if (wr_en && !full)
                memory[wbin[ADDR_WIDTH-1:0]] <= din;
            wbin <= wbin_next; wgray <= wgray_next;
            full_reg <= (wgray_next == full_compare);
        end
    end
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            rbin <= 0; rgray <= 0; wgray_r1 <= 0; wgray_r2 <= 0;
            empty_reg <= 1'b1;
        end else begin
            wgray_r1 <= wgray; wgray_r2 <= wgray_r1;
            rbin <= rbin_next; rgray <= rgray_next;
            empty_reg <= (rgray_next == wgray_r2);
        end
    end
`endif
endmodule

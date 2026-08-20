`timescale 1ns / 1ps

// AXI3 slave wrapper for the OpenCores I2C master by Richard Herveille.
//
// Physical base address is selected by the SoC AXI slave mux.  Registers are
// exposed as 32-bit, little-endian MMIO with a four-byte stride, matching the
// Linux i2c-ocores settings reg-io-width = <4> and reg-shift = <2>:
//
//   0x00 PRER low             0x04 PRER high
//   0x08 control              0x0c TX/RX
//   0x10 command/status       0x14..0x1c reserved by OpenCores
//   0x20 TOUCH_CTRL [0] reset_n, [1] drive INT low
//   0x24 TOUCH_STAT [0] INT, [1] SCL, [2] SDA, [3] reset_n
//
// The upstream I2C RTL is kept unchanged in IP/I2C/opencores.  This wrapper
// only translates AXI transactions to its native 8-bit Wishbone interface.
module axi_i2c_ocores #(
    parameter AXI_ID_WIDTH   = 4,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_LEN_WIDTH  = 4
)(
    input  wire                         s_axi_aclk,
    input  wire                         s_axi_aresetn,

    input  wire [AXI_ID_WIDTH-1:0]      s_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [AXI_LEN_WIDTH-1:0]     s_axi_awlen,
    input  wire [2:0]                   s_axi_awsize,
    input  wire [1:0]                   s_axi_awburst,
    input  wire [1:0]                   s_axi_awlock,
    input  wire [3:0]                   s_axi_awcache,
    input  wire [2:0]                   s_axi_awprot,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,

    input  wire [AXI_ID_WIDTH-1:0]      s_axi_wid,
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                         s_axi_wlast,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,

    output wire [AXI_ID_WIDTH-1:0]      s_axi_bid,
    output wire [1:0]                   s_axi_bresp,
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,

    input  wire [AXI_ID_WIDTH-1:0]      s_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [AXI_LEN_WIDTH-1:0]     s_axi_arlen,
    input  wire [2:0]                   s_axi_arsize,
    input  wire [1:0]                   s_axi_arburst,
    input  wire [1:0]                   s_axi_arlock,
    input  wire [3:0]                   s_axi_arcache,
    input  wire [2:0]                   s_axi_arprot,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,

    output wire [AXI_ID_WIDTH-1:0]      s_axi_rid,
    output wire [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output wire                         s_axi_rlast,
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready,

    output wire                         i2c_irq,
    inout  wire                         touch_scl,
    inout  wire                         touch_sda,
    inout  wire                         touch_int,
    output wire                         touch_rst_n
);

    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam [1:0] AXI_BURST_FIXED = 2'b00;
    localparam [1:0] AXI_BURST_INCR  = 2'b01;

    localparam [2:0] WR_IDLE = 3'd0;
    localparam [2:0] WR_DATA = 3'd1;
    localparam [2:0] WR_WB   = 3'd2;
    localparam [2:0] WR_RESP = 3'd3;

    localparam [1:0] RD_IDLE = 2'd0;
    localparam [1:0] RD_WB   = 2'd1;
    localparam [1:0] RD_RESP = 2'd2;

    reg [2:0]                  wr_state;
    reg [AXI_ID_WIDTH-1:0]     wr_id;
    reg [AXI_ADDR_WIDTH-1:0]   wr_addr;
    reg [AXI_LEN_WIDTH:0]      wr_beats_left;
    reg [1:0]                  wr_burst;
    reg                        wr_protocol_ok;
    reg [1:0]                  wr_resp;
    reg [7:0]                  wr_byte;

    reg [1:0]                  rd_state;
    reg [AXI_ID_WIDTH-1:0]     rd_id;
    reg [AXI_ADDR_WIDTH-1:0]   rd_addr;
    reg [AXI_LEN_WIDTH:0]      rd_beats_left;
    reg [1:0]                  rd_burst;
    reg                        rd_protocol_ok;
    reg [31:0]                 rd_data;
    reg [1:0]                  rd_resp;

    reg                        wb_cyc;
    reg                        wb_stb;
    reg                        wb_we;
    reg [2:0]                  wb_addr;
    reg [7:0]                  wb_data_i;
    wire [7:0]                 wb_data_o;
    wire                       wb_ack;

    wire scl_pad_o;
    wire scl_padoen_o;
    wire sda_pad_o;
    wire sda_padoen_o;

    reg [1:0] touch_ctrl;

    wire wr_expected_last =
        (wr_beats_left == {{AXI_LEN_WIDTH{1'b0}}, 1'b1});
    wire rd_expected_last =
        (rd_beats_left == {{AXI_LEN_WIDTH{1'b0}}, 1'b1});
    wire wr_is_ocores = (wr_addr[7:2] < 6'd8);
    wire wr_is_touch_ctrl = (wr_addr[7:0] == 8'h20);
    wire rd_is_ocores = (rd_addr[7:2] < 6'd8);
    wire rd_is_touch_ctrl = (rd_addr[7:0] == 8'h20);
    wire rd_is_touch_stat = (rd_addr[7:0] == 8'h24);

    assign s_axi_awready = (wr_state == WR_IDLE);
    assign s_axi_wready  = (wr_state == WR_DATA);
    assign s_axi_bid     = wr_id;
    assign s_axi_bresp   = wr_resp;
    assign s_axi_bvalid  = (wr_state == WR_RESP);

    assign s_axi_arready = (rd_state == RD_IDLE) && (wr_state != WR_WB);
    assign s_axi_rid     = rd_id;
    assign s_axi_rdata   = rd_data;
    assign s_axi_rresp   = rd_resp;
    assign s_axi_rlast   = (rd_state == RD_RESP) && rd_expected_last;
    assign s_axi_rvalid  = (rd_state == RD_RESP);

    // OpenCores uses *_padoen_o=1 to release the line.  Never actively drive
    // a high level on an I2C signal.
    assign touch_scl = scl_padoen_o ? 1'bz : scl_pad_o;
    assign touch_sda = sda_padoen_o ? 1'bz : sda_pad_o;
    assign touch_int = touch_ctrl[1] ? 1'b0 : 1'bz;
    assign touch_rst_n = touch_ctrl[0];

    i2c_master_top u_i2c_master (
        .wb_clk_i     (s_axi_aclk),
        .wb_rst_i     (1'b0),
        .arst_i       (s_axi_aresetn),
        .wb_adr_i     (wb_addr),
        .wb_dat_i     (wb_data_i),
        .wb_dat_o     (wb_data_o),
        .wb_we_i      (wb_we),
        .wb_stb_i     (wb_stb),
        .wb_cyc_i     (wb_cyc),
        .wb_ack_o     (wb_ack),
        .wb_inta_o    (i2c_irq),
        .scl_pad_i    (touch_scl),
        .scl_pad_o    (scl_pad_o),
        .scl_padoen_o (scl_padoen_o),
        .sda_pad_i    (touch_sda),
        .sda_pad_o    (sda_pad_o),
        .sda_padoen_o (sda_padoen_o)
    );

    // AXI write channel.  One AXI beat becomes one 8-bit Wishbone access.
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wr_state       <= WR_IDLE;
            wr_id          <= {AXI_ID_WIDTH{1'b0}};
            wr_addr        <= {AXI_ADDR_WIDTH{1'b0}};
            wr_beats_left  <= {(AXI_LEN_WIDTH+1){1'b0}};
            wr_burst       <= AXI_BURST_INCR;
            wr_protocol_ok <= 1'b0;
            wr_resp        <= AXI_RESP_OKAY;
            wr_byte        <= 8'h00;
            // Keep Goodix out of reset after FPGA configuration.  INT is
            // released, so the external pull-up selects I2C address 0x14.
            touch_ctrl     <= 2'b01;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id         <= s_axi_awid;
                        wr_addr       <= s_axi_awaddr;
                        wr_beats_left <= {1'b0, s_axi_awlen} + 1'b1;
                        wr_burst      <= s_axi_awburst;
                        wr_protocol_ok <= (s_axi_awsize == 3'b010) &&
                            ((s_axi_awburst == AXI_BURST_FIXED) ||
                             (s_axi_awburst == AXI_BURST_INCR)) &&
                            (s_axi_awaddr[1:0] == 2'b00);
                        wr_resp <= AXI_RESP_OKAY;
                        wr_state <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        if (!wr_protocol_ok || (s_axi_wid != wr_id) ||
                            !s_axi_wstrb[0] ||
                            (s_axi_wlast != wr_expected_last) ||
                            !(wr_is_ocores || wr_is_touch_ctrl))
                            wr_resp <= AXI_RESP_SLVERR;

                        if (wr_protocol_ok && (s_axi_wid == wr_id) &&
                            s_axi_wstrb[0] && wr_is_touch_ctrl) begin
                            touch_ctrl <= s_axi_wdata[1:0];
                            if (wr_expected_last || s_axi_wlast)
                                wr_state <= WR_RESP;
                            else begin
                                wr_beats_left <= wr_beats_left - 1'b1;
                                if (wr_burst == AXI_BURST_INCR)
                                    wr_addr <= wr_addr + 32'd4;
                            end
                        end else if (wr_protocol_ok &&
                                     (s_axi_wid == wr_id) &&
                                     s_axi_wstrb[0] && wr_is_ocores) begin
                            wr_byte   <= s_axi_wdata[7:0];
                            wr_state  <= WR_WB;
                        end else begin
                            wr_state <= WR_RESP;
                        end
                    end
                end

                WR_WB: begin
                    if (wb_ack) begin
                        if (wr_expected_last)
                            wr_state <= WR_RESP;
                        else begin
                            wr_beats_left <= wr_beats_left - 1'b1;
                            if (wr_burst == AXI_BURST_INCR)
                                wr_addr <= wr_addr + 32'd4;
                            wr_state <= WR_DATA;
                        end
                    end
                end

                WR_RESP: begin
                    if (s_axi_bready)
                        wr_state <= WR_IDLE;
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // AXI read channel.  Reads of the two touch-control registers are local;
    // OpenCores register reads are translated to Wishbone cycles.
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            rd_state       <= RD_IDLE;
            rd_id          <= {AXI_ID_WIDTH{1'b0}};
            rd_addr        <= {AXI_ADDR_WIDTH{1'b0}};
            rd_beats_left  <= {(AXI_LEN_WIDTH+1){1'b0}};
            rd_burst       <= AXI_BURST_INCR;
            rd_protocol_ok <= 1'b0;
            rd_data        <= 32'h0000_0000;
            rd_resp        <= AXI_RESP_OKAY;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_id         <= s_axi_arid;
                        rd_addr       <= s_axi_araddr;
                        rd_beats_left <= {1'b0, s_axi_arlen} + 1'b1;
                        rd_burst      <= s_axi_arburst;
                        rd_protocol_ok <= (s_axi_arsize == 3'b010) &&
                            ((s_axi_arburst == AXI_BURST_FIXED) ||
                             (s_axi_arburst == AXI_BURST_INCR)) &&
                            (s_axi_araddr[1:0] == 2'b00);
                        rd_resp <= AXI_RESP_OKAY;

                        if ((s_axi_arsize != 3'b010) ||
                            !((s_axi_arburst == AXI_BURST_FIXED) ||
                              (s_axi_arburst == AXI_BURST_INCR)) ||
                            (s_axi_araddr[1:0] != 2'b00)) begin
                            rd_data  <= 32'h0000_0000;
                            rd_resp  <= AXI_RESP_SLVERR;
                            rd_state <= RD_RESP;
                        end else if (s_axi_araddr[7:0] == 8'h20) begin
                            rd_data  <= {30'b0, touch_ctrl};
                            rd_state <= RD_RESP;
                        end else if (s_axi_araddr[7:0] == 8'h24) begin
                            rd_data <= {28'b0, touch_ctrl[0], touch_sda,
                                        touch_scl, touch_int};
                            rd_state <= RD_RESP;
                        end else if (s_axi_araddr[7:2] < 6'd8) begin
                            rd_state <= RD_WB;
                        end else begin
                            rd_data  <= 32'h0000_0000;
                            rd_resp  <= AXI_RESP_SLVERR;
                            rd_state <= RD_RESP;
                        end
                    end
                end

                RD_WB: begin
                    if (wb_ack) begin
                        rd_data  <= {24'b0, wb_data_o};
                        rd_state <= RD_RESP;
                    end
                end

                RD_RESP: begin
                    if (s_axi_rready) begin
                        if (rd_expected_last)
                            rd_state <= RD_IDLE;
                        else begin
                            rd_beats_left <= rd_beats_left - 1'b1;
                            if (rd_burst == AXI_BURST_INCR)
                                rd_addr <= rd_addr + 32'd4;

                            if (!rd_protocol_ok) begin
                                rd_data  <= 32'h0000_0000;
                                rd_resp  <= AXI_RESP_SLVERR;
                                rd_state <= RD_RESP;
                            end else if (((rd_burst == AXI_BURST_INCR) ?
                                         (rd_addr[7:0] + 8'd4) :
                                          rd_addr[7:0]) == 8'h20) begin
                                rd_data  <= {30'b0, touch_ctrl};
                                rd_resp  <= AXI_RESP_OKAY;
                                rd_state <= RD_RESP;
                            end else begin
                                rd_resp  <= AXI_RESP_OKAY;
                                rd_state <= RD_WB;
                            end
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // A single Wishbone port is shared by AXI reads and writes.  The AXI read
    // address channel is blocked while a write-side Wishbone cycle is active.
    always @(*) begin
        wb_cyc    = 1'b0;
        wb_stb    = 1'b0;
        wb_we     = 1'b0;
        wb_addr   = 3'b000;
        wb_data_i = wr_byte;

        if (wr_state == WR_WB) begin
            wb_cyc  = 1'b1;
            wb_stb  = 1'b1;
            wb_we   = 1'b1;
            wb_addr = wr_addr[4:2];
        end else if (rd_state == RD_WB) begin
            wb_cyc  = 1'b1;
            wb_stb  = 1'b1;
            wb_we   = 1'b0;
            wb_addr = rd_addr[4:2];
        end
    end

    wire unused_axi_attributes = ^{s_axi_awlock, s_axi_awcache,
        s_axi_awprot, s_axi_arlock, s_axi_arcache, s_axi_arprot,
        s_axi_wstrb[3:1], sda_pad_o, rd_is_ocores, rd_is_touch_ctrl,
        rd_is_touch_stat};

endmodule

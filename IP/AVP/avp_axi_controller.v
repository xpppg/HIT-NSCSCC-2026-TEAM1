`timescale 1ns / 1ps

// Audio/Video/PS2 register block.  This is intentionally a narrow AXI3
// peripheral: only aligned, 32-bit, single-beat CPU transactions are accepted.
module avp_axi_controller (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        pix_clk,
    input  wire        pix_locked,
    input  wire        aud_clk,
    input  wire        aud_locked,

    input  wire [3:0]  s_axi_awid,
    input  wire [31:0] s_axi_awaddr,
    input  wire [3:0]  s_axi_awlen,
    input  wire [2:0]  s_axi_awsize,
    input  wire [1:0]  s_axi_awburst,
    input  wire [1:0]  s_axi_awlock,
    input  wire [3:0]  s_axi_awcache,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [3:0]  s_axi_wid,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wlast,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output reg  [3:0]  s_axi_bid,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [3:0]  s_axi_arid,
    input  wire [31:0] s_axi_araddr,
    input  wire [3:0]  s_axi_arlen,
    input  wire [2:0]  s_axi_arsize,
    input  wire [1:0]  s_axi_arburst,
    input  wire [1:0]  s_axi_arlock,
    input  wire [3:0]  s_axi_arcache,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [3:0]  s_axi_rid,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output wire        s_axi_rlast,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    output wire [3:0]  i2s_m_axi_arid,
    output wire [31:0] i2s_m_axi_araddr,
    output wire [3:0]  i2s_m_axi_arlen,
    output wire [2:0]  i2s_m_axi_arsize,
    output wire [1:0]  i2s_m_axi_arburst,
    output wire [1:0]  i2s_m_axi_arlock,
    output wire [3:0]  i2s_m_axi_arcache,
    output wire [2:0]  i2s_m_axi_arprot,
    output wire        i2s_m_axi_arvalid,
    input  wire        i2s_m_axi_arready,
    input  wire [3:0]  i2s_m_axi_rid,
    input  wire [63:0] i2s_m_axi_rdata,
    input  wire [1:0]  i2s_m_axi_rresp,
    input  wire        i2s_m_axi_rlast,
    input  wire        i2s_m_axi_rvalid,
    output wire        i2s_m_axi_rready,

    output wire [3:0]  vga_m_axi_arid,
    output wire [31:0] vga_m_axi_araddr,
    output wire [3:0]  vga_m_axi_arlen,
    output wire [2:0]  vga_m_axi_arsize,
    output wire [1:0]  vga_m_axi_arburst,
    output wire [1:0]  vga_m_axi_arlock,
    output wire [3:0]  vga_m_axi_arcache,
    output wire [2:0]  vga_m_axi_arprot,
    output wire        vga_m_axi_arvalid,
    input  wire        vga_m_axi_arready,
    input  wire [3:0]  vga_m_axi_rid,
    input  wire [63:0] vga_m_axi_rdata,
    input  wire [1:0]  vga_m_axi_rresp,
    input  wire        vga_m_axi_rlast,
    input  wire        vga_m_axi_rvalid,
    output wire        vga_m_axi_rready,

    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,
    inout  wire        ps2_clk,
    inout  wire        ps2_data,
    output wire        i2s_bclk,
    output wire        i2s_lrclk,
    output wire        i2s_data,
    output wire        media_irq
);
    localparam [15:0] I2S_PAGE = 16'h1fa2;
    localparam [15:0] VGA_PAGE = 16'h1fa3;
    localparam [15:0] PS2_PAGE = 16'h1fa4;

    function automatic [31:0] merge_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] strobes;
        integer byte_index;
        begin
            merge_wstrb = old_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                if (strobes[byte_index])
                    merge_wstrb[byte_index*8 +: 8] =
                        new_value[byte_index*8 +: 8];
        end
    endfunction

    function automatic register_address_valid;
        input [31:0] address;
        input is_write;
        begin
            register_address_valid = 1'b0;
            case (address[31:16])
                I2S_PAGE: begin
                    if (is_write)
                        register_address_valid = address[15:0] == 16'h0000 ||
                            address[15:0] == 16'h0004 || address[15:0] == 16'h0008 ||
                            address[15:0] == 16'h000c || address[15:0] == 16'h0010;
                    else
                        register_address_valid = address[15:0] == 16'h0000 ||
                            address[15:0] == 16'h0004 || address[15:0] == 16'h0008 ||
                            address[15:0] == 16'h000c || address[15:0] == 16'h0010 ||
                            address[15:0] == 16'h0014 || address[15:0] == 16'h0018;
                end
                VGA_PAGE: begin
                    if (is_write)
                        register_address_valid = address[15:0] == 16'h0000 ||
                            address[15:0] == 16'h0004 || address[15:0] == 16'h0008 ||
                            address[15:0] == 16'h000c;
                    else
                        register_address_valid = address[15:0] == 16'h0000 ||
                            address[15:0] == 16'h0004 || address[15:0] == 16'h0008 ||
                            address[15:0] == 16'h000c || address[15:0] == 16'h0010 ||
                            address[15:0] == 16'h0014;
                end
                PS2_PAGE: begin
                    if (is_write)
                        register_address_valid = address[15:0] == 16'h0000 ||
                            address[15:0] == 16'h0004 || address[15:0] == 16'h0008 ||
                            address[15:0] == 16'hf004 || address[15:0] == 16'hf008 ||
                            address[15:0] == 16'hf00c;
                    else
                        register_address_valid = address[15:0] == 16'h0000 ||
                            address[15:0] == 16'h0004 || address[15:0] == 16'h0008 ||
                            address[15:0] == 16'h000c || address[15:0] == 16'hf000 ||
                            address[15:0] == 16'hf004 || address[15:0] == 16'hf008 ||
                            address[15:0] == 16'hf00c;
                end
                default: register_address_valid = 1'b0;
            endcase
        end
    endfunction

    reg [31:0] i2s_ctrl;
    reg [31:0] i2s_buf_addr;
    reg [31:0] i2s_buf_bytes;
    reg [31:0] i2s_period_bytes;
    reg [2:0]  i2s_status;
    reg [31:0] vga_ctrl;
    reg [31:0] vga_fb_addr;
    reg [31:0] vga_stride;
    reg [1:0]  vga_status;
    reg        ps2_enable;
    reg [1:0]  ps2_status;
    reg [2:0]  irq_enable;

    wire i2s_running;
    wire i2s_dma_error;
    wire [63:0] i2s_stream_data;
    wire i2s_stream_valid;
    wire i2s_stream_ready;
    wire [31:0] i2s_play_pos;
    wire i2s_period_event;
    wire i2s_underflow_event;

    avp_stream_dma #(.AXI_ID(4'h5)) u_i2s_dma (
        .clk(aclk), .resetn(aresetn), .enable(i2s_ctrl[0]),
        .base_addr(i2s_buf_addr), .byte_length(i2s_buf_bytes),
        .running(i2s_running), .error(i2s_dma_error),
        .fetched_pos(),
        .stream_data(i2s_stream_data), .stream_valid(i2s_stream_valid),
        .stream_ready(i2s_stream_ready),
        .m_axi_arid(i2s_m_axi_arid), .m_axi_araddr(i2s_m_axi_araddr),
        .m_axi_arlen(i2s_m_axi_arlen), .m_axi_arsize(i2s_m_axi_arsize),
        .m_axi_arburst(i2s_m_axi_arburst), .m_axi_arlock(i2s_m_axi_arlock),
        .m_axi_arcache(i2s_m_axi_arcache), .m_axi_arprot(i2s_m_axi_arprot),
        .m_axi_arvalid(i2s_m_axi_arvalid), .m_axi_arready(i2s_m_axi_arready),
        .m_axi_rid(i2s_m_axi_rid), .m_axi_rdata(i2s_m_axi_rdata),
        .m_axi_rresp(i2s_m_axi_rresp), .m_axi_rlast(i2s_m_axi_rlast),
        .m_axi_rvalid(i2s_m_axi_rvalid), .m_axi_rready(i2s_m_axi_rready)
    );

    avp_i2s u_i2s (
        .bus_clk(aclk), .bus_resetn(aresetn),
        .aud_clk(aud_clk), .aud_locked(aud_locked),
        .enable(i2s_ctrl[0]), .buffer_bytes(i2s_buf_bytes),
        .period_bytes(i2s_period_bytes),
        .stream_data(i2s_stream_data), .stream_valid(i2s_stream_valid),
        .stream_ready(i2s_stream_ready), .play_pos(i2s_play_pos),
        .period_event(i2s_period_event),
        .underflow_event(i2s_underflow_event),
        .i2s_bclk(i2s_bclk), .i2s_lrclk(i2s_lrclk), .i2s_data(i2s_data)
    );

    wire vga_running;
    wire vga_dma_error;
    wire [31:0] vga_fetched_pos;
    wire [63:0] vga_stream_data;
    wire vga_stream_valid;
    wire vga_stream_ready;
    wire vga_underflow_event;

    avp_stream_dma #(.AXI_ID(4'h6)) u_vga_dma (
        .clk(aclk), .resetn(aresetn), .enable(vga_ctrl[0]),
        .base_addr(vga_fb_addr), .byte_length(32'd614400),
        .running(vga_running), .error(vga_dma_error),
        .fetched_pos(vga_fetched_pos),
        .stream_data(vga_stream_data), .stream_valid(vga_stream_valid),
        .stream_ready(vga_stream_ready),
        .m_axi_arid(vga_m_axi_arid), .m_axi_araddr(vga_m_axi_araddr),
        .m_axi_arlen(vga_m_axi_arlen), .m_axi_arsize(vga_m_axi_arsize),
        .m_axi_arburst(vga_m_axi_arburst), .m_axi_arlock(vga_m_axi_arlock),
        .m_axi_arcache(vga_m_axi_arcache), .m_axi_arprot(vga_m_axi_arprot),
        .m_axi_arvalid(vga_m_axi_arvalid), .m_axi_arready(vga_m_axi_arready),
        .m_axi_rid(vga_m_axi_rid), .m_axi_rdata(vga_m_axi_rdata),
        .m_axi_rresp(vga_m_axi_rresp), .m_axi_rlast(vga_m_axi_rlast),
        .m_axi_rvalid(vga_m_axi_rvalid), .m_axi_rready(vga_m_axi_rready)
    );

    avp_vga u_vga (
        .bus_clk(aclk), .bus_resetn(aresetn),
        .pix_clk(pix_clk), .pix_locked(pix_locked), .enable(vga_ctrl[0]),
        .stream_data(vga_stream_data), .stream_valid(vga_stream_valid),
        .stream_ready(vga_stream_ready), .vga_r(vga_r), .vga_g(vga_g),
        .vga_b(vga_b), .vga_hsync(vga_hsync), .vga_vsync(vga_vsync),
        .underflow_event(vga_underflow_event)
    );

    wire [7:0] ps2_rx_data;
    wire ps2_rx_ready;
    wire ps2_host_error;
    wire ps2_busy;
    reg [7:0] ps2_tx_data;
    reg ps2_send;
    ps2_host #(.SYS_CLOCK_HZ(33_000_000)) u_ps2 (
        .sys_clk(aclk), .sys_rst(!aresetn || !ps2_enable),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .tx_data(ps2_tx_data), .send_req(ps2_send), .busy(ps2_busy),
        .rx_data(ps2_rx_data), .ready(ps2_rx_ready), .error(ps2_host_error)
    );

    reg [7:0] ps2_fifo [0:15];
    reg [3:0] ps2_wr_ptr;
    reg [3:0] ps2_rd_ptr;
    reg [4:0] ps2_count;

    wire [2:0] irq_raw = {
        |vga_status,
        (ps2_count != 0) | (|ps2_status),
        |i2s_status
    };
    assign media_irq = |(irq_raw & irq_enable);

    reg aw_held;
    reg [3:0] awid_held;
    reg [31:0] awaddr_held;
    reg aw_bad;
    reg w_held;
    reg [3:0] wid_held;
    reg [31:0] wdata_held;
    reg [3:0] wstrb_held;
    reg w_bad;
    assign s_axi_awready = !aw_held && !s_axi_bvalid;
    assign s_axi_wready = !w_held && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    assign s_axi_rlast = 1'b1;

    wire write_commit = aw_held && w_held && !s_axi_bvalid;
    wire write_good = !aw_bad && !w_bad && (awid_held == wid_held) &&
                      register_address_valid(awaddr_held, 1'b1);

    function automatic [31:0] register_read;
        input [31:0] address;
        begin
            register_read = 32'h00000000;
            case (address[31:16])
                I2S_PAGE: case (address[15:0])
                    16'h0000: register_read = i2s_ctrl;
                    16'h0004: register_read = {27'b0, i2s_dma_error,
                                               i2s_running, i2s_status};
                    16'h0008: register_read = i2s_buf_addr;
                    16'h000c: register_read = i2s_buf_bytes;
                    16'h0010: register_read = i2s_period_bytes;
                    16'h0014: register_read = i2s_play_pos;
                    16'h0018: register_read = 32'h0010ac44; // S16, 2ch, 44.1k
                    default: register_read = 0;
                endcase
                VGA_PAGE: case (address[15:0])
                    16'h0000: register_read = vga_ctrl;
                    16'h0004: register_read = {27'b0, vga_dma_error,
                                               vga_running, 1'b0, vga_status};
                    16'h0008: register_read = vga_fb_addr;
                    16'h000c: register_read = vga_stride;
                    16'h0010: register_read = {16'd480, 16'd640};
                    16'h0014: register_read = vga_fetched_pos;
                    default: register_read = 0;
                endcase
                PS2_PAGE: begin
                    if (address[15:0] == 16'h0000)
                        register_read = ps2_count != 0 ? {24'b0, ps2_fifo[ps2_rd_ptr]} : 0;
                    else if (address[15:0] == 16'h0004)
                        register_read = {19'b0, ps2_count[4:0], 6'b0,
                                         ps2_busy, |ps2_status};
                    else if (address[15:0] == 16'h0008)
                        register_read = {31'b0, ps2_enable};
                    else if (address[15:0] == 16'h000c)
                        register_read = 32'd33000000;
                    else if (address[15:12] == 4'hf)
                        case (address[3:0])
                            4'h0: register_read = {29'b0, irq_raw};
                            4'h4, 4'h8, 4'hc: register_read = {29'b0, irq_enable};
                            default: register_read = 0;
                        endcase
                end
                default: register_read = 0;
            endcase
        end
    endfunction

    wire read_good = (s_axi_arlen == 0) && (s_axi_arsize == 3'b010) &&
                     (s_axi_araddr[1:0] == 0) &&
                     register_address_valid(s_axi_araddr, 1'b0);
    wire ps2_pop = s_axi_arvalid && s_axi_arready && read_good &&
                   s_axi_araddr[31:16] == PS2_PAGE &&
                   s_axi_araddr[15:0] == 16'h0000 && ps2_count != 0;
    wire ps2_push = ps2_rx_ready && ps2_count != 16;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            i2s_ctrl <= 0; i2s_buf_addr <= 0; i2s_buf_bytes <= 0;
            i2s_period_bytes <= 0; i2s_status <= 0;
            vga_ctrl <= 0; vga_fb_addr <= 0; vga_stride <= 32'd1280;
            vga_status <= 0;
            ps2_enable <= 0; ps2_status <= 0; ps2_tx_data <= 0;
            ps2_send <= 0; ps2_wr_ptr <= 0; ps2_rd_ptr <= 0; ps2_count <= 0;
            irq_enable <= 0;
            aw_held <= 0; awid_held <= 0; awaddr_held <= 0; aw_bad <= 0;
            w_held <= 0; wid_held <= 0; wdata_held <= 0; wstrb_held <= 0;
            w_bad <= 0;
            s_axi_bid <= 0; s_axi_bresp <= 0; s_axi_bvalid <= 0;
            s_axi_rid <= 0; s_axi_rdata <= 0; s_axi_rresp <= 0;
            s_axi_rvalid <= 0;
        end else begin
            ps2_send <= 1'b0;

            if (i2s_period_event) i2s_status[0] <= 1'b1;
            if (i2s_underflow_event) i2s_status[1] <= 1'b1;
            if (i2s_dma_error) i2s_status[2] <= 1'b1;
            if (vga_underflow_event) vga_status[0] <= 1'b1;
            if (vga_dma_error) vga_status[1] <= 1'b1;
            if (ps2_host_error) ps2_status[0] <= 1'b1;

            if (ps2_push) begin
                ps2_fifo[ps2_wr_ptr] <= ps2_rx_data;
                ps2_wr_ptr <= ps2_wr_ptr + 1'b1;
            end
            if (ps2_rx_ready && !ps2_push)
                ps2_status[1] <= 1'b1;
            if (ps2_pop)
                ps2_rd_ptr <= ps2_rd_ptr + 1'b1;
            case ({ps2_push, ps2_pop})
                2'b10: ps2_count <= ps2_count + 1'b1;
                2'b01: ps2_count <= ps2_count - 1'b1;
                default: ps2_count <= ps2_count;
            endcase

            if (s_axi_awvalid && s_axi_awready) begin
                aw_held <= 1'b1;
                awid_held <= s_axi_awid;
                awaddr_held <= s_axi_awaddr;
                aw_bad <= (s_axi_awlen != 0) || (s_axi_awsize != 3'b010) ||
                          (s_axi_awaddr[1:0] != 0);
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_held <= 1'b1;
                wid_held <= s_axi_wid;
                wdata_held <= s_axi_wdata;
                wstrb_held <= s_axi_wstrb;
                w_bad <= !s_axi_wlast;
            end
            if (write_commit) begin
                aw_held <= 1'b0;
                w_held <= 1'b0;
                s_axi_bid <= awid_held;
                s_axi_bresp <= write_good ? 2'b00 : 2'b10;
                s_axi_bvalid <= 1'b1;
                if (write_good) begin
                    case (awaddr_held[31:16])
                        I2S_PAGE: case (awaddr_held[15:0])
                            16'h0000: begin
                                i2s_ctrl <= merge_wstrb(i2s_ctrl, wdata_held, wstrb_held) & 32'h1;
                                if (wdata_held[1]) i2s_status <= 0;
                            end
                            16'h0004: i2s_status <= i2s_status & ~wdata_held[2:0];
                            16'h0008: i2s_buf_addr <= merge_wstrb(i2s_buf_addr, wdata_held, wstrb_held);
                            16'h000c: i2s_buf_bytes <= merge_wstrb(i2s_buf_bytes, wdata_held, wstrb_held);
                            16'h0010: i2s_period_bytes <= merge_wstrb(i2s_period_bytes, wdata_held, wstrb_held);
                            default: ;
                        endcase
                        VGA_PAGE: case (awaddr_held[15:0])
                            16'h0000: begin
                                vga_ctrl <= merge_wstrb(vga_ctrl, wdata_held, wstrb_held) & 32'h1;
                                if (wdata_held[1]) vga_status <= 0;
                            end
                            16'h0004: vga_status <= vga_status & ~wdata_held[1:0];
                            16'h0008: vga_fb_addr <= merge_wstrb(vga_fb_addr, wdata_held, wstrb_held);
                            16'h000c: vga_stride <= merge_wstrb(vga_stride, wdata_held, wstrb_held);
                            default: ;
                        endcase
                        PS2_PAGE: begin
                            if (awaddr_held[15:0] == 16'h0000) begin
                                if (!ps2_busy) begin
                                    ps2_tx_data <= wdata_held[7:0];
                                    ps2_send <= 1'b1;
                                end else begin
                                    ps2_status[1] <= 1'b1;
                                end
                            end else if (awaddr_held[15:0] == 16'h0004) begin
                                ps2_status <= ps2_status & ~wdata_held[1:0];
                            end else if (awaddr_held[15:0] == 16'h0008) begin
                                ps2_enable <= wdata_held[0];
                                if (wdata_held[1]) begin
                                    ps2_wr_ptr <= 0; ps2_rd_ptr <= 0; ps2_count <= 0;
                                    ps2_status <= 0;
                                end
                            end else if (awaddr_held[15:0] == 16'hf004) begin
                                irq_enable <= wdata_held[2:0];
                            end else if (awaddr_held[15:0] == 16'hf008) begin
                                irq_enable <= irq_enable | wdata_held[2:0];
                            end else if (awaddr_held[15:0] == 16'hf00c) begin
                                irq_enable <= irq_enable & ~wdata_held[2:0];
                            end
                        end
                        default: ;
                    endcase
                end
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rid <= s_axi_arid;
                s_axi_rdata <= read_good ? register_read(s_axi_araddr) : 0;
                s_axi_rresp <= read_good ? 2'b00 : 2'b10;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // AXI attributes are deliberately accepted but unused by this register
    // block; naming them here keeps lint from mistaking that for an omission.
    wire unused_axi = &{1'b0, s_axi_awburst, s_axi_awlock, s_axi_awcache,
                        s_axi_awprot, s_axi_arburst, s_axi_arlock,
                        s_axi_arcache, s_axi_arprot,
                        vga_stride[0]};
endmodule

`timescale 1ns / 1ps

// AXI3-to-8080 LCD write controller.
//
// Physical address decoding is performed by axi_slave_mux.  This block only
// decodes the low 16-bit register offset:
//   0x00 CTRL   [0] software reset (write-one pulse)
//               [1] LCD reset_n level
//               [2] backlight enable
//   0x04 STATUS [0] FIFO empty, [1] FIFO full, [2] busy,
//               [3] LCD reset_n level, [4] backlight enable,
//               [16:8] FIFO fill level
//   0x08 TIMING [7:0] setup, [15:8] write-low, [23:16] hold cycles
//               A zero timing field is treated as one clock cycle.
//   0x10 CMD     enqueue s_axi_wdata[15:0] with lcd_rs=0
//   0x14 DATA    enqueue s_axi_wdata[15:0] with lcd_rs=1
//   0x18 DMA_ADDR source framebuffer physical address (64-bit aligned)
//   0x1c DMA_LEN  transfer length in bytes; writing starts one transfer
//                 (non-zero and 64-bit aligned)
//   0x20 DMA_STAT [0] busy, [1] done, [2] AXI/configuration error,
//                 [3] interrupt pending.  Any write acknowledges done/IRQ.
//
// A burst beginning at DATA is treated as a stream: every write beat is
// enqueued as LCD data even though an AXI INCR burst conceptually advances the
// address.  This makes the aperture suitable for a future DMA writer.
module lcd_axi_controller #(
    parameter AXI_ID_WIDTH    = 4,
    parameter AXI_ADDR_WIDTH  = 32,
    parameter AXI_DATA_WIDTH  = 32,
    parameter AXI_LEN_WIDTH   = 4,
    parameter FIFO_ADDR_WIDTH = 8
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

    // Read-only AXI master used to fetch RGB565 pixels from DDR.
    output wire [3:0]                   m_axi_arid,
    output wire [31:0]                  m_axi_araddr,
    output wire [3:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire [1:0]                   m_axi_arlock,
    output wire [3:0]                   m_axi_arcache,
    output wire [2:0]                   m_axi_arprot,
    output wire                         m_axi_arvalid,
    input  wire                         m_axi_arready,
    input  wire [3:0]                   m_axi_rid,
    input  wire [63:0]                  m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready,

    output wire                         dma_irq,

    output wire                         lcd_cs_n,
    output wire                         lcd_wr_n,
    output wire                         lcd_rd_n,
    output wire                         lcd_rs,
    output wire                         lcd_rst_n,
    inout  wire [15:0]                  lcd_db,
    output wire                         lcd_bl_ctr
);

    localparam [15:0] ADDR_CTRL   = 16'h0000;
    localparam [15:0] ADDR_STATUS = 16'h0004;
    localparam [15:0] ADDR_TIMING = 16'h0008;
    localparam [15:0] ADDR_CMD    = 16'h0010;
    localparam [15:0] ADDR_DATA   = 16'h0014;
    localparam [15:0] ADDR_DMA_ADDR = 16'h0018;
    localparam [15:0] ADDR_DMA_LEN  = 16'h001c;
    localparam [15:0] ADDR_DMA_STAT = 16'h0020;

    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam [1:0] AXI_BURST_FIXED = 2'b00;
    localparam [1:0] AXI_BURST_INCR  = 2'b01;

    reg [31:0] ctrl_reg;
    reg [31:0] timing_reg;
    reg        soft_reset_pulse;
    reg [31:0] dma_addr_reg;
    reg [31:0] dma_length_reg;
    reg        dma_start_pulse;
    reg        dma_ack_pulse;

    wire       dma_busy;
    wire       dma_done;
    wire       dma_error;
    wire       dma_pixel_valid;
    wire       dma_pixel_ready;
    wire [15:0] dma_pixel_data;
    // An accepted AXI burst cannot be cancelled.  Ignore the software FIFO
    // reset while DMA is active; the system reset still resets both sides.
    wire       lcd_soft_reset_pulse = soft_reset_pulse && !dma_busy;

    wire [16:0] fifo_din;
    wire [16:0] fifo_dout;
    wire        fifo_wr_en;
    wire        cpu_fifo_wr_en;
    wire        dma_fifo_wr_en;
    wire        fifo_rd_en;
    wire        fifo_full;
    wire        fifo_empty;
    wire [FIFO_ADDR_WIDTH:0] fifo_count;

    // ------------------------------------------------------------------
    // AXI write channel
    // ------------------------------------------------------------------
    localparam [1:0] W_IDLE = 2'd0;
    localparam [1:0] W_DATA = 2'd1;
    localparam [1:0] W_RESP = 2'd2;

    reg [1:0]                  wr_state;
    reg [AXI_ID_WIDTH-1:0]     wr_id;
    reg [AXI_ADDR_WIDTH-1:0]   wr_addr;
    reg [AXI_LEN_WIDTH:0]      wr_beats_left;
    reg [2:0]                  wr_size;
    reg [1:0]                  wr_burst;
    reg                        wr_stream_data;
    reg [1:0]                  wr_resp;

    wire [15:0] wr_offset = wr_stream_data ? ADDR_DATA : wr_addr[15:0];
    wire wr_fifo_target = (wr_offset == ADDR_CMD) || (wr_offset == ADDR_DATA);
    wire wr_protocol_ok = (wr_size == 3'b010) &&
                          ((wr_burst == AXI_BURST_FIXED) ||
                           (wr_burst == AXI_BURST_INCR)) &&
                          (s_axi_wid == wr_id);
    wire wr_beat = s_axi_wvalid && s_axi_wready;
    wire wr_expected_last = (wr_beats_left == {{AXI_LEN_WIDTH{1'b0}}, 1'b1});

    assign s_axi_awready = (wr_state == W_IDLE);
    assign s_axi_wready  = (wr_state == W_DATA) &&
                           (!wr_fifo_target || (!fifo_full && !dma_busy));
    assign s_axi_bid     = wr_id;
    assign s_axi_bresp   = wr_resp;
    assign s_axi_bvalid  = (wr_state == W_RESP);

    assign cpu_fifo_wr_en = wr_beat && wr_protocol_ok && wr_fifo_target &&
                            (&s_axi_wstrb[1:0]);
    assign dma_fifo_wr_en = dma_pixel_valid && dma_pixel_ready;
    assign fifo_wr_en = cpu_fifo_wr_en || dma_fifo_wr_en;
    assign fifo_din = dma_fifo_wr_en ? {1'b1, dma_pixel_data} :
                                      {(wr_offset == ADDR_DATA),
                                       s_axi_wdata[15:0]};
    assign dma_pixel_ready = !fifo_full;

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strb;
        integer byte_index;
        begin
            apply_wstrb = old_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                if (strb[byte_index])
                    apply_wstrb[byte_index*8 +: 8] =
                        new_value[byte_index*8 +: 8];
        end
    endfunction

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wr_state         <= W_IDLE;
            wr_id            <= {AXI_ID_WIDTH{1'b0}};
            wr_addr          <= {AXI_ADDR_WIDTH{1'b0}};
            wr_beats_left    <= {(AXI_LEN_WIDTH+1){1'b0}};
            wr_size          <= 3'b010;
            wr_burst         <= AXI_BURST_INCR;
            wr_stream_data   <= 1'b0;
            wr_resp          <= AXI_RESP_OKAY;
            ctrl_reg         <= 32'h0000_0000;
            timing_reg       <= 32'h0001_0101;
            soft_reset_pulse <= 1'b0;
            dma_addr_reg     <= 32'h0000_0000;
            dma_length_reg   <= 32'h0000_0000;
            dma_start_pulse  <= 1'b0;
            dma_ack_pulse    <= 1'b0;
        end else begin
            soft_reset_pulse <= 1'b0;
            dma_start_pulse  <= 1'b0;
            dma_ack_pulse    <= 1'b0;

            case (wr_state)
                W_IDLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id          <= s_axi_awid;
                        wr_addr        <= s_axi_awaddr;
                        wr_beats_left  <= {1'b0, s_axi_awlen} + 1'b1;
                        wr_size        <= s_axi_awsize;
                        wr_burst       <= s_axi_awburst;
                        wr_stream_data <= (s_axi_awaddr[15:0] == ADDR_DATA) &&
                                          (s_axi_awlen != {AXI_LEN_WIDTH{1'b0}});
                        wr_resp        <= ((s_axi_awsize == 3'b010) &&
                                           ((s_axi_awburst == AXI_BURST_FIXED) ||
                                            (s_axi_awburst == AXI_BURST_INCR))) ?
                                          AXI_RESP_OKAY : AXI_RESP_SLVERR;
                        wr_state       <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (wr_beat) begin
                        if (!wr_protocol_ok ||
                            (s_axi_wlast != wr_expected_last) ||
                            ((wr_fifo_target) && !(&s_axi_wstrb[1:0])) ||
                            ((wr_offset != ADDR_CTRL) &&
                             (wr_offset != ADDR_TIMING) &&
                             (wr_offset != ADDR_CMD) &&
                             (wr_offset != ADDR_DATA) &&
                             (wr_offset != ADDR_DMA_ADDR) &&
                             (wr_offset != ADDR_DMA_LEN) &&
                             (wr_offset != ADDR_DMA_STAT)))
                            wr_resp <= AXI_RESP_SLVERR;

                        if (wr_protocol_ok) begin
                            case (wr_offset)
                                ADDR_CTRL: begin
                                    ctrl_reg <= apply_wstrb(ctrl_reg,
                                                            s_axi_wdata,
                                                            s_axi_wstrb) &
                                                32'hffff_fffe;
                                    if (s_axi_wstrb[0] && s_axi_wdata[0])
                                        soft_reset_pulse <= 1'b1;
                                end
                                ADDR_TIMING:
                                    timing_reg <= apply_wstrb(timing_reg,
                                                              s_axi_wdata,
                                                              s_axi_wstrb);
                                ADDR_DMA_ADDR:
                                    dma_addr_reg <= apply_wstrb(dma_addr_reg,
                                                                s_axi_wdata,
                                                                s_axi_wstrb);
                                ADDR_DMA_LEN: begin
                                    dma_length_reg <=
                                        apply_wstrb(dma_length_reg,
                                                    s_axi_wdata,
                                                    s_axi_wstrb);
                                    dma_start_pulse <= 1'b1;
                                end
                                ADDR_DMA_STAT:
                                    dma_ack_pulse <= 1'b1;
                                default: begin
                                end
                            endcase
                        end

                        if (!wr_stream_data && (wr_burst == AXI_BURST_INCR))
                            wr_addr <= wr_addr + 32'd4;

                        if (wr_expected_last || s_axi_wlast) begin
                            wr_beats_left <= {(AXI_LEN_WIDTH+1){1'b0}};
                            wr_state      <= W_RESP;
                        end else begin
                            wr_beats_left <= wr_beats_left - 1'b1;
                        end
                    end
                end

                W_RESP: begin
                    if (s_axi_bready && s_axi_bvalid)
                        wr_state <= W_IDLE;
                end

                default:
                    wr_state <= W_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // AXI read channel.  Reads are completed even for unsupported offsets
    // so that an accidental access cannot stall the CPU indefinitely.
    // ------------------------------------------------------------------
    reg                         rd_active;
    reg [AXI_ID_WIDTH-1:0]      rd_id;
    reg [AXI_ADDR_WIDTH-1:0]    rd_addr;
    reg [AXI_LEN_WIDTH:0]       rd_beats_left;
    reg [1:0]                   rd_burst;
    reg                         rd_protocol_ok;
    reg [AXI_DATA_WIDTH-1:0]    rd_data;
    reg [1:0]                   rd_resp;

    wire lcd_busy;
    wire [31:0] dma_status_word = {28'b0, dma_irq, dma_error,
                                   dma_done, dma_busy};
    wire [31:0] status_word = {
        15'b0,
        fifo_count[8:0],
        2'b0,
        dma_busy,
        ctrl_reg[2],
        ctrl_reg[1],
        lcd_busy,
        fifo_full,
        fifo_empty
    };

    function readable_offset;
        input [15:0] address;
        begin
            case (address)
                ADDR_CTRL,
                ADDR_STATUS,
                ADDR_TIMING,
                ADDR_DMA_ADDR,
                ADDR_DMA_LEN,
                ADDR_DMA_STAT: readable_offset = 1'b1;
                default:     readable_offset = 1'b0;
            endcase
        end
    endfunction

    function [31:0] read_register;
        input [15:0] address;
        begin
            case (address)
                ADDR_CTRL:   read_register = ctrl_reg;
                ADDR_STATUS: read_register = status_word;
                ADDR_TIMING: read_register = timing_reg;
                ADDR_DMA_ADDR: read_register = dma_addr_reg;
                ADDR_DMA_LEN:  read_register = dma_length_reg;
                ADDR_DMA_STAT: read_register = dma_status_word;
                default:     read_register = 32'h0000_0000;
            endcase
        end
    endfunction

    wire [AXI_ADDR_WIDTH-1:0] rd_next_addr =
        (rd_burst == AXI_BURST_INCR) ? (rd_addr + 32'd4) : rd_addr;

    assign s_axi_arready = !rd_active;
    assign s_axi_rid     = rd_id;
    assign s_axi_rdata   = rd_data;
    assign s_axi_rresp   = rd_resp;
    assign s_axi_rlast   = rd_active &&
                           (rd_beats_left == {{AXI_LEN_WIDTH{1'b0}}, 1'b1});
    assign s_axi_rvalid  = rd_active;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            rd_active     <= 1'b0;
            rd_id         <= {AXI_ID_WIDTH{1'b0}};
            rd_addr       <= {AXI_ADDR_WIDTH{1'b0}};
            rd_beats_left <= {(AXI_LEN_WIDTH+1){1'b0}};
            rd_burst      <= AXI_BURST_INCR;
            rd_protocol_ok <= 1'b0;
            rd_data       <= {AXI_DATA_WIDTH{1'b0}};
            rd_resp       <= AXI_RESP_OKAY;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                rd_active     <= 1'b1;
                rd_id         <= s_axi_arid;
                rd_addr       <= s_axi_araddr;
                rd_beats_left <= {1'b0, s_axi_arlen} + 1'b1;
                rd_burst      <= s_axi_arburst;
                rd_protocol_ok <= (s_axi_arsize == 3'b010) &&
                                  ((s_axi_arburst == AXI_BURST_FIXED) ||
                                   (s_axi_arburst == AXI_BURST_INCR));
                rd_data       <= read_register(s_axi_araddr[15:0]);
                rd_resp       <= ((s_axi_arsize == 3'b010) &&
                                  ((s_axi_arburst == AXI_BURST_FIXED) ||
                                   (s_axi_arburst == AXI_BURST_INCR)) &&
                                  readable_offset(s_axi_araddr[15:0])) ?
                                 AXI_RESP_OKAY : AXI_RESP_SLVERR;
            end else if (s_axi_rvalid && s_axi_rready) begin
                if (s_axi_rlast) begin
                    rd_active <= 1'b0;
                end else begin
                    rd_addr       <= rd_next_addr;
                    rd_beats_left <= rd_beats_left - 1'b1;
                    rd_data       <= read_register(rd_next_addr[15:0]);
                    rd_resp       <= (rd_protocol_ok &&
                                      readable_offset(rd_next_addr[15:0])) ?
                                     AXI_RESP_OKAY : AXI_RESP_SLVERR;
                end
            end
        end
    end

    // Unused AXI attributes are intentionally accepted for compatibility
    // with the SoC's AXI3 fabric.
    wire unused_axi_attributes = ^{s_axi_awlock, s_axi_awcache, s_axi_awprot,
                                   s_axi_arlock, s_axi_arcache, s_axi_arprot};

    // ------------------------------------------------------------------
    // Framebuffer DMA reader.  It deliberately has only an AXI read
    // channel: pixels are fetched from DDR in 16-beat bursts and serialized
    // into the existing LCD command FIFO as RGB565 DATA entries.
    // ------------------------------------------------------------------
    lcd_dma_reader u_dma_reader (
        .clk          (s_axi_aclk),
        .resetn       (s_axi_aresetn),
        .clear        (lcd_soft_reset_pulse),
        .start        (dma_start_pulse),
        .ack          (dma_ack_pulse),
        .base_addr    (dma_addr_reg),
        .byte_length  (dma_length_reg),
        .busy         (dma_busy),
        .done         (dma_done),
        .error        (dma_error),
        .irq          (dma_irq),
        .pixel_valid  (dma_pixel_valid),
        .pixel_ready  (dma_pixel_ready),
        .pixel_data   (dma_pixel_data),
        .m_axi_arid   (m_axi_arid),
        .m_axi_araddr (m_axi_araddr),
        .m_axi_arlen  (m_axi_arlen),
        .m_axi_arsize (m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock (m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot (m_axi_arprot),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid    (m_axi_rid),
        .m_axi_rdata  (m_axi_rdata),
        .m_axi_rresp  (m_axi_rresp),
        .m_axi_rlast  (m_axi_rlast),
        .m_axi_rvalid (m_axi_rvalid),
        .m_axi_rready (m_axi_rready)
    );

    // ------------------------------------------------------------------
    // LCD command FIFO
    // ------------------------------------------------------------------
    lcd_sync_fifo #(
        .DATA_WIDTH(17),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_command_fifo (
        .clk   (s_axi_aclk),
        .resetn(s_axi_aresetn),
        .clear (lcd_soft_reset_pulse),
        .wr_en (fifo_wr_en),
        .din   (fifo_din),
        .rd_en (fifo_rd_en),
        .dout  (fifo_dout),
        .full  (fifo_full),
        .empty (fifo_empty),
        .count (fifo_count)
    );

    // ------------------------------------------------------------------
    // 16-bit Intel/8080-style write engine
    // ------------------------------------------------------------------
    localparam [2:0] LCD_IDLE   = 3'd0;
    localparam [2:0] LCD_SETUP  = 3'd1;
    localparam [2:0] LCD_PULSE  = 3'd2;
    localparam [2:0] LCD_HOLD   = 3'd3;
    localparam [2:0] LCD_FINISH = 3'd4;

    reg [2:0]  lcd_state;
    reg [7:0]  lcd_timer;
    reg        lcd_cs_n_reg;
    reg        lcd_wr_n_reg;
    reg        lcd_rs_reg;
    reg [15:0] lcd_db_reg;
    reg        lcd_db_oe;

    wire [7:0] setup_cycles = (timing_reg[7:0]   == 8'd0) ?
                              8'd1 : timing_reg[7:0];
    wire [7:0] pulse_cycles = (timing_reg[15:8]  == 8'd0) ?
                              8'd1 : timing_reg[15:8];
    wire [7:0] hold_cycles  = (timing_reg[23:16] == 8'd0) ?
                              8'd1 : timing_reg[23:16];

    assign fifo_rd_en = (lcd_state == LCD_IDLE) && !fifo_empty &&
                        !lcd_soft_reset_pulse;
    assign lcd_busy = (lcd_state != LCD_IDLE) || !fifo_empty;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn || lcd_soft_reset_pulse) begin
            lcd_state    <= LCD_IDLE;
            lcd_timer    <= 8'd0;
            lcd_cs_n_reg <= 1'b1;
            lcd_wr_n_reg <= 1'b1;
            lcd_rs_reg   <= 1'b0;
            lcd_db_reg   <= 16'h0000;
            lcd_db_oe    <= 1'b0;
        end else begin
            case (lcd_state)
                LCD_IDLE: begin
                    lcd_cs_n_reg <= 1'b1;
                    lcd_wr_n_reg <= 1'b1;
                    lcd_db_oe    <= 1'b0;
                    lcd_timer    <= 8'd0;
                    if (!fifo_empty) begin
                        lcd_db_reg   <= fifo_dout[15:0];
                        lcd_rs_reg   <= fifo_dout[16];
                        lcd_cs_n_reg <= 1'b0;
                        lcd_db_oe    <= 1'b1;
                        lcd_state    <= LCD_SETUP;
                    end
                end

                LCD_SETUP: begin
                    if (lcd_timer + 1'b1 >= setup_cycles) begin
                        lcd_timer    <= 8'd0;
                        lcd_wr_n_reg <= 1'b0;
                        lcd_state    <= LCD_PULSE;
                    end else begin
                        lcd_timer <= lcd_timer + 1'b1;
                    end
                end

                LCD_PULSE: begin
                    if (lcd_timer + 1'b1 >= pulse_cycles) begin
                        lcd_timer    <= 8'd0;
                        lcd_wr_n_reg <= 1'b1;
                        lcd_state    <= LCD_HOLD;
                    end else begin
                        lcd_timer <= lcd_timer + 1'b1;
                    end
                end

                LCD_HOLD: begin
                    if (lcd_timer + 1'b1 >= hold_cycles) begin
                        lcd_timer <= 8'd0;
                        lcd_state <= LCD_FINISH;
                    end else begin
                        lcd_timer <= lcd_timer + 1'b1;
                    end
                end

                LCD_FINISH: begin
                    lcd_cs_n_reg <= 1'b1;
                    lcd_db_oe    <= 1'b0;
                    lcd_state    <= LCD_IDLE;
                end

                default:
                    lcd_state <= LCD_IDLE;
            endcase
        end
    end

    assign lcd_cs_n   = lcd_cs_n_reg;
    assign lcd_wr_n   = lcd_wr_n_reg;
    assign lcd_rd_n   = 1'b1;
    assign lcd_rs     = lcd_rs_reg;
    assign lcd_rst_n  = ctrl_reg[1];
    assign lcd_bl_ctr = ctrl_reg[2];
    assign lcd_db     = lcd_db_oe ? lcd_db_reg : 16'hzzzz;

endmodule


// Read-only AXI3 framebuffer engine.  At most one burst is outstanding.  A
// 64-bit read beat is converted to four low-byte-first RGB565 pixels, matching
// the little-endian framebuffer layout used by Linux fbdev.
module lcd_dma_reader (
    input  wire        clk,
    input  wire        resetn,
    input  wire        clear,
    input  wire        start,
    input  wire        ack,
    input  wire [31:0] base_addr,
    input  wire [31:0] byte_length,
    output reg         busy,
    output reg         done,
    output reg         error,
    output reg         irq,

    output wire        pixel_valid,
    input  wire        pixel_ready,
    output wire [15:0] pixel_data,

    output wire [3:0]  m_axi_arid,
    output wire [31:0] m_axi_araddr,
    output wire [3:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire [1:0]  m_axi_arlock,
    output wire [3:0]  m_axi_arcache,
    output wire [2:0]  m_axi_arprot,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [3:0]  m_axi_rid,
    input  wire [63:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready
);

    localparam [3:0] DMA_AXI_ID = 4'h3;

    reg [31:0] next_addr;
    reg [31:0] words_unrequested;
    reg        arvalid_reg;
    reg [31:0] araddr_reg;
    reg [4:0]  planned_beats;
    reg        burst_active;
    reg [4:0]  response_beats_left;
    reg        read_complete;

    reg [63:0] word_data;
    reg        word_valid;
    reg [1:0]  word_pixel_index;

    wire pixel_take = pixel_valid && pixel_ready;
    wire read_take = m_axi_rvalid && m_axi_rready;
    wire expected_last = response_beats_left == 5'd1;

    // Limit every burst to 16 words and prevent a burst from crossing a 4 KiB
    // AXI boundary.  The start address itself is required to be word aligned.
    function [4:0] choose_burst_words;
        input [31:0] words_left;
        input [8:0] address_word;
        reg [9:0] boundary_words;
        begin
            boundary_words = 10'd512 - {1'b0, address_word};
            if (words_left < 32'd16)
                choose_burst_words = words_left[4:0];
            else if (boundary_words < 10'd16)
                choose_burst_words = boundary_words[4:0];
            else
                choose_burst_words = 5'd16;
        end
    endfunction

    assign pixel_valid = word_valid;
    assign pixel_data = (word_pixel_index == 2'd0) ? word_data[15:0]  :
                        (word_pixel_index == 2'd1) ? word_data[31:16] :
                        (word_pixel_index == 2'd2) ? word_data[47:32] :
                                                    word_data[63:48];

    assign m_axi_arid    = DMA_AXI_ID;
    assign m_axi_araddr  = araddr_reg;
    assign m_axi_arlen   = planned_beats[3:0] - 1'b1;
    assign m_axi_arsize  = 3'b011;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 2'b00;
    assign m_axi_arcache = 4'b0000;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arvalid = arvalid_reg;
    assign m_axi_rready  = busy && burst_active && !word_valid;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            busy                 <= 1'b0;
            done                 <= 1'b0;
            error                <= 1'b0;
            irq                  <= 1'b0;
            next_addr            <= 32'b0;
            words_unrequested    <= 32'b0;
            arvalid_reg          <= 1'b0;
            araddr_reg           <= 32'b0;
            planned_beats        <= 5'b0;
            burst_active         <= 1'b0;
            response_beats_left  <= 5'b0;
            read_complete        <= 1'b0;
            word_data            <= 64'b0;
            word_valid           <= 1'b0;
            word_pixel_index     <= 2'b0;
        end else if (clear) begin
            busy                 <= 1'b0;
            done                 <= 1'b0;
            error                <= 1'b0;
            irq                  <= 1'b0;
            words_unrequested    <= 32'b0;
            arvalid_reg          <= 1'b0;
            planned_beats        <= 5'b0;
            burst_active         <= 1'b0;
            response_beats_left  <= 5'b0;
            read_complete        <= 1'b0;
            word_valid           <= 1'b0;
            word_pixel_index     <= 2'b0;
        end else begin
            if (ack) begin
                done  <= 1'b0;
                error <= 1'b0;
                irq   <= 1'b0;
            end

            if (start && !busy) begin
                done                <= 1'b0;
                error               <= 1'b0;
                irq                 <= 1'b0;
                arvalid_reg         <= 1'b0;
                burst_active        <= 1'b0;
                response_beats_left <= 5'b0;
                read_complete       <= 1'b0;
                word_valid          <= 1'b0;
                word_pixel_index    <= 2'b0;

                if ((base_addr[2:0] != 3'b000) ||
                    (byte_length == 32'b0) ||
                    (byte_length[2:0] != 3'b000)) begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    error <= 1'b1;
                    irq   <= 1'b1;
                    words_unrequested <= 32'b0;
                end else begin
                    busy              <= 1'b1;
                    next_addr         <= base_addr;
                    words_unrequested <= byte_length >> 3;
                end
            end else if (busy) begin
                if (!arvalid_reg && !burst_active && !read_complete &&
                    (words_unrequested != 32'b0)) begin
                    araddr_reg    <= next_addr;
                    planned_beats <= choose_burst_words(words_unrequested,
                                                         next_addr[11:3]);
                    arvalid_reg   <= 1'b1;
                end

                if (arvalid_reg && m_axi_arready) begin
                    arvalid_reg         <= 1'b0;
                    burst_active        <= 1'b1;
                    response_beats_left <= planned_beats;
                    next_addr           <= next_addr +
                                           {24'b0, planned_beats, 3'b000};
                    words_unrequested   <= words_unrequested -
                                           {27'b0, planned_beats};
                end

                if (read_take) begin
                    word_data      <= m_axi_rdata;
                    word_valid     <= 1'b1;
                    word_pixel_index <= 2'b0;

                    if ((m_axi_rresp != 2'b00) ||
                        (m_axi_rid != DMA_AXI_ID))
                        error <= 1'b1;

                    if (expected_last) begin
                        burst_active        <= 1'b0;
                        response_beats_left <= 5'b0;
                        if (!m_axi_rlast)
                            error <= 1'b1;
                        if (words_unrequested == 32'b0)
                            read_complete <= 1'b1;
                    end else begin
                        response_beats_left <= response_beats_left - 1'b1;
                        if (m_axi_rlast) begin
                            // An early RLAST makes the remaining transfer
                            // unrecoverable; drain the word already received
                            // and complete with the error flag set.
                            error                <= 1'b1;
                            burst_active         <= 1'b0;
                            response_beats_left  <= 5'b0;
                            words_unrequested    <= 32'b0;
                            read_complete        <= 1'b1;
                            arvalid_reg          <= 1'b0;
                        end
                    end
                end

                if (pixel_take) begin
                    if (word_pixel_index != 2'd3) begin
                        word_pixel_index <= word_pixel_index + 1'b1;
                    end else begin
                        word_valid     <= 1'b0;
                        word_pixel_index <= 2'b0;
                        if (read_complete) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            irq  <= 1'b1;
                        end
                    end
                end
            end
        end
    end

endmodule


// Small show-ahead synchronous FIFO.  It replaces the reference design's
// generated FIFO IP so that the LCD block remains self-contained.
module lcd_sync_fifo #(
    parameter DATA_WIDTH = 17,
    parameter ADDR_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  resetn,
    input  wire                  clear,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] dout,
    output wire                  full,
    output wire                  empty,
    output reg  [ADDR_WIDTH:0]   count
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] write_pointer;
    reg [ADDR_WIDTH-1:0] read_pointer;

    wire write_do = wr_en && !full;
    wire read_do  = rd_en && !empty;

    assign full  = count == DEPTH;
    assign empty = count == 0;
    assign dout  = memory[read_pointer];

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            write_pointer <= {ADDR_WIDTH{1'b0}};
            read_pointer  <= {ADDR_WIDTH{1'b0}};
            count         <= {(ADDR_WIDTH+1){1'b0}};
        end else if (clear) begin
            write_pointer <= {ADDR_WIDTH{1'b0}};
            read_pointer  <= {ADDR_WIDTH{1'b0}};
            count         <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            if (write_do) begin
                memory[write_pointer] <= din;
                write_pointer <= write_pointer + 1'b1;
            end

            if (read_do)
                read_pointer <= read_pointer + 1'b1;

            case ({write_do, read_do})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule

`timescale 1ns / 1ps

// 640x480@60 RGB565 scanout.  The AXI-side DMA supplies four pixels in each
// 64-bit word.  Timing is based on Project F's MIT-licensed display_timings.
module avp_vga (
    input  wire        bus_clk,
    input  wire        bus_resetn,
    input  wire        pix_clk,
    input  wire        pix_locked,
    input  wire        enable,

    input  wire [63:0] stream_data,
    input  wire        stream_valid,
    output wire        stream_ready,

    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         vga_hsync,
    output reg         vga_vsync,
    output reg         underflow_event
);
    // The AXI reset and MMCM lock indication are asynchronous to pix_clk.
    // Assert reset immediately, but release it only after two pixel clocks so
    // the raster registers never see an asynchronous recovery/removal edge.
    wire pix_async_resetn = bus_resetn && pix_locked;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [1:0] pix_reset_sync;
    always @(posedge pix_clk or negedge pix_async_resetn) begin
        if (!pix_async_resetn)
            pix_reset_sync <= 2'b00;
        else
            pix_reset_sync <= {pix_reset_sync[0], 1'b1};
    end
    wire pix_resetn = pix_reset_sync[1];

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] enable_sync;
    always @(posedge pix_clk) begin
        if (!pix_resetn)
            enable_sync <= 2'b00;
        else
            enable_sync <= {enable_sync[0], enable};
    end

    wire fifo_reset = !bus_resetn || !enable;
    wire fifo_full;
    wire fifo_empty;
    wire [63:0] fifo_dout;
    reg fifo_rd;

    assign stream_ready = enable && !fifo_full;
    avp_async_fifo #(.DATA_WIDTH(64), .DEPTH(512)) u_vga_fifo (
        .rst(fifo_reset),
        .wr_clk(bus_clk), .din(stream_data),
        .wr_en(stream_valid && stream_ready), .full(fifo_full),
        .rd_clk(pix_clk), .dout(fifo_dout), .rd_en(fifo_rd),
        .empty(fifo_empty)
    );

    // Give the DMA time to prefill the FIFO before releasing the raster.
    reg [10:0] startup_count;
    wire timing_reset = !pix_resetn || !enable_sync[1] ||
                        (startup_count != 11'h7ff);
    always @(posedge pix_clk) begin
        if (!pix_resetn || !enable_sync[1])
            startup_count <= 0;
        else if (startup_count != 11'h7ff)
            startup_count <= startup_count + 1'b1;
    end

    wire timing_hs;
    wire timing_vs;
    wire timing_de;
    display_timings u_timings (
        .i_pix_clk(pix_clk), .i_rst(timing_reset),
        .o_hs(timing_hs), .o_vs(timing_vs), .o_de(timing_de),
        .o_frame(), .o_sx(), .o_sy()
    );

    reg [47:0] pixel_tail;
    reg [1:0] pixel_lane;
    reg word_valid;
    reg underflow_active;
    reg underflow_toggle;

    always @(posedge pix_clk) begin
        if (!pix_resetn) begin
            fifo_rd <= 1'b0;
            pixel_tail <= 0;
            pixel_lane <= 0;
            word_valid <= 1'b0;
            underflow_active <= 1'b0;
            underflow_toggle <= 1'b0;
            vga_r <= 0; vga_g <= 0; vga_b <= 0;
            vga_hsync <= 1'b1; vga_vsync <= 1'b1;
        end else begin
            fifo_rd <= 1'b0;
            vga_hsync <= timing_hs;
            vga_vsync <= timing_vs;

            if (timing_reset) begin
                pixel_lane <= 0;
                word_valid <= 1'b0;
                underflow_active <= 1'b0;
                vga_r <= 0; vga_g <= 0; vga_b <= 0;
            end else if (timing_de) begin
                if (!word_valid) begin
                    if (!fifo_empty) begin
                        pixel_tail <= fifo_dout[63:16];
                        fifo_rd <= 1'b1;
                        pixel_lane <= 2'd1;
                        word_valid <= 1'b1;
                        underflow_active <= 1'b0;
                        vga_r <= fifo_dout[15:12];
                        vga_g <= fifo_dout[10:7];
                        vga_b <= fifo_dout[4:1];
                    end else begin
                        vga_r <= 0; vga_g <= 0; vga_b <= 0;
                        if (!underflow_active)
                            underflow_toggle <= ~underflow_toggle;
                        underflow_active <= 1'b1;
                    end
                end else begin
                    case (pixel_lane)
                        2'd1: begin
                            vga_r <= pixel_tail[15:12];
                            vga_g <= pixel_tail[10:7];
                            vga_b <= pixel_tail[4:1];
                        end
                        2'd2: begin
                            vga_r <= pixel_tail[31:28];
                            vga_g <= pixel_tail[26:23];
                            vga_b <= pixel_tail[20:17];
                        end
                        default: begin
                            vga_r <= pixel_tail[47:44];
                            vga_g <= pixel_tail[42:39];
                            vga_b <= pixel_tail[36:33];
                        end
                    endcase
                    if (pixel_lane == 2'd3) begin
                        word_valid <= 1'b0;
                        pixel_lane <= 0;
                    end else begin
                        pixel_lane <= pixel_lane + 1'b1;
                    end
                    underflow_active <= 1'b0;
                end
            end else begin
                vga_r <= 0; vga_g <= 0; vga_b <= 0;
                underflow_active <= 1'b0;
            end
        end
    end

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [2:0] underflow_sync;
    always @(posedge bus_clk or negedge bus_resetn) begin
        if (!bus_resetn) begin
            underflow_sync <= 0;
            underflow_event <= 1'b0;
        end else begin
            underflow_sync <= {underflow_sync[1:0], underflow_toggle};
            underflow_event <= underflow_sync[2] ^ underflow_sync[1];
        end
    end
endmodule

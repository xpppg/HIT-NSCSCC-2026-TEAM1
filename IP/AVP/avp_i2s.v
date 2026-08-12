`timescale 1ns / 1ps

// Fixed-format 44.1 kHz, stereo, signed 16-bit I2S transmitter.  aud_clk is
// 22.5792 MHz: BCLK is aud_clk/16 and LRCLK is BCLK/32.
module avp_i2s (
    input  wire        bus_clk,
    input  wire        bus_resetn,
    input  wire        aud_clk,
    input  wire        aud_locked,
    input  wire        enable,
    input  wire [31:0] buffer_bytes,
    input  wire [31:0] period_bytes,

    input  wire [63:0] stream_data,
    input  wire        stream_valid,
    output wire        stream_ready,

    output reg  [31:0] play_pos,
    output reg         period_event,
    output reg         underflow_event,
    output wire        i2s_bclk,
    output reg         i2s_lrclk,
    output reg         i2s_data
);
    // The AXI reset and MMCM lock indication are asynchronous to aud_clk.
    // Assert reset immediately, then release it synchronously in this domain.
    wire aud_async_resetn = bus_resetn && aud_locked;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [1:0] aud_reset_sync;
    always @(posedge aud_clk or negedge aud_async_resetn) begin
        if (!aud_async_resetn)
            aud_reset_sync <= 2'b00;
        else
            aud_reset_sync <= {aud_reset_sync[0], 1'b1};
    end
    wire aud_resetn = aud_reset_sync[1];

    wire fifo_reset = !bus_resetn || !enable;
    wire fifo_full;
    wire fifo_empty;
    wire [63:0] fifo_dout;
    reg fifo_rd;
    assign stream_ready = enable && !fifo_full;

    avp_async_fifo #(.DATA_WIDTH(64), .DEPTH(512)) u_i2s_fifo (
        .rst(fifo_reset),
        .wr_clk(bus_clk), .din(stream_data),
        .wr_en(stream_valid && stream_ready), .full(fifo_full),
        .rd_clk(aud_clk), .dout(fifo_dout), .rd_en(fifo_rd),
        .empty(fifo_empty)
    );

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] enable_sync;
    reg [31:0] buffer_bytes_a;
    reg [31:0] period_bytes_a;
    always @(posedge aud_clk) begin
        if (!aud_resetn) begin
            enable_sync <= 0;
            buffer_bytes_a <= 0;
            period_bytes_a <= 0;
        end else begin
            enable_sync <= {enable_sync[0], enable};
            if (!enable_sync[1]) begin
                buffer_bytes_a <= buffer_bytes;
                period_bytes_a <= period_bytes;
            end
        end
    end

    reg [3:0] clock_div;
    reg [10:0] startup_count;
    wire audio_active = enable_sync[1] && aud_resetn &&
                        startup_count == 11'h7ff;
    assign i2s_bclk = audio_active ? clock_div[3] : 1'b0;
    wire bclk_falling = clock_div == 4'hf;

    always @(posedge aud_clk) begin
        if (!aud_resetn || !enable_sync[1])
            startup_count <= 0;
        else if (startup_count != 11'h7ff)
            startup_count <= startup_count + 1'b1;
    end

    reg [63:0] sample_word;
    reg sample_word_valid;
    reg sample_half;
    reg [31:0] sample_frame;
    reg sample_valid;
    reg [5:0] serial_bit;
    reg [31:0] play_pos_a;
    reg [31:0] period_pos_a;
    reg period_toggle;
    reg underflow_toggle;
    reg underflow_active;

    always @(posedge aud_clk) begin
        if (!aud_resetn) begin
            fifo_rd <= 0;
            clock_div <= 0;
            sample_word <= 0;
            sample_word_valid <= 0;
            sample_half <= 0;
            sample_frame <= 0;
            sample_valid <= 0;
            serial_bit <= 0;
            play_pos_a <= 0;
            period_pos_a <= 0;
            period_toggle <= 0;
            underflow_toggle <= 0;
            underflow_active <= 0;
            i2s_lrclk <= 0;
            i2s_data <= 0;
        end else begin
            fifo_rd <= 1'b0;
            if (!audio_active) begin
                clock_div <= 0;
                sample_word_valid <= 0;
                sample_half <= 0;
                sample_valid <= 0;
                serial_bit <= 0;
                play_pos_a <= 0;
                period_pos_a <= 0;
                underflow_active <= 0;
                i2s_lrclk <= 0;
                i2s_data <= 0;
            end else begin
                clock_div <= clock_div + 1'b1;

                // Keep one 64-bit word locally so AXI jitter is absorbed by
                // the asynchronous FIFO instead of propagating to BCLK.
                if (!sample_word_valid && !fifo_empty) begin
                    sample_word <= fifo_dout;
                    sample_word_valid <= 1'b1;
                    sample_half <= 1'b0;
                    fifo_rd <= 1'b1;
                end

                if (bclk_falling) begin
                    // Standard I2S: LRCLK changes one bit clock before the
                    // next channel's MSB.  Left is low, right is high.
                    i2s_lrclk <= (serial_bit >= 6'd15 && serial_bit < 6'd31);
                    if (sample_valid) begin
                        if (serial_bit < 16)
                            i2s_data <= sample_frame[15-serial_bit];
                        else
                            i2s_data <= sample_frame[47-serial_bit];
                    end else begin
                        i2s_data <= 1'b0;
                    end

                    if (serial_bit == 6'd31) begin
                        serial_bit <= 0;
                        if (sample_valid) begin
                            play_pos_a <= (play_pos_a + 4 >= buffer_bytes_a) ?
                                          0 : play_pos_a + 4;
                            if (period_bytes_a != 0) begin
                                if (period_pos_a + 4 >= period_bytes_a) begin
                                    period_pos_a <= 0;
                                    period_toggle <= ~period_toggle;
                                end else begin
                                    period_pos_a <= period_pos_a + 4;
                                end
                            end
                        end

                        if (sample_word_valid) begin
                            sample_frame <= sample_half ?
                                            sample_word[63:32] : sample_word[31:0];
                            sample_valid <= 1'b1;
                            underflow_active <= 1'b0;
                            if (sample_half) begin
                                sample_word_valid <= 1'b0;
                                sample_half <= 1'b0;
                            end else begin
                                sample_half <= 1'b1;
                            end
                        end else begin
                            sample_frame <= 0;
                            sample_valid <= 1'b0;
                            if (!underflow_active)
                                underflow_toggle <= ~underflow_toggle;
                            underflow_active <= 1'b1;
                        end
                    end else begin
                        serial_bit <= serial_bit + 1'b1;
                    end
                end
            end
        end
    end

    // play_pos is monotonic in the audio clock domain.  Gray coding prevents
    // torn multi-bit reads when it is observed by the register clock.
    wire [31:0] play_gray_a = (play_pos_a >> 1) ^ play_pos_a;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [31:0] play_gray_s1, play_gray_s2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [2:0] period_sync, underflow_sync;
    integer gray_index;
    always @* begin
        play_pos[31] = play_gray_s2[31];
        for (gray_index = 30; gray_index >= 0; gray_index = gray_index - 1)
            play_pos[gray_index] = play_pos[gray_index+1] ^ play_gray_s2[gray_index];
    end

    always @(posedge bus_clk or negedge bus_resetn) begin
        if (!bus_resetn) begin
            play_gray_s1 <= 0; play_gray_s2 <= 0;
            period_sync <= 0; underflow_sync <= 0;
            period_event <= 0; underflow_event <= 0;
        end else begin
            play_gray_s1 <= play_gray_a;
            play_gray_s2 <= play_gray_s1;
            period_sync <= {period_sync[1:0], period_toggle};
            underflow_sync <= {underflow_sync[1:0], underflow_toggle};
            period_event <= period_sync[2] ^ period_sync[1];
            underflow_event <= underflow_sync[2] ^ underflow_sync[1];
        end
    end
endmodule

//////////////////////////////////////////////////////////////////////
////                                                              ////
////  ps2_host.v                                                  ////
////                                                              ////
////  OpenCores PS/2 host controller, adapted for this SoC.       ////
////                                                              ////
////  Original author: Piotr Foltyn, piotr.foltyn@gmail.com       ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//// Copyright (C) 2011 Author                                    ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
//////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

// Raw, bidirectional PS/2 host.  The interface intentionally returns bytes
// without interpreting E0/F0 prefixes so Linux atkbd can perform decoding.
module ps2_host #(
    parameter integer SYS_CLOCK_HZ = 33_000_000
)(
    input  wire       sys_clk,
    input  wire       sys_rst,
    inout  wire       ps2_clk,
    inout  wire       ps2_data,
    input  wire [7:0] tx_data,
    input  wire       send_req,
    output wire       busy,
    output reg  [7:0] rx_data,
    output reg        ready,
    output reg        error
);
    localparam integer INHIBIT_CYCLES = SYS_CLOCK_HZ / 10_000;
    localparam integer WATCHDOG_CYCLES = SYS_CLOCK_HZ / 5_000;
    localparam integer TIMER_WIDTH = 16;

    reg [2:0] clk_sync;
    reg [2:0] data_sync;
    wire clk_rise = clk_sync[2:1] == 2'b01;
    wire clk_fall = clk_sync[2:1] == 2'b10;
    wire data_in = data_sync[2];

    reg clk_drive_low;
    reg data_drive_low;
    assign ps2_clk  = clk_drive_low  ? 1'b0 : 1'bz;
    assign ps2_data = data_drive_low ? 1'b0 : 1'bz;

    reg [3:0] rx_bit;
    reg [9:0] rx_shift;
    reg [TIMER_WIDTH-1:0] watchdog;

    localparam [2:0] TX_IDLE = 3'd0;
    localparam [2:0] TX_INHIBIT = 3'd1;
    localparam [2:0] TX_REQUEST = 3'd2;
    localparam [2:0] TX_BITS = 3'd3;
    localparam [2:0] TX_ACK = 3'd4;
    reg [2:0] tx_state;
    reg [TIMER_WIDTH-1:0] tx_timer;
    reg [3:0] tx_bit;
    reg [10:0] tx_frame;

    assign busy = tx_state != TX_IDLE;

    always @(posedge sys_clk) begin
        if (sys_rst) begin
            clk_sync      <= 3'b111;
            data_sync     <= 3'b111;
            clk_drive_low <= 1'b0;
            data_drive_low <= 1'b0;
            rx_bit        <= 4'd0;
            rx_shift      <= 10'h3ff;
            rx_data       <= 8'h00;
            ready         <= 1'b0;
            error         <= 1'b0;
            watchdog      <= WATCHDOG_CYCLES[TIMER_WIDTH-1:0];
            tx_state      <= TX_IDLE;
            tx_timer      <= {TIMER_WIDTH{1'b0}};
            tx_bit        <= 4'd0;
            tx_frame      <= 11'h7ff;
        end else begin
            clk_sync  <= {clk_sync[1:0], ps2_clk};
            data_sync <= {data_sync[1:0], ps2_data};
            ready <= 1'b0;
            error <= 1'b0;

            if (clk_rise || clk_fall)
                watchdog <= WATCHDOG_CYCLES[TIMER_WIDTH-1:0];
            else if (watchdog != 0)
                watchdog <= watchdog - 1'b1;
            else begin
                rx_bit <= 4'd0;
                if (tx_state != TX_IDLE) begin
                    tx_state <= TX_IDLE;
                    clk_drive_low <= 1'b0;
                    data_drive_low <= 1'b0;
                    error <= 1'b1;
                end
            end

            // Device-to-host receive path.  Samples start, eight data bits,
            // odd parity and stop on falling PS/2 clock edges.
            if (tx_state == TX_IDLE && clk_fall) begin
                if (rx_bit < 4'd10)
                    rx_shift[rx_bit] <= data_in;
                if (rx_bit == 4'd10) begin
                    rx_bit <= 4'd0;
                    if ((rx_shift[0] == 1'b0) &&
                        ((^rx_shift[9:1]) == 1'b1) &&
                        (data_in == 1'b1)) begin
                        rx_data <= rx_shift[8:1];
                        ready <= 1'b1;
                    end else begin
                        error <= 1'b1;
                    end
                end else begin
                    rx_bit <= rx_bit + 1'b1;
                end
            end

            case (tx_state)
                TX_IDLE: begin
                    clk_drive_low <= 1'b0;
                    data_drive_low <= 1'b0;
                    if (send_req) begin
                        // start, data LSB first, odd parity, stop
                        tx_frame <= {1'b1, ~^tx_data, tx_data, 1'b0};
                        tx_timer <= INHIBIT_CYCLES[TIMER_WIDTH-1:0];
                        clk_drive_low <= 1'b1;
                        tx_state <= TX_INHIBIT;
                    end
                end
                TX_INHIBIT: begin
                    if (tx_timer != 0)
                        tx_timer <= tx_timer - 1'b1;
                    else begin
                        data_drive_low <= 1'b1;
                        clk_drive_low <= 1'b0;
                        tx_bit <= 4'd0;
                        tx_state <= TX_REQUEST;
                    end
                end
                TX_REQUEST: begin
                    if (clk_fall) begin
                        data_drive_low <= ~tx_frame[0];
                        tx_bit <= 4'd1;
                        tx_state <= TX_BITS;
                    end
                end
                TX_BITS: begin
                    if (clk_fall) begin
                        if (tx_bit < 4'd11) begin
                            data_drive_low <= ~tx_frame[tx_bit];
                            tx_bit <= tx_bit + 1'b1;
                        end else begin
                            data_drive_low <= 1'b0;
                            tx_state <= TX_ACK;
                        end
                    end
                end
                TX_ACK: begin
                    if (clk_fall) begin
                        if (data_in != 1'b0)
                            error <= 1'b1;
                        tx_state <= TX_IDLE;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end
endmodule

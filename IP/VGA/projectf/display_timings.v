`timescale 1ns / 1ps
`default_nettype none

// Project F: Display Timings
// (C)2019 Will Green, Open Source Hardware released under the MIT License
// Learn more at https://projectf.io

// Defaults to 640x480 at 60 Hz

module display_timings #(
    H_RES=640,
    V_RES=480,
    H_FP=16,
    H_SYNC=96,
    H_BP=48,
    V_FP=10,
    V_SYNC=2,
    V_BP=33,
    H_POL=0,
    V_POL=0
    )
    (
    input  wire i_pix_clk,
    input  wire i_rst,
    output wire o_hs,
    output wire o_vs,
    output wire o_de,
    output wire o_frame,
    output reg signed [15:0] o_sx,
    output reg signed [15:0] o_sy
    );

    localparam signed H_STA  = 0 - H_FP - H_SYNC - H_BP;
    localparam signed HS_STA = H_STA + H_FP;
    localparam signed HS_END = HS_STA + H_SYNC;
    localparam signed HA_END = H_RES - 1;
    localparam signed V_STA  = 0 - V_FP - V_SYNC - V_BP;
    localparam signed VS_STA = V_STA + V_FP;
    localparam signed VS_END = VS_STA + V_SYNC;
    localparam signed VA_END = V_RES - 1;

    assign o_hs = H_POL ? (o_sx > HS_STA && o_sx <= HS_END)
        : ~(o_sx > HS_STA && o_sx <= HS_END);
    assign o_vs = V_POL ? (o_sy > VS_STA && o_sy <= VS_END)
        : ~(o_sy > VS_STA && o_sy <= VS_END);
    assign o_de = (o_sx >= 0 && o_sy >= 0);
    assign o_frame = (o_sy == V_STA && o_sx == H_STA);

    always @ (posedge i_pix_clk)
    begin
        if (i_rst)
        begin
            o_sx <= H_STA;
            o_sy <= V_STA;
        end
        else
        begin
            if (o_sx == HA_END)
            begin
                o_sx <= H_STA;
                if (o_sy == VA_END)
                    o_sy <= V_STA;
                else
                    o_sy <= o_sy + 16'sh1;
            end
            else
                o_sx <= o_sx + 16'sh1;
        end
    end
endmodule

`default_nettype wire

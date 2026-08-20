module i2s_gen(
    input  wire        aud_clk_i , // 22.5792Mhz for 44.1khz || 24.576mhz for 48khz
    input  wire        aud_rst_i ,

    output reg         sclk_o  ,
    output reg         wclk_o  ,
    output reg         sdata_o ,
    
    input  wire  [31:0]audio_data_i,
    input  wire        audio_data_valid_i,
    output wire        audio_data_ready_o
);

    reg [8:0]   clk_divider;
    reg [31:0] audio_data_q;
    always_ff @(posedge aud_clk_i) begin
        if(aud_rst_i) begin
            clk_divider <= '0;
        end else begin
            clk_divider <= clk_divider + 1;
        end
    end
    (*mark_debug="true"*) wire sck_negedge = &clk_divider[3:0];
    (*mark_debug="true"*) wire wck_negedge = &clk_divider[8:0];
    wire sdata_d = audio_data_q[5'd31 - clk_divider[8:4]];
    (*mark_debug="true"*) reg  sdata_q;
    always_ff @(posedge aud_clk_i) begin
        if(sck_negedge) begin
            sdata_q <= sdata_d;
        end
    end
    // clk_divider[0] // 11.2896 MHZ
    // clk_divider[1] //  5.6448 MHZ
    // clk_divider[2] //  2.8224 MHZ
    // clk_divider[3] //  1.4112 MHZ - sclk == 2 * 16 * 44100
    // clk_divider[4] //  705.6  KHZ
    // clk_divider[5] //  352.8  KHZ
    // clk_divider[6] //  176.4  KHZ
    // clk_divider[7] //   88.2  KHZ
    // clk_divider[8] //   44.1  KHZ - wclk == 2 * 44100
    always_ff @(posedge aud_clk_i) begin
        sclk_o <= clk_divider[3];
        wclk_o <= clk_divider[8];
        sdata_o <= sdata_q;
    end
    assign audio_data_ready_o = wck_negedge || aud_rst_i;
    always_ff @(posedge aud_clk_i) begin
        if(audio_data_ready_o) begin
            audio_data_q <= audio_data_valid_i ? audio_data_i : '0;
        end
    end

endmodule

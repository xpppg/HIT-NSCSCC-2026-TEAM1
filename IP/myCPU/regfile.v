module regfile(
    input  wire        clk,
    // READ PORT 1
    input  wire [ 4:0] raddr1,
    output wire [31:0] rdata1,
    // READ PORT 2
    input  wire [ 4:0] raddr2,
    output wire [31:0] rdata2,
    // READ PORT 3
    input  wire [ 4:0] raddr3,
    output wire [31:0] rdata3,
    // READ PORT 4
    input  wire [ 4:0] raddr4,
    output wire [31:0] rdata4,
    // WRITE PORT 1
    input  wire        we1,       //write enable, HIGH valid
    input  wire [ 4:0] waddr1,
    input  wire [31:0] wdata1,
    // WRITE PORT 2
    input  wire        we2,       //write enable, HIGH valid
    input  wire [ 4:0] waddr2,
    input  wire [31:0] wdata2,

    input  wire        turning
`ifdef DIFFTEST_EN
    ,
    output wire [31:0] rf_o [31:0]
`endif
);
reg [31:0] rf[31:0];

//WRITE
always @(posedge clk) begin
    if (we1 & we2) 
    begin
        if(turning) begin
          rf[waddr2] <= wdata2;
          rf[waddr1] <= wdata1;
        end
        else begin
          rf[waddr1] <= wdata1;
          rf[waddr2] <= wdata2;
        end
    end
    else if(we1)
        rf[waddr1] <= wdata1;
    else if(we2)
        rf[waddr2] <= wdata2;
end

//READ OUT 1
assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : rf[raddr1];

//READ OUT 2
assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : rf[raddr2];

//READ OUT 3
assign rdata3 = (raddr3 == 5'b0) ? 32'b0 : rf[raddr3];

//READ OUT 4
assign rdata4 = (raddr4 == 5'b0) ? 32'b0 : rf[raddr4];

`ifdef DIFFTEST_EN
assign rf_o[0]  = rf[0];
assign rf_o[1]  = rf[1];
assign rf_o[2]  = rf[2];
assign rf_o[3]  = rf[3];
assign rf_o[4]  = rf[4];
assign rf_o[5]  = rf[5];
assign rf_o[6]  = rf[6];
assign rf_o[7]  = rf[7];
assign rf_o[8]  = rf[8];
assign rf_o[9]  = rf[9];
assign rf_o[10] = rf[10];
assign rf_o[11] = rf[11];
assign rf_o[12] = rf[12];
assign rf_o[13] = rf[13];
assign rf_o[14] = rf[14];
assign rf_o[15] = rf[15];
assign rf_o[16] = rf[16];
assign rf_o[17] = rf[17];
assign rf_o[18] = rf[18];
assign rf_o[19] = rf[19];
assign rf_o[20] = rf[20];
assign rf_o[21] = rf[21];
assign rf_o[22] = rf[22];
assign rf_o[23] = rf[23];
assign rf_o[24] = rf[24];
assign rf_o[25] = rf[25];
assign rf_o[26] = rf[26];
assign rf_o[27] = rf[27];
assign rf_o[28] = rf[28];
assign rf_o[29] = rf[29];
assign rf_o[30] = rf[30];
assign rf_o[31] = rf[31];
`endif

endmodule

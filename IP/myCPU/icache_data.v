module cache_data (
    input          clk        ,  // 时钟
    input          resetn     ,  // 低有效复位信号

    //读端口
    input  [ 31:0] raddr      ,    //由CPU发送至Cache
    input          re_way_sel0,
    output [ 31:0] rdata      ,
    output [ 31:0] rdata2     ,
    //写端口
    input          we         ,
    input  [ 31:0] waddr      ,
    input  wire    we_way_sel0,
    input  [511:0] wcacheline

);

wire [31:0] rdata0 [15:0];
wire [31:0] rdata1 [15:0];
wire [31:0] rdata_way0;
wire [31:0] rdata_way1;
wire [31:0] rdata2_way0;
wire [31:0] rdata2_way1;
wire [5:0] index;
wire [3:0] offset;

reg r_sel0;
reg  [3:0] r_offset;
wire [9:0] bram_addr;
wire [3:0] way0_we;
wire [3:0] way1_we;

assign bram_addr = we ? waddr[11:2] : raddr[11:2];
assign index = bram_addr[9:4];
assign offset = bram_addr[3:0];
assign way0_we = {4{we & we_way_sel0}};
assign way1_we = {4{we & ~we_way_sel0}};

data_bram_bank bank0_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[31:0]),
    .douta(rdata0[0])
);
data_bram_bank bank1_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[63:32]),
    .douta(rdata0[1])
);
data_bram_bank bank2_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[95:64]),
    .douta(rdata0[2])
);
data_bram_bank bank3_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[127:96]),
    .douta(rdata0[3])
);
data_bram_bank bank4_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[159:128]),
    .douta(rdata0[4])
);
data_bram_bank bank5_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[191:160]),
    .douta(rdata0[5])
);
data_bram_bank bank6_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[223:192]),
    .douta(rdata0[6])
);
data_bram_bank bank7_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[255:224]),
    .douta(rdata0[7])
);
data_bram_bank bank8_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[287:256]),
    .douta(rdata0[8])
);
data_bram_bank bank9_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[319:288]),
    .douta(rdata0[9])
);
data_bram_bank bank10_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[351:320]),
    .douta(rdata0[10])
);
data_bram_bank bank11_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[383:352]),
    .douta(rdata0[11])
);
data_bram_bank bank12_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[415:384]),
    .douta(rdata0[12])
);
data_bram_bank bank13_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[447:416]),
    .douta(rdata0[13])
);
data_bram_bank bank14_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[479:448]),
    .douta(rdata0[14])
);
data_bram_bank bank15_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(way0_we),
    .addra(index),
    .dina(wcacheline[511:480]),
    .douta(rdata0[15])
);

data_bram_bank bank0_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[31:0]),
    .douta(rdata1[0])
);
data_bram_bank bank1_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[63:32]),
    .douta(rdata1[1])
);
data_bram_bank bank2_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[95:64]),
    .douta(rdata1[2])
);
data_bram_bank bank3_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[127:96]),
    .douta(rdata1[3])
);
data_bram_bank bank4_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[159:128]),
    .douta(rdata1[4])
);
data_bram_bank bank5_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[191:160]),
    .douta(rdata1[5])
);
data_bram_bank bank6_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[223:192]),
    .douta(rdata1[6])
);
data_bram_bank bank7_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[255:224]),
    .douta(rdata1[7])
);
data_bram_bank bank8_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[287:256]),
    .douta(rdata1[8])
);
data_bram_bank bank9_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[319:288]),
    .douta(rdata1[9])
);
data_bram_bank bank10_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[351:320]),
    .douta(rdata1[10])
);
data_bram_bank bank11_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[383:352]),
    .douta(rdata1[11])
);
data_bram_bank bank12_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[415:384]),
    .douta(rdata1[12])
);
data_bram_bank bank13_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[447:416]),
    .douta(rdata1[13])
);
data_bram_bank bank14_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[479:448]),
    .douta(rdata1[14])
);
data_bram_bank bank15_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(way1_we),
    .addra(index),
    .dina(wcacheline[511:480]),
    .douta(rdata1[15])
);

always@(posedge clk) begin
    r_sel0 <= re_way_sel0;
    r_offset <= offset;
end


assign rdata_way0 = rdata0[r_offset];
assign rdata_way1 = rdata1[r_offset];
assign rdata2_way0 = rdata0[r_offset + 4'h1];
assign rdata2_way1 = rdata1[r_offset + 4'h1];

assign rdata = r_sel0 ? rdata_way0 : rdata_way1;
assign rdata2 = r_sel0 ? rdata2_way0 : rdata2_way1;

endmodule

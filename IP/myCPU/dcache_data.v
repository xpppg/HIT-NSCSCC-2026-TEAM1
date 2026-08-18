module dcache_data(
    input wire clk,
    input wire rst,

    input wire [1:0] hit,
    input wire [1:0] hit1,
    input wire sel1,

    // cpu_port
    input wire [3:0] cpu_wen,
    input wire [31:0] cpu_addr,
    input wire [31:0] cpu_wdata,
    output wire [31:0] cpu_rdata,

    // axi
    input wire refresh,
    input wire [511:0] cacheline_new,
    output wire [511:0] cacheline_old
);
    wire [31:0] rdata_way0 [15:0];
    wire [31:0] rdata_way1 [15:0];
    wire [19:0] tag;
    wire [5:0] index;
    wire [5:0] offset;
    reg [1:0] hit_r;
    assign {
        tag,
        index,
        offset
    } = cpu_addr;

    wire [15:0] bank_sel;
    reg [15:0] bank_sel_r;
    reg [3:0] bank_index_r;
    decoder_4_16 u_decoder_4_16(
    	.in  (offset[5:2]  ),
        .out (bank_sel )
    );

    always @ (posedge clk) begin
        if (rst) begin
            hit_r <= 2'b0;
            //bank_sel_r <= 16'b0;
            bank_index_r <= 4'b0;
        end
        else begin
            hit_r <= hit1;
            //bank_sel_r <= bank_sel;
            bank_index_r <= offset[5:2];
        end
    end
    
    data_bram_bank bank0_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[0]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[31:0]:cpu_wdata),    // 32
        .douta(rdata_way0[0])    //32
    );
    data_bram_bank bank1_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[1]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[63:32]:cpu_wdata),    // 32
        .douta(rdata_way0[1])    //32
    );
    data_bram_bank bank2_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[2]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[95:64]:cpu_wdata),    // 32
        .douta(rdata_way0[2])    //32
    );
    data_bram_bank bank3_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[3]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[127:96]:cpu_wdata),    // 32
        .douta(rdata_way0[3])    //32
    );
    data_bram_bank bank4_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[4]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[159:128]:cpu_wdata),    // 32
        .douta(rdata_way0[4])    //32
    );
    data_bram_bank bank5_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[5]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[191:160]:cpu_wdata),    // 32
        .douta(rdata_way0[5])    //32
    );
    data_bram_bank bank6_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[6]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[223:192]:cpu_wdata),    // 32
        .douta(rdata_way0[6])    //32
    );
    data_bram_bank bank7_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[7]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[255:224]:cpu_wdata),    // 32
        .douta(rdata_way0[7])    //32
    );
    data_bram_bank bank8_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[8]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[287:256]:cpu_wdata),    // 32
        .douta(rdata_way0[8])    //32
    );
    data_bram_bank bank9_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[9]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[319:288]:cpu_wdata),    // 32
        .douta(rdata_way0[9])    //32
    );
    data_bram_bank bank10_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[10]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[351:320]:cpu_wdata),    // 32
        .douta(rdata_way0[10])    //32
    );
    data_bram_bank bank11_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[11]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[383:352]:cpu_wdata),    // 32
        .douta(rdata_way0[11])    //32
    );
    data_bram_bank bank12_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[12]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[415:384]:cpu_wdata),    // 32
        .douta(rdata_way0[12])    //32
    );
    data_bram_bank bank13_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[13]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[447:416]:cpu_wdata),    // 32
        .douta(rdata_way0[13])    //32
    );
    data_bram_bank bank14_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[14]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[479:448]:cpu_wdata),    // 32
        .douta(rdata_way0[14])    //32
    );
    data_bram_bank bank15_way0(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&~sel1)?4'b1111:bank_sel[15]&hit[0]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[511:480]:cpu_wdata),    // 32
        .douta(rdata_way0[15])    //32
    );
    data_bram_bank bank0_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[0]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[31:0]:cpu_wdata),    // 32
        .douta(rdata_way1[0])    //32
    );
    data_bram_bank bank1_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[1]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[63:32]:cpu_wdata),    // 32
        .douta(rdata_way1[1])    //32
    );
    data_bram_bank bank2_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[2]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[95:64]:cpu_wdata),    // 32
        .douta(rdata_way1[2])    //32
    );
    data_bram_bank bank3_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[3]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[127:96]:cpu_wdata),    // 32
        .douta(rdata_way1[3])    //32
    );
    data_bram_bank bank4_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[4]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[159:128]:cpu_wdata),    // 32
        .douta(rdata_way1[4])    //32
    );
    data_bram_bank bank5_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[5]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[191:160]:cpu_wdata),    // 32
        .douta(rdata_way1[5])    //32
    );
    data_bram_bank bank6_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[6]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[223:192]:cpu_wdata),    // 32
        .douta(rdata_way1[6])    //32
    );
    data_bram_bank bank7_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[7]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[255:224]:cpu_wdata),    // 32
        .douta(rdata_way1[7])    //32
    );
    data_bram_bank bank8_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[8]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[287:256]:cpu_wdata),    // 32
        .douta(rdata_way1[8])    //32
    );
    data_bram_bank bank9_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[9]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[319:288]:cpu_wdata),    // 32
        .douta(rdata_way1[9])    //32
    );
    data_bram_bank bank10_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[10]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[351:320]:cpu_wdata),    // 32
        .douta(rdata_way1[10])    //32
    );
    data_bram_bank bank11_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[11]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[383:352]:cpu_wdata),    // 32
        .douta(rdata_way1[11])    //32
    );
    data_bram_bank bank12_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[12]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[415:384]:cpu_wdata),    // 32
        .douta(rdata_way1[12])    //32
    );
    data_bram_bank bank13_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[13]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[447:416]:cpu_wdata),    // 32
        .douta(rdata_way1[13])    //32
    );
    data_bram_bank bank14_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[14]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[479:448]:cpu_wdata),    // 32
        .douta(rdata_way1[14])    //32
    );
    data_bram_bank bank15_way1(
        .clka(clk),
        .ena(1'b1),     // 1
        .wea((refresh&sel1)?4'b1111:bank_sel[15]&hit[1]?cpu_wen:4'b0000),     // 4
        .addra(index),   // 7
        .dina(refresh?cacheline_new[511:480]:cpu_wdata),    // 32
        .douta(rdata_way1[15])    //32
    );

    wire [31:0] cpu_rdata_way0,cpu_rdata_way1;

    assign cpu_rdata_way0 = rdata_way0[bank_index_r];
    assign cpu_rdata_way1 = rdata_way1[bank_index_r];

    assign cpu_rdata = ({32{hit_r[0]}} & cpu_rdata_way0) |
                        ({32{hit_r[1]}} & cpu_rdata_way1);

    wire [511:0] cacheline_old_way0, cacheline_old_way1;
    assign cacheline_old_way0 = {
        rdata_way0[15],
        rdata_way0[14],
        rdata_way0[13],
        rdata_way0[12],
        rdata_way0[11],
        rdata_way0[10],
        rdata_way0[9],
        rdata_way0[8],
        rdata_way0[7],
        rdata_way0[6],
        rdata_way0[5],
        rdata_way0[4],
        rdata_way0[3],
        rdata_way0[2],
        rdata_way0[1],
        rdata_way0[0]
    };
    assign cacheline_old_way1 = {
        rdata_way1[15],
        rdata_way1[14],
        rdata_way1[13],
        rdata_way1[12],
        rdata_way1[11],
        rdata_way1[10],
        rdata_way1[9],
        rdata_way1[8],
        rdata_way1[7],
        rdata_way1[6],
        rdata_way1[5],
        rdata_way1[4],
        rdata_way1[3],
        rdata_way1[2],
        rdata_way1[1],
        rdata_way1[0]
    };
    assign cacheline_old = sel1 ? cacheline_old_way1 : cacheline_old_way0;
endmodule
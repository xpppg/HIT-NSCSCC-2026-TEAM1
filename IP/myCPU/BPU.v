module BPU(
    input  wire        clk,
    input  wire        rst,
    input  wire        clk_rst,
    output wire        pht_rst,
    // 读端口
    input  wire [31:0] pc,
    output wire [31:0] pred_target,
    output wire pred_hit1,
    output wire [1:0] pred_pht,

    input  wire [31:0] pc2,
    output wire [31:0] pred_target_2,
    output wire pred_hit2,
    output wire [1:0] pred_pht2,
    // 写端口    
    input  wire [31:0] br_pc,
    input  wire [31:0] br_target,
    input  wire [ 1:0] br_pht,
    input  wire        inst_br,       
    input  wire        actual_taken
);
wire BTB_hit1;
wire BTB_hit2;
wire PHT_taken;
wire PHT_taken_2;

    BTB u_BTB(
        .clk        (clk),
        .rst        (rst),

        .pc         (pc),
        .pred_target(pred_target),
        .BTB_hit1   (BTB_hit1),

        .pc2        (pc2),
        .pred_target_2(pred_target_2),
        .BTB_hit2   (BTB_hit2),

        .BTB_wen    (actual_taken),
        .br_pc      (br_pc),
        .br_target  (br_target)
    );

    PHT u_PHT(
        .clk         (clk),
        .rst         (rst),
        .clk_rst     (clk_rst),
        .pht_rst     (pht_rst),
        
        .pc          (pc),
        .PHT_taken  (PHT_taken),
        .pred_pht   (pred_pht),

        .pc2         (pc2),
        .PHT_taken_2(PHT_taken_2),
        .pred_pht2  (pred_pht2),

        .PHT_wen     (inst_br),
        .br_pc       (br_pc),
        .br_pht      (br_pht),
        .actual_taken(actual_taken)
    );

    assign pred_hit1 = BTB_hit1 & PHT_taken;
    assign pred_hit2 = BTB_hit2 & PHT_taken_2;

    //RAS u_RAS(
    //    .clk         (clk),
    //    .rst         (reset),
    //    
    //    .RAS_ren     ((pred_jirl_pre_IF | pred_jirl_pre_IF_2) & pre_IF_ready_go & IF1_allowin),
    //    .RAS_target  (r1_value),
    //    .RAS_v       (RAS_v),

    //    .RAS_wen     (br_bl),
    //    .ret_addr    (br_pc + 32'h4)
    //);
endmodule

module BTB(
    input  wire        clk,
    input  wire        rst,
    // 读端口
    input  wire [31:0] pc,
    output wire [31:0] pred_target,
    output wire BTB_hit1,

    input  wire [31:0] pc2,
    output wire [31:0] pred_target_2,
    output wire BTB_hit2,
    // 写端口
    input  wire        BTB_wen,       
    input  wire [31:0] br_pc,
    input  wire [31:0] br_target
);
reg  timer;//伪随机数发生器
wire [9:0] rindex;
wire [9:0] rindex_2;
wire [9:0] windex;
wire v_way0;
wire v2_way0;
wire v_way1;
wire v2_way1;
reg  v_way0_buf;
reg  v2_way0_buf;
reg  v_way1_buf;
reg  v2_way1_buf;
reg  [7:0] PC_tag;
reg  [7:0] PC2_tag;
//reg  [31:0] BTB_way0[1023:0];
//reg  [31:0] BTB_way1[1023:0];
reg  [1023:0] BTB_v_0;
reg  [1023:0] BTB_v_1;
wire [7:0] tag_way0;
wire [7:0] tag2_way0;
wire [7:0] tag_way1;
wire [7:0] tag2_way1;

wire tag_hit;
wire tag_hit_2;

assign rindex   = pc[11:2];
assign rindex_2 = pc2[11:2];
assign windex   = br_pc[11:2];

wire r_sel0;
wire r2_sel0;
wire [31:0] rdata_way0;
wire [31:0] rdata_way1;
wire [31:0] rdata2_way0;
wire [31:0] rdata2_way1;

always @(posedge clk) begin
    if(rst) begin
        timer <= 1'b0;
    end 
    else begin
        timer <= timer + 1'b1;
    end
end

//WRITE
integer i;
always @(posedge clk) begin
    if(rst) begin
        BTB_v_0 <= 1024'b0;
        BTB_v_1 <= 1024'b0;
    end 
    else if(BTB_wen) begin
        if(~BTB_v_0[windex]) begin
            //BTB_way0[windex] <= br_target;
            BTB_v_0[windex] <= 1'b1;
            //BTB_tag_way0[windex] <= br_pc[19:12];
        end
        else if(~BTB_v_1[windex]) begin
            //BTB_way1[windex] <= br_target;
            BTB_v_1[windex] <= 1'b1;
            //BTB_tag_way1[windex] <= br_pc[19:12];
        end
        /*else begin //随机替换
            if(timer) begin
                //BTB_way0[windex] <= br_target;
                BTB_tag_way0[windex] <= br_pc[19:12];
            end 
            else begin
                //BTB_way1[windex] <= br_target;
                BTB_tag_way1[windex] <= br_pc[19:12];
            end
        end*/
    end
end

btb_tag_bram btb_tag_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(BTB_wen & (~BTB_v_0[windex] | (BTB_v_1[windex] & timer))),
    .addra(windex),
    .dina(br_pc[19:12]),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex),
    .doutb(tag_way0)
);

btb_tag_bram btb_tag_way0_sub(
    .clka(clk),
    .ena(1'b1),
    .wea(BTB_wen & (~BTB_v_0[windex] | (BTB_v_1[windex] & timer))),
    .addra(windex),
    .dina(br_pc[19:12]),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex_2),
    .doutb(tag2_way0)
);

btb_tag_bram btb_tag_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(BTB_wen & ((BTB_v_0[windex] & ~BTB_v_1[windex]) | (BTB_v_0[windex] & BTB_v_1[windex] & ~timer))),
    .addra(windex),
    .dina(br_pc[19:12]),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex),
    .doutb(tag_way1)
);

btb_tag_bram btb_tag_way1_sub(
    .clka(clk),
    .ena(1'b1),
    .wea(BTB_wen & ((BTB_v_0[windex] & ~BTB_v_1[windex]) | (BTB_v_0[windex] & BTB_v_1[windex] & ~timer))),
    .addra(windex),
    .dina(br_pc[19:12]),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex_2),
    .doutb(tag2_way1)
);


btb_bram btb_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(BTB_wen & (~BTB_v_0[windex] | (BTB_v_1[windex] & timer))),
    .addra(windex),
    .dina(br_target),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex),
    .doutb(rdata_way0)
);

btb_bram btb_way0_sub(
    .clka(clk),
    .ena(1'b1),
    .wea(BTB_wen & (~BTB_v_0[windex] | (BTB_v_1[windex] & timer))),
    .addra(windex),
    .dina(br_target),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex_2),
    .doutb(rdata2_way0)
);

btb_bram btb_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(BTB_wen & ((BTB_v_0[windex] & ~BTB_v_1[windex]) | (BTB_v_0[windex] & BTB_v_1[windex] & ~timer))),
    .addra(windex),
    .dina(br_target),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex),
    .doutb(rdata_way1)
);

btb_bram btb_way1_sub(
    .clka(clk),
    .ena(1'b1),
    .wea(BTB_wen & ((BTB_v_0[windex] & ~BTB_v_1[windex]) | (BTB_v_0[windex] & BTB_v_1[windex] & ~timer))),
    .addra(windex),
    .dina(br_target),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex_2),
    .doutb(rdata2_way1)
);

assign v_way0 = BTB_v_0[rindex];
assign v2_way0 = BTB_v_0[rindex_2];
assign v_way1 = BTB_v_1[rindex];
assign v2_way1 = BTB_v_1[rindex_2];

assign tag_hit   = ((tag_way0 == PC_tag) && v_way0_buf) | ((tag_way1 == PC_tag) && v_way1_buf);
assign tag_hit_2 = ((tag2_way0 == PC2_tag) && v2_way0_buf) | ((tag2_way1 == PC2_tag) && v2_way1_buf);

assign r_sel0 = (tag_way0 == PC_tag) && v_way0_buf;
assign r2_sel0 = (tag2_way0 == PC2_tag) && v2_way0_buf;

assign pred_target = r_sel0 ? rdata_way0 : rdata_way1;
assign pred_target_2 = r2_sel0 ? rdata2_way0 : rdata2_way1;

always @(posedge clk) begin
    if(rst) begin
        PC_tag <= 8'b0;
        PC2_tag <= 8'b0;
        v_way0_buf <= 1'b0;
        v2_way0_buf <= 1'b0;
        v_way1_buf <= 1'b0;
        v2_way1_buf <= 1'b0;
    end 
    else begin
        PC_tag <= pc[19:12];
        PC2_tag <= pc2[19:12];
        v_way0_buf <= v_way0;
        v2_way0_buf <= v2_way0;
        v_way1_buf <= v_way1;
        v2_way1_buf <= v2_way1;
    end
end

assign BTB_hit1 = tag_hit;
assign BTB_hit2 = tag_hit_2;

endmodule

module PHT(
    input  wire        clk,
    input  wire        rst,
    input  wire        clk_rst,
    output reg         pht_rst,
    // 读端口
    input  wire [31:0] pc,
    output wire PHT_taken,
    output wire [1:0] pred_pht,
    //output wire pred_jirl,

    input  wire [31:0] pc2,
    output wire PHT_taken_2,
    output wire [1:0] pred_pht2,
    //output wire pred_jirl_2,
    // 写端口
    input  wire        PHT_wen,       
    input  wire [31:0] br_pc,
    input  wire [ 1:0] br_pht,
    input  wire        actual_taken
    //input  wire        br_jirl
);
wire pred_taken;
wire pred_taken_2;
//wire [11:0] rindex;
//wire [11:0] rindex_2;
//wire [11:0] windex;
wire [ 9:0] rindex;
wire [ 9:0] rindex_2;
wire [ 9:0] windex;
//wire [ 9:0] RAS_rindex;
//wire [ 9:0] RAS_rindex_2;
//wire [ 9:0] RAS_windex;
wire [10:0] rindex_PHTs;
wire [10:0] rindex_2_PHTs;
wire [10:0] windex_PHTs;
wire index_10_1;
wire index_10_2;
wire index_10_3;
reg  [10:0] offset;

//reg  [1:0] PHT[4095:0];
reg  [1:0] BHT[1023:0];
reg  [1:0] GHR;
reg  [1:0] BHT_value;
reg  [1:0] BHT_value2;
wire [1:0] PHT_value;
wire [1:0] PHT_value2;
//reg  JL[1023:0]; // 记录是否是jirl指令
//reg  [19:0] JL_tag[1023:0]; // 记录jirl指令的tag


//assign rindex   = {GHR,pc[11:2]};
//assign rindex_2 = {GHR,pc2[11:2]};
//assign windex   = {GHR,br_pc[11:2]};
assign rindex   = pc[11:2] ^ pc[21:12];
assign rindex_2 = pc2[11:2] ^ pc2[21:12];
assign windex   = br_pc[11:2] ^ br_pc[21:12];

//assign RAS_rindex   = pc[11:2];
//assign RAS_rindex_2 = pc2[11:2];
//assign RAS_windex   = br_pc[11:2];

assign index_10_1 = BHT[rindex][0];
assign index_10_2 = BHT[rindex_2][0];
assign index_10_3 = BHT[windex][0];

assign rindex_PHTs = {index_10_1, rindex};
assign rindex_2_PHTs = {index_10_2, rindex_2};
assign windex_PHTs = {index_10_3, windex};

//WRITE
integer j;
always @(posedge clk) begin
    if(rst) begin
        for(j = 0; j < 1024; j = j + 1) begin
            BHT[j] = 2'b00; 
            //JL[j] <= 1'b0;
        end
    end 
    else if(PHT_wen) begin
        BHT[windex] <= {BHT[windex][0],actual_taken};
        //JL[RAS_windex] <= br_jirl;
        //JL_tag[RAS_windex] <= br_pc[31:12];
    end
end

always @(posedge clk) begin
    if(clk_rst & ~pht_rst) begin
        pht_rst <= 1'b1;
        offset <= 11'b0;
    end 
    else if(pht_rst) begin
        if(offset == 11'b11111111111) begin
            if(clk_rst) begin
                pht_rst <= 1'b1;
                offset <= 11'b11111111111;
            end 
            else begin
                pht_rst <= 1'b0;
                offset <= 11'b0;
            end
        end
        else begin
            offset <= offset + 1'b1;
        end
    end
    else begin
        pht_rst <= 1'b0;
        offset <= 11'b0;
    end
end



wire pht_we;
wire [10:0] pht_windex;
wire [1:0] pht_wdata;

assign pht_we = (PHT_wen & ((actual_taken & (br_pht < 2'b11)) | (~actual_taken & (br_pht > 2'b00)))) | pht_rst;
assign pht_windex = pht_rst ? offset : windex_PHTs;
assign pht_wdata = pht_rst ? 2'b0 : actual_taken ? (br_pht + 1'b1) : (br_pht - 1'b1);

pht_bram pht_way0(
    .clka(clk),
    .ena(1'b1),
    .wea(pht_we),
    .addra(pht_windex),
    .dina(pht_wdata),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex_PHTs),
    .doutb(PHT_value)
);

pht_bram pht_way1(
    .clka(clk),
    .ena(1'b1),
    .wea(pht_we),
    .addra(pht_windex),
    .dina(pht_wdata),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rindex_2_PHTs),
    .doutb(PHT_value2)
);

always @(posedge clk) begin
    if(rst) begin
        BHT_value <= 2'b0;
        BHT_value2 <= 2'b0;
    end 
    else begin
        BHT_value <= BHT[rindex];
        BHT_value2 <= BHT[rindex_2];
    end
end

assign PHT_taken = (BHT_value == 2'b11) ? 1'b1 :
                  (BHT_value == 2'b00) ? 1'b0 : PHT_value[1];

assign PHT_taken_2 = (BHT_value2 == 2'b11) ? 1'b1 :
                     (BHT_value2 == 2'b00) ? 1'b0 : PHT_value2[1];

assign pred_pht = PHT_value;
assign pred_pht2 = PHT_value2;

//assign pred_jirl = JL[RAS_rindex] && (JL_tag[RAS_rindex] == pc[31:12]);
//assign pred_jirl_2 = JL[RAS_rindex_2] && (JL_tag[RAS_rindex_2] == pc2[31:12]);

endmodule



module RAS(
    input  wire        clk,
    input  wire        rst,
    // 读端口
    input  wire        RAS_ren,
    output wire [31:0] RAS_target,
    output wire        RAS_v,
    // 写端口
    input  wire        RAS_wen,       
    input  wire [31:0] ret_addr
);
reg [31:0] stack[31:0];
reg [4:0]  times;
reg [31:0] total_times;

wire RAS_full;
wire RAS_empty;

assign RAS_full = (times == 5'b11111);
assign RAS_empty = (times == 5'b0);
assign RAS_v = ~(times == 5'b0);

always @(posedge clk) begin
    if(rst) begin
        times <= 5'b0;
        total_times <= 32'b0;
    end 
    else if(RAS_wen & ~RAS_ren) begin
        if(RAS_full) begin
            times <= times;
        end
        else begin
            stack[times + 1'b1] <= ret_addr;
            times <= times + 1'b1;
        end
        total_times <= total_times + 1'b1;
    end
    else if(~RAS_wen & RAS_ren & ~RAS_empty) begin
        if(times == total_times) begin
            times <= times - 1'b1;
        end
        else begin
            times <= times;
        end
        total_times <= total_times - 1'b1;
    end
end

assign RAS_target = RAS_wen ? ret_addr : stack[times];



endmodule
module IF(
    input wire clk,
    input wire reset,
    input wire br_taken,
    input wire wb_ex,
    input wire ertn_flush,
    input wire tlb_remake,
    
    input wire pre_IF_ready_go,
    input wire IF1_allowin,
    input wire IF1_ready_go,
    input wire IF2_allowin,
    input wire IF2_ready_go,
    input wire ID_allowin,

    input wire [31:0] nextpc,
    input wire sub_inst_valid,
    input wire pred_taken_pre_IF,
    input wire [31:0] pred_target_pre_IF,
    input wire [1:0] pred_pht_pre_IF,
    input wire pred_taken_pre_IF_2,
    input wire [31:0] pred_target_pre_IF_2,
    input wire [1:0] pred_pht2_pre_IF,

    input wire inst_sram_en,
    input wire inst_stall,
    input wire [31:0] inst_sram_rdata,
    input wire [31:0] inst_sram_rdata2,

    output reg IF1_valid,
    output reg inst_en,
    output reg [31:0] pc_buf_IF1,

    output reg IF2_valid,
    output reg sub_inst_valid_IF2,
    output reg [31:0] pc_buf_IF2,
    output wire [31:0] IF_inst,
    output wire [31:0] IF_inst2,
    output reg pred_taken_IF2,
    output reg [31:0] pred_target_IF2,
    output reg [1:0] pred_pht_IF2,
    output reg pred_taken_IF2_2,
    output reg [31:0] pred_target_IF2_2,
    output reg [1:0] pred_pht2_IF2,

    output wire pred_taken,
    output wire [31:0] pred_target,
    output wire pred_wating

);
reg pred_taken_IF1;
reg pred_taken_IF1_2;
reg [31:0] pred_target_IF1;
reg [31:0] pred_target_IF1_2;
reg [1:0] pred_pht_IF1;
reg [1:0] pred_pht2_IF1;
wire sub_inst_valid_IF1;
reg  sub_inst_valid_buf_IF1;

reg         pred_buf_sel;
reg         pred_taken_buf;
reg         pred_taken_buf_2;
reg  [31:0] pred_target_buf;
reg  [31:0] pred_target_buf_2;
reg  [1:0]  pred_pht_buf;
reg  [1:0]  pred_pht2_buf;

always @(posedge clk) begin
    if(reset)
    begin
        pred_buf_sel <= 1'b0;
        pred_taken_IF1 <= 1'b0;
        pred_taken_IF1_2 <= 1'b0;
        pred_target_IF1 <= 32'h0;
        pred_target_IF1_2 <= 32'h0;
        pred_pht_IF1 <= 2'b0;
        pred_pht2_IF1 <= 2'b0;
    end
    else if(pred_wating & ~pred_buf_sel)
    begin
        pred_buf_sel <= 1'b1;
        pred_taken_IF1 <= pred_taken_pre_IF;
        pred_taken_IF1_2 <= pred_taken_pre_IF_2;
        pred_target_IF1 <= pred_target_pre_IF;
        pred_target_IF1_2 <= pred_target_pre_IF_2;
        pred_pht_IF1 <= pred_pht_pre_IF;
        pred_pht2_IF1 <= pred_pht2_pre_IF;
    end
    else if(IF1_ready_go & IF2_allowin)
    begin
        pred_buf_sel <= 1'b0;
    end
end

assign pred_taken = pred_buf_sel & ((pred_taken_IF1 & IF1_valid) | (pred_taken_IF1_2 & sub_inst_valid_IF1));
assign pred_target = pred_taken_IF1 ? pred_target_IF1 : pred_target_IF1_2;
assign pred_wating = ~pred_buf_sel & ((pred_taken_pre_IF & IF1_valid) | (pred_taken_pre_IF_2 & sub_inst_valid_buf_IF1));

always @(posedge clk) begin
    if(reset) begin
        IF1_valid <= 1'b0;
        inst_en   <= 1'b0;
        sub_inst_valid_buf_IF1 <= 1'b0;
    end
    else if(pre_IF_ready_go & IF1_allowin)
    begin
        IF1_valid  <= 1'b1;
        inst_en    <= 1'b1;
        pc_buf_IF1 <= nextpc;
        sub_inst_valid_buf_IF1 <= sub_inst_valid;
    end
    else if(IF1_ready_go & IF2_allowin)
    begin
        IF1_valid <= 1'b0;
        sub_inst_valid_buf_IF1 <= 1'b0;
    end
    else if(br_taken | wb_ex | ertn_flush | tlb_remake)
    begin
        IF1_valid <= 1'b0;
        sub_inst_valid_buf_IF1 <= 1'b0;
    end
end

assign sub_inst_valid_IF1 = sub_inst_valid_buf_IF1 & ~(pred_buf_sel & pred_taken_IF1);

always @(posedge clk) begin
    if(reset | wb_ex | ertn_flush | tlb_remake | br_taken)
    begin
        IF2_valid <= 1'b0;
        sub_inst_valid_IF2 <= 1'b0;
    end
    else if(IF1_ready_go & IF2_allowin)
    begin
        IF2_valid <= IF1_valid ;
        pc_buf_IF2 <= pc_buf_IF1;
        sub_inst_valid_IF2 <= sub_inst_valid_IF1 ;

        pred_taken_IF2 <= pred_buf_sel & pred_taken_IF1;
        pred_target_IF2 <= pred_buf_sel ? pred_target_IF1 : pred_target_pre_IF;
        pred_pht_IF2 <= pred_buf_sel ? pred_pht_IF1 : pred_pht_pre_IF;
        pred_taken_IF2_2 <= pred_buf_sel & pred_taken_IF1_2 & sub_inst_valid_IF1;
        pred_target_IF2_2 <= pred_buf_sel ? pred_target_IF1_2 : pred_target_pre_IF_2;
        pred_pht2_IF2 <= pred_buf_sel ? pred_pht2_IF1 : pred_pht2_pre_IF;
    end
    else if(IF2_ready_go & ID_allowin)
    begin
        IF2_valid <= 1'b0;
        sub_inst_valid_IF2 <= 1'b0;
    end
end

reg         IF_inst_sel;
reg  [31:0] IF_inst_buf;
reg  [31:0] IF_inst2_buf;

always @(posedge clk) begin
    if(reset)
        IF_inst_sel <= 1'b0;
    else if(IF2_valid & ~ID_allowin & ~inst_stall & ~IF_inst_sel)
        IF_inst_sel <= 1'b1;
    else if(IF2_ready_go & ID_allowin)
        IF_inst_sel <= 1'b0;
end
always @(posedge clk) begin
    if(IF_inst_sel)
    begin
        IF_inst_buf <= IF_inst_buf;
        IF_inst2_buf <= IF_inst2_buf;
    end
    else
    begin
        IF_inst_buf <= inst_sram_rdata;
        IF_inst2_buf <= inst_sram_rdata2;
    end
end

assign IF_inst = IF_inst_sel ? IF_inst_buf : inst_sram_rdata;
assign IF_inst2 = IF_inst_sel ? IF_inst2_buf : inst_sram_rdata2;


    
endmodule
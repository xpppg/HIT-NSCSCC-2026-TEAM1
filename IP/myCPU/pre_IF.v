module pre_IF(
    input reset,
    input clk,
    input br_taken,
    input wire [31:0] br_target,
    input IF1_allowin,
    input pre_IF_ready_go,

    output reg [31:0] pc,
    output wire [31:0] nextpc,
    output sub_inst_valid,

    input wb_ex,
    input [31:0] ex_entry,
    input ertn_flush,
    input [31:0] ex_exit,
    input tlb_remake,
    input [31:0] tlb_entry,
    input pred_taken,
    input [31:0] pred_target
);
    wire [31:0] seq_pc;
    reg  [31:0] nextpc_buf;
    wire cross_line;
    reg  buf_sel;
    
    assign sub_inst_valid = ~(nextpc[5:2] == 4'hf);
    assign cross_line = (pc[5:2] == 4'hf);
    assign seq_pc       = cross_line ? (pc + 32'h4) : (pc + 32'h8);
    assign nextpc       = wb_ex ? ex_entry :
                          ertn_flush ? ex_exit :
                          tlb_remake ? tlb_entry :
                          br_taken ? br_target : 
                          pred_taken ? pred_target :
                          buf_sel ? nextpc_buf : seq_pc;

    always @(posedge clk) begin
    if (reset) begin
        pc <= 32'h1bfffffc;     //trick: to make nextpc be 0x1c000000 during reset 32'h1bfffffc
    end
    else if(pre_IF_ready_go & IF1_allowin) begin
        pc <= nextpc;
    end
    else begin
        pc <= pc;
    end
end
    always @(posedge clk) begin
        if (reset) begin
            nextpc_buf <= 32'h1bfffffc; 
            buf_sel <= 1'b0;
        end
        else if (~pre_IF_ready_go | ~IF1_allowin) begin
            nextpc_buf <= nextpc;
            buf_sel <= 1'b1;
        end
        else 
            buf_sel <= 1'b0;
    end
    
    
endmodule
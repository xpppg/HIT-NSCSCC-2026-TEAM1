module fetch_buffer(
    input wire clk,
    input wire flush,

    //write
    input wire wr,
    input wire [31:0] pc_buf_IF,
    input wire [31:0] IF_inst,
    input wire [32:0] if_pred_info,
    input wire [15:0] if_ex_info,

    input wire wr2,
    input wire [31:0] pc_buf_IF2,
    input wire [31:0] IF_inst2,
    input wire [32:0] if_pred_info_2,
    input wire [15:0] if_ex_info_2,
    
    output wire ID_allowin,

    //read
    input wire rd,
    output wire [31:0] pc_buf_ID,
    output wire [31:0] ID_inst,
    output wire [32:0] id_pred_info,
    output wire [15:0] id_ex_info,

    output wire ID_valid,

    input wire rd2,
    output wire [31:0] pc_buf_ID2,
    output wire [31:0] ID_inst2,
    output wire [32:0] id_pred_info_2,
    output wire [15:0] id_ex_info_2,

    output wire sub_ID_valid
);
//
wire pred_taken_IF;
wire [31:0] pred_target_IF;
wire wb_ex_IF;
wire [5:0] wb_ecode_IF;
wire [8:0] wb_esubcode_IF;
wire pred_taken_IF2;
wire [31:0] pred_target_IF2;
wire wb_ex_IF2;
wire [5:0] wb_ecode_IF2;
wire [8:0] wb_esubcode_IF2;
wire pred_taken_ID;
wire [31:0] pred_target_ID;
wire wb_ex_ID;
wire [5:0] wb_ecode_ID;
wire [8:0] wb_esubcode_ID;
wire pred_taken_ID2;
wire [31:0] pred_target_ID2;
wire wb_ex_ID2;
wire [5:0] wb_ecode_ID2;
wire [8:0] wb_esubcode_ID2;

assign {pred_taken_IF,pred_target_IF} = if_pred_info;
assign {wb_esubcode_IF,wb_ecode_IF,wb_ex_IF} = if_ex_info;
assign {pred_taken_IF2,pred_target_IF2} = if_pred_info_2;
assign {wb_esubcode_IF2,wb_ecode_IF2,wb_ex_IF2} = if_ex_info_2;


// real max_depth = 9
reg [31:0] pc[15:0];
reg [31:0] inst[15:0];
reg pred_taken[15:0];
reg [31:0] pred_target[15:0];
reg [15:0] wb_ex_buf;
reg [5:0] wb_ecode_buf[15:0];
reg [8:0] wb_esubcode_buf[15:0];
reg [15:0] valid;

reg [4:0] count;
reg [3:0] rd_ptr;
reg [3:0] wr_ptr;

wire full;//不可写

wire [4:0] wr_depth;
wire [4:0] rd_depth;

assign full = count[3];
assign ID_allowin = !full;
assign wr_depth =      full ? 5'd0 :
                 (wr & wr2) ? 5'd2 :
                       wr ? 5'd1 : 5'd0;
assign rd_depth = (rd & ID_valid & rd2 & sub_ID_valid) ? 5'd2 :
                                       (rd & ID_valid) ? 5'd1 : 5'd0;

always @(posedge clk) begin
    if(flush) begin
        count <= 5'd0;
    end
    else begin
        count <= count + wr_depth - rd_depth;
    end
end

always @(posedge clk) begin
    if(flush) begin
        wr_ptr <= 4'd0;
        wb_ex_buf[15:0] <= 16'b0;
    end
    else begin
        if(wr & !full) begin
            pc[wr_ptr] <= pc_buf_IF;
            inst[wr_ptr] <= IF_inst;
            pred_taken[wr_ptr] <= pred_taken_IF;
            pred_target[wr_ptr] <= pred_target_IF;
            wb_ex_buf[wr_ptr] <= wb_ex_IF;
            wb_ecode_buf[wr_ptr] <= wb_ecode_IF;
            wb_esubcode_buf[wr_ptr] <= wb_esubcode_IF;
            if(wr2) begin
                pc[wr_ptr + 4'd1] <= pc_buf_IF2;
                inst[wr_ptr + 4'd1] <= IF_inst2;
                pred_taken[wr_ptr + 4'd1] <= pred_taken_IF2;
                pred_target[wr_ptr + 4'd1] <= pred_target_IF2;
                wb_ex_buf[wr_ptr + 4'd1] <= wb_ex_IF2;
                wb_ecode_buf[wr_ptr + 4'd1] <= wb_ecode_IF2;
                wb_esubcode_buf[wr_ptr + 4'd1] <= wb_esubcode_IF2;
            end
            wr_ptr <= wr_ptr + (wr2 ? 4'd2 : 4'd1);
        end
    end
end

always @(posedge clk) begin
    if(flush) begin
        rd_ptr <= 4'd0;
    end
    else begin
        if(rd & ID_valid) begin
            if(rd2 & sub_ID_valid) begin
                rd_ptr <= rd_ptr + 4'd2;
            end
            else begin
                rd_ptr <= rd_ptr + 4'd1;
            end
        end
    end
end

always @(posedge clk) begin
    if(flush)
        valid[15:0] <= 16'b0;
    else begin
        if(rd & ID_valid) begin
            valid[rd_ptr] <= 1'b0;
            if(rd2 & sub_ID_valid) begin
                valid[rd_ptr + 4'd1] <= 1'b0;
            end
        end
        if(wr & !full) begin
            valid[wr_ptr] <= 1'b1;
            if(wr2) begin
                valid[wr_ptr + 4'd1] <= 1'b1;
            end
        end
    end
end

assign pc_buf_ID = pc[rd_ptr];
assign ID_inst = inst[rd_ptr];
assign pred_taken_ID = pred_taken[rd_ptr];
assign pred_target_ID = pred_target[rd_ptr];
assign wb_ex_ID = wb_ex_buf[rd_ptr];
assign wb_ecode_ID = wb_ecode_buf[rd_ptr];
assign wb_esubcode_ID = wb_esubcode_buf[rd_ptr];
assign id_pred_info = {pred_taken_ID, pred_target_ID};
assign id_ex_info = {wb_esubcode_ID, wb_ecode_ID, wb_ex_ID};

assign ID_valid = valid[rd_ptr];
assign pc_buf_ID2 = pc[rd_ptr + 4'd1];
assign ID_inst2 = inst[rd_ptr + 4'd1];

assign pred_taken_ID2 = pred_taken[rd_ptr + 4'd1];
assign pred_target_ID2 = pred_target[rd_ptr + 4'd1];
assign wb_ex_ID2 = wb_ex_buf[rd_ptr + 4'd1];
assign wb_ecode_ID2 = wb_ecode_buf[rd_ptr + 4'd1];
assign wb_esubcode_ID2 = wb_esubcode_buf[rd_ptr + 4'd1];
assign id_pred_info_2 = {pred_taken_ID2, pred_target_ID2};
assign id_ex_info_2 = {wb_esubcode_ID2, wb_ecode_ID2, wb_ex_ID2};

assign sub_ID_valid = valid[rd_ptr + 4'd1];



endmodule



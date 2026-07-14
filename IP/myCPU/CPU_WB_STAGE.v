module WB(
    input         clk,
    input         reset,

    input         cpu_stall,
    input         wb_ex,
    input         rf_we,
    input  [4:0]  rf_waddr,
    input  [31:0] rf_wdata,
    input         rf_we2,
    input  [4:0]  rf_waddr2,
    input  [31:0] rf_wdata2,
    input         rf_we_turning,
    input  [31:0] pc_buf_MEM,
    input  [31:0] pc_buf_MEM_2,

    output [31:0] debug_wb_pc,
    output [3:0]  debug_wb_rf_we,
    output [4:0]  debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata,
    output        WB_allowin
);
reg         WB_full;
reg  [31:0] WB_pc;
reg  [3:0]  WB_rf_we;
reg  [4:0]  WB_rf_wnum;
reg  [31:0] WB_rf_wdata;

always @(posedge clk) begin
    if (cpu_stall) begin
        if(wb_ex & rf_we2 & rf_we_turning)
        begin
            WB_rf_we <= 4'b1111;
            WB_rf_wnum <= rf_waddr2;
            WB_rf_wdata <= rf_wdata2;
            WB_pc <= pc_buf_MEM_2;
        end else begin
            WB_pc <= pc_buf_MEM;
            WB_rf_we <= 4'b0;
            WB_rf_wnum <= 5'b0;
            WB_rf_wdata <= 32'b0;
        end
    end
    else if (rf_we & rf_we2) 
    begin
        if(rf_we_turning & ~WB_full) begin
            WB_pc <= pc_buf_MEM_2;
            WB_rf_we <= 4'b1111;
            WB_rf_wnum <= rf_waddr2;
            WB_rf_wdata <= rf_wdata2;
        end
        else if (rf_we_turning & WB_full) begin
            WB_pc <= pc_buf_MEM;
            WB_rf_we <= 4'b1111;
            WB_rf_wnum <= rf_waddr;
            WB_rf_wdata <= rf_wdata;
        end
        else if (~rf_we_turning & ~WB_full) begin
            WB_pc <= pc_buf_MEM;
            WB_rf_we <= 4'b1111;
            WB_rf_wnum <= rf_waddr;
            WB_rf_wdata <= rf_wdata;
        end
        else if (~rf_we_turning & WB_full) begin
            WB_pc <= pc_buf_MEM_2;
            WB_rf_we <= 4'b1111;
            WB_rf_wnum <= rf_waddr2;
            WB_rf_wdata <= rf_wdata2;
        end
    end
    else if(rf_we) begin
        WB_pc <= pc_buf_MEM;
        WB_rf_we <= 4'b1111;
        WB_rf_wnum <= rf_waddr;
        WB_rf_wdata <= rf_wdata;
    end
    else if(rf_we2) begin
        WB_rf_we <= 4'b1111;
        WB_rf_wnum <= rf_waddr2;
        WB_rf_wdata <= rf_wdata2;
        if(rf_we_turning) begin
            WB_pc <= pc_buf_MEM_2;
        end
        else begin
            WB_pc <= pc_buf_MEM_2;
        end
    end
    else begin
        WB_pc <= pc_buf_MEM;
        WB_rf_we <= 4'b0;
        WB_rf_wnum <= 5'b0;
        WB_rf_wdata <= 32'b0;
    end
end

always @(posedge clk) begin
    if (reset) begin
        WB_full <= 1'b0;
    end
    else if (rf_we & rf_we2 & ~WB_full) begin
        WB_full <= 1'b1;
    end
    else if (rf_we & rf_we2 & WB_full) begin
        WB_full <= 1'b0;
    end
end

assign debug_wb_pc       = WB_pc;
assign debug_wb_rf_we    = WB_rf_we;
assign debug_wb_rf_wnum  = WB_rf_wnum;
assign debug_wb_rf_wdata = WB_rf_wdata;
assign WB_allowin  = ~(rf_we & rf_we2 & ~WB_full);

endmodule
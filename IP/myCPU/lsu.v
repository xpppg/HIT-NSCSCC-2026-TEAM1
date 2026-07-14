module lsu(//两周期访存
  //input  wire        clk,
  //input  wire        rst,
  //ex级
  input  wire        en,//load and store
  input  wire [ 9:0] op,
  input  wire [31:0] rj_value,
  input  wire [31:0] rd_value,
  input  wire [31:0] imm,
  input  wire        llbit,
  
  output wire        mem_en,
  output wire [31:0] mem_vaddr,
  output wire        mem_wr,//1:store,0:load
  output wire [ 2:0] mem_rsize,
  output wire [ 3:0] mem_wen,
  output wire [31:0] mem_wdata,
  output wire [ 4:0] ld_sel,
  //wb级
  input  wire [31:0] data_sram_rdata,
  input  wire [ 4:0] result_sel,
  input  wire [ 1:0] result_byte,
  output wire [31:0] lsu_result,

  output wire [15:0] ex_info
  `ifdef DIFFTEST_EN
  ,
  output wire [ 7:0] ex_inst_ld_en,
  output wire [ 7:0] ex_inst_st_en,
  output wire [31:0] ex_st_data
  `endif
);
wire inst_st_w;
wire inst_st_b;
wire inst_st_h;
wire inst_sc_w;
wire inst_ld_w;
wire inst_ld_b;
wire inst_ld_h;
wire inst_ld_bu;
wire inst_ld_hu;
wire inst_ll_w;
wire [3:0] byte_mask;
wire [3:0] half_mask;
wire [1:0] offset;

assign inst_st_w = op[0];
assign inst_st_b = op[1];
assign inst_st_h = op[2];
assign inst_sc_w = op[3];
assign inst_ld_w = op[4];
assign inst_ld_b = op[5];
assign inst_ld_h = op[6];
assign inst_ld_bu= op[7];
assign inst_ld_hu= op[8];
assign inst_ll_w = op[9];

assign mem_en = en & ~ex_info[0] & ~(inst_sc_w & ~llbit);//特定情况取消
assign mem_vaddr = rj_value + imm;
assign mem_wr = inst_st_w | inst_st_b | inst_st_h | (inst_sc_w & llbit) ;
assign mem_wdata = inst_st_b ? {4{rd_value[ 7:0]}} :
                   inst_st_h ? {2{rd_value[15:0]}} :
                                 {rd_value[31:0]};

assign offset = mem_vaddr[1:0];
assign byte_mask = (4'b0001 << offset);
assign half_mask = offset[1] ? 4'b1100 : 4'b0011;
assign mem_wen = ({4{inst_st_b}} & byte_mask) |
                          ({4{inst_st_h}} & half_mask) |
                          ({4{inst_st_w | inst_sc_w}} & 4'b1111);

assign mem_rsize[0] = inst_ld_h | inst_ld_hu;
assign mem_rsize[1] = inst_ld_w | inst_ll_w;
assign mem_rsize[2] = 1'b0;

assign ld_sel = (inst_ld_w | inst_ll_w) ? 5'b00001 :
                inst_ld_b  ? 5'b00010 :
               inst_ld_bu  ? 5'b00100 :
               inst_ld_h   ? 5'b01000 :
               inst_ld_hu  ? 5'b10000 :
               5'b00000;
//data process
wire [7:0] byte0;
wire [15:0] half0;
assign byte0   = data_sram_rdata[{result_byte, 3'b0} +: 8];
assign half0   = data_sram_rdata[{result_byte[1], 4'b0} +: 16];

assign lsu_result = result_sel[0] ? data_sram_rdata :
                    result_sel[1] ? {{24{byte0[7]}}, byte0} :
                    result_sel[2] ? {{24{1'b0}}, byte0} :
                    result_sel[3] ? {{16{half0[15]}}, half0} : 
                                    {{16{1'b0}}, half0};
//ex_info
wire ale_h;
wire ale_w;
wire ale_ex;
wire [5:0] ecode;
wire [8:0] esubcode;

assign ale_h = inst_ld_h | inst_ld_hu | inst_st_h;
assign ale_w = inst_ld_w | inst_ll_w | inst_st_w | (inst_sc_w & llbit);

assign ale_ex = (ale_h & mem_vaddr[0]) | (ale_w & (mem_vaddr[1:0] != 2'b00));

assign ecode = 6'h09;
assign esubcode = 9'h0;

assign ex_info = {esubcode, ecode, ale_ex};

`ifdef DIFFTEST_EN
assign ex_inst_ld_en =  {2'b0, inst_ll_w, inst_ld_w, inst_ld_hu, inst_ld_h, inst_ld_bu, inst_ld_b};
assign ex_inst_st_en =  {4'b0, llbit && inst_sc_w, inst_st_w, inst_st_h, inst_st_b};
assign ex_st_data = {{8{mem_wen[3]}} & mem_wdata[31:24] , 
                     {8{mem_wen[2]}} & mem_wdata[23:16] , 
                     {8{mem_wen[1]}} & mem_wdata[15: 8] , 
                     {8{mem_wen[0]}} & mem_wdata[ 7: 0]};
`endif



endmodule
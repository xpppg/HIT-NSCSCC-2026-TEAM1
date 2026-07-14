module peu(
  input  wire        en,
  input  wire [18:0] op,
  input  wire [31:0] rj_value,
  input  wire [31:0] rd_value,
  input  wire [31:0] csr_value,
  input  wire        llbit,

  output wire [ 9:0] peu2tlb_en,
  input  wire [31:0] tlbsrch_wmask,
  input  wire [31:0] tlbsrch_wvalue,
  //流水线
  output wire        ertn,
  output wire [31:0] peu_result,

  output wire [ 1:0] peu_csr_wen,
  output wire [31:0] peu_csr_wmask,
  output wire [31:0] peu_csr_wvalue,

  output wire [15:0] ex_info
`ifdef DIFFTEST_EN
    ,
    output wire is_CNTinst,
    output wire csr_rstat
`endif 
);
wire inst_csrrd;
wire inst_csrwr;
wire inst_csrxchg;
wire inst_rdcntid_w;
wire inst_rdcntvl_w;
wire inst_rdcntvh_w;
wire inst_tlbsrch;
wire inst_tlbrd;
wire inst_tlbwr;
wire inst_tlbfill;
wire inst_invtlb;
wire inst_ertn;
wire inst_ll_w;
wire inst_sc_w;
wire [4:0] invtlb_op;
wire inst_not_exist;

assign inst_csrrd = op[0];
assign inst_csrwr = op[1];
assign inst_csrxchg = op[2];
assign inst_rdcntid_w = op[3];
assign inst_rdcntvl_w = op[4];
assign inst_rdcntvh_w = op[5];
assign inst_tlbsrch = op[6];
assign inst_tlbrd = op[7];
assign inst_tlbwr = op[8];
assign inst_tlbfill = op[9];
assign inst_invtlb = op[10];
assign inst_ertn = op[11];
assign inst_ll_w = op[12];
assign inst_sc_w = op[13];
assign invtlb_op = op[18:14];

assign peu2tlb_en = {invtlb_op,inst_invtlb,inst_tlbfill,inst_tlbwr,inst_tlbrd,inst_tlbsrch} & {10{en}};//tlb操作指令

assign ertn = inst_ertn & en;

assign peu_result = inst_sc_w ? {31'b0, llbit} : csr_value;

assign peu_csr_wmask = inst_tlbsrch ? tlbsrch_wmask : 
                       inst_csrxchg ? rj_value : 32'hffffffff;
assign peu_csr_wvalue = inst_tlbsrch ? tlbsrch_wvalue : 
                           inst_ll_w ? 32'h1 :
                           (inst_sc_w & llbit) ? 32'h0 :
                           rd_value;
assign peu_csr_wen[0] = (inst_csrwr | inst_csrxchg | inst_ll_w | (inst_sc_w & llbit) | inst_tlbsrch) & en;//只写单个寄存器
assign peu_csr_wen[1] =  inst_tlbrd & en;//写多个寄存器

assign inst_not_exist = en & inst_invtlb & (invtlb_op[4] | invtlb_op[3] | invtlb_op[2] & invtlb_op[1] & invtlb_op[0]) ;//op操作码不存在 >6

assign ex_info = {9'h0,6'h0d,inst_not_exist};

`ifdef DIFFTEST_EN
assign is_CNTinst = inst_rdcntid_w | inst_rdcntvl_w | inst_rdcntvh_w;
assign csr_rstat = inst_csrrd | inst_csrwr | inst_csrxchg; 
`endif

endmodule
module mycpu_core(
    input  wire        clk,
    input  wire        resetn,
    input  wire [ 7:0] intrpt,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [31:0] inst_sram_addr,
    input  wire [31:0] inst_sram_rdata,
    input  wire [31:0] inst_sram_rdata2,
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_wen,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_waddr,
    output wire [ 2:0] data_sram_rsize,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    output wire        dcache_v,
    
    input  wire        fetch_stall,
    input  wire        cpu_stall,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    output wire [31:0] debug1_wb_pc,
    output wire [ 3:0] debug1_wb_rf_we,
    output wire [ 4:0] debug1_wb_rf_wnum,
    output wire [31:0] debug1_wb_rf_wdata
);
wire [31:0] debug_r1;

reg         reset;
reg         clk_rst;
wire        pht_rst;
always @(posedge clk) begin
    clk_rst <= ~resetn;
end

always @(posedge clk) begin
    reset <= clk_rst | pht_rst;
end

wire        inst_br;
wire        br_taken;
wire [31:0] br_target;
wire [ 1:0] br_pht;

wire [31:0] ID_inst;
wire [31:0] ID_inst2;
wire [31:0] IF_inst;
wire [31:0] IF_inst2;

wire        rf_we;
wire        rf_we2;
wire [31:0] rf_rdata1;
wire [31:0] rf_rdata2;
wire [31:0] rf_rdata3;
wire [31:0] rf_rdata4;

wire inst_en;

wire [31:0] rf_wdata;
wire [31:0] rf_wdata2;
wire [31:0] pc;
wire [31:0] nextpc;

wire [4:0] rf_waddr;
wire [4:0] rf_waddr2;

//TLB模块声明
// invtlb opcode
wire invtlb_valid;
wire [ 4:0] invtlb_op_ID;
reg  [ 4:0] invtlb_op_EXE;
wire [ 4:0] invtlb_op;
// write port

//TLB控制信号
wire tlb_remake;

//CSR模块声明
wire [14:0] csr_wnum;
wire csr_we;
wire csr_we2;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;
wire [31:0] ex_entry;
wire [31:0] ex_exit;
wire has_int;
wire ertn_flush;
wire wb_ex;
wire [5:0] wb_ecode;
wire [8:0] wb_esubcode;
wire [31:0] wb_pc;
wire [14:0] csr_num_ID;
wire csr_we_ID;

wire [31:0] csr_rovalue;
wire wb_ex_IF;
wire [5:0] wb_ecode_IF;
wire [8:0] wb_esubcode_IF;

wire tlb_ex;
wire inv_ex;
wire [5:0] wb_ecode_EXE;
wire [8:0] wb_esubcode_EXE;

`ifdef DIFFTEST_EN
wire [31:0] csr_crmd_diff;
wire [31:0] csr_prmd_diff;
wire [31:0] csr_ectl_diff;
wire [31:0] csr_estat_diff;
wire [31:0] csr_era_diff;
wire [31:0] csr_badv_diff;
wire [31:0] csr_eentry_diff;
wire [31:0] csr_tlbidx_diff;
wire [31:0] csr_tlbehi_diff;
wire [31:0] csr_tlbelo0_diff;
wire [31:0] csr_tlbelo1_diff;
wire [31:0] csr_asid_diff;
wire [31:0] csr_save0_diff;
wire [31:0] csr_save1_diff;
wire [31:0] csr_save2_diff;
wire [31:0] csr_save3_diff;
wire [31:0] csr_tid_diff;
wire [31:0] csr_tcfg_diff;
wire [31:0] csr_tval_diff;
wire [31:0] csr_ticlr_diff;
wire [31:0] csr_llbctl_diff;
wire [31:0] csr_tlbrentry_diff;
wire [31:0] csr_dmw0_diff;
wire [31:0] csr_dmw1_diff;
wire [31:0] csr_pgdl_diff;
wire [31:0] csr_pgdh_diff;
wire [63:0] csr_timer_64_diff;
wire [31:0] regs [31:0];

reg  [63:0] ex_timer_64;
reg  [63:0] wb_timer_64;
`endif
reg [5:0] wb_ecode_MEM_buf;
reg [8:0] wb_esubcode_MEM_buf;
wire [31:0] wb_vaddr;
wire [9:0] csr_asid;
wire [18:0] csr_vppn;
wire [31:0] tlbelo0_rvalue;
wire [31:0] tlbelo1_rvalue;
wire [31:0] tlbidx_rvalue;
wire car_tlbrd_valid;
wire [31:0] tlb_entry;
reg  [31:0] tlb_entry_EXE;
wire [31:0] tlb_entry_IS;
wire [5:0] csr_ecode;
wire wb_inv;
wire [31:0] csr_dmw0;
wire [31:0] csr_dmw1;
wire [31:0] csr_crmd;

reg  basic_int_IS;
reg  basic_int_IS_2;

//流水线控制信�?
wire pre_IF_ready_go;
wire IF1_ready_go;
wire IF2_ready_go;
wire ID_ready_go;
wire EXE_ready_go;
wire MEM_ready_go;
wire IS_ready_go;
wire IS_ready_go_2;
wire ID_ready_go_2;
wire EXE_ready_go_2;
wire MEM_ready_go_2;
wire WB_ready_go;
wire div_wating;
wire mul_wating;
wire sub_mul_wating;
wire mmu_wating;
wire pred_wating;
wire fetch_wating;
wire rf_we_wating;
wire rf_we_wating_2;
wire IF1_allowin;
wire IF2_allowin;
wire ID_allowin;
wire EXE_allowin;
wire MEM_allowin;
wire WB_allowin;
wire IS_allowin;
wire IS_allowin_single;
wire IF1_valid;
wire IF2_valid;
wire ID_valid;
wire sub_ID_valid;
reg EXE_valid;
reg MEM_valid;
reg WB_valid;
reg IS_valid;
reg sub_IS_valid;
reg  sub_EXE_valid;
reg  sub_MEM_valid;

//TLB异常相关
wire wb_tlbr0;
wire wb_tlbr1;
wire wb_pil;
wire wb_pis;
wire wb_pif;
wire wb_pme;
wire wb_ppi0;
wire wb_ppi1;
reg wb_tlbr0_IF2;
reg wb_ppi0_IF2;
reg wb_pif_IF2;
reg wb_tlbr0_IF1;
reg wb_ppi0_IF1;
reg wb_pif_IF1;
//IS级缓�?
reg [31:0] pc_buf_MEM;
reg [31:0] pc_buf_MEM_2;
reg [31:0] pc_buf_IS;
reg [31:0] pc_buf_IS_2;
reg [31:0] pc_buf_EXE;
reg [31:0] pc_buf_EXE_2;

//sub流水�?
wire [31:0] br_pc;
wire EXE_forward_ok;
wire [31:0] EXE_forward_result;
wire EXE_forward_ok_2;
wire [31:0] EXE_forward_result_2;

//阻塞逻辑判断
assign pre_IF_ready_go = ~fetch_stall ;
assign IF1_ready_go =  ~fetch_stall & ~fetch_wating & ~pred_wating;
assign IF2_ready_go = ~fetch_stall;

assign ID_ready_go =  ~cpu_stall & ~peu_wating3;
assign IS_ready_go =  ~cpu_stall & ~rf_we_wating & ~peu_wating;
assign EXE_ready_go = ~div_wating & ~sub_div_wating & ~cpu_stall & ~mmu_wating & ~wr_buf_wating & ~mul_wating & ~sub_mul_wating;
assign MEM_ready_go = ~cpu_stall;
assign WB_ready_go  = 1'b1;

assign ID_ready_go_2 = ~cpu_stall & ~peu_wating3;
assign IS_ready_go_2 = ~cpu_stall & ~inst_waiting & ~is_raw_wating & ~rf_we_wating_2 & ~peu_wating2;

assign IF1_allowin = (IF1_ready_go & IF2_allowin) | ~IF1_valid;
assign IF2_allowin = (IF2_ready_go & ID_allowin) | ~IF2_valid;
//assign ID_allowin = (ID_ready_go & ID_ready_go_2 & IS_allowin) | ~ID_valid & ~sub_ID_valid;
assign IS_allowin = (IS_ready_go & IS_ready_go_2 & EXE_allowin) | ~IS_valid & ~sub_IS_valid;//均可进入
assign IS_allowin_single = (IS_ready_go & EXE_allowin) | ~sub_IS_valid;//表示至少第二槽可进入
assign EXE_allowin = (EXE_ready_go & MEM_allowin) | ~EXE_valid & ~sub_EXE_valid;
assign MEM_allowin = (MEM_ready_go & WB_allowin) | ~MEM_valid & ~sub_MEM_valid;

assign rf_we_wating = (is_r1 == ex_dest & ex_dest_we & EXE_valid & ~(ex_dest_from[0] & EXE_forward_ok)) |
                      (is_r2 == ex_dest & ex_dest_we & EXE_valid & ~(ex_dest_from[0] & EXE_forward_ok)) |
                      (is_r1 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ~(ex_dest_from_2[0] & EXE_forward_ok_2)) |
                      (is_r2 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ~(ex_dest_from_2[0] & EXE_forward_ok_2)) ;

assign rf_we_wating_2 = (is_r1 == ex_dest & ex_dest_we & EXE_valid & ~(ex_dest_from[0] & EXE_forward_ok)) |
                      (is_r2 == ex_dest & ex_dest_we & EXE_valid & ~(ex_dest_from[0] & EXE_forward_ok)) |
                      (is_r3 == ex_dest & ex_dest_we & EXE_valid & ~(ex_dest_from[0] & EXE_forward_ok)) |
                      (is_r4 == ex_dest & ex_dest_we & EXE_valid & ~(ex_dest_from[0] & EXE_forward_ok)) |
                      (is_r1 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ~(ex_dest_from_2[0] & EXE_forward_ok_2)) |
                      (is_r2 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ~(ex_dest_from_2[0] & EXE_forward_ok_2)) |
                      (is_r3 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ~(ex_dest_from_2[0] & EXE_forward_ok_2)) |
                      (is_r4 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ~(ex_dest_from_2[0] & EXE_forward_ok_2)) ;
wire flush;

assign flush = wb_ex | ertn_flush | tlb_remake;

wire sub_inst_valid;
wire sub_inst_valid_IF2;
wire [31:0] pc_buf_IF1;
wire [31:0] pc_buf_IF2;
wire pred_taken;
wire pred_taken_pre_IF;
wire pred_taken_IF2;
reg  pred_taken_IS;
wire pred_taken_pre_IF_2;
wire pred_taken_IF2_2;
wire [1:0] pred_pht_pre_IF;
wire [1:0] pred_pht2_pre_IF;
wire [1:0] pred_pht_IF2;
wire [1:0] pred_pht2_IF2;
wire [31:0] pred_target;
wire [31:0] pred_target_pre_IF;
wire [31:0] pred_target_IF2;
wire [31:0] pred_target_pre_IF_2;
wire [31:0] pred_target_IF2_2;
wire actual_taken;
wire [31:0] actual_target;
wire call;
wire [31:0] call_target;
wire ret;
wire ret_wrong;

wire BPU_rst;


reg [31:0] IS_inst;
reg [31:0] IS_inst2;
reg [31:0] EXE_inst;
reg [31:0] EXE_inst2;
reg [31:0] MEM_inst;
reg [31:0] MEM_inst2;
`ifdef DIFFTEST_EN
wire tlb_fill;
wire [3:0] tlb_fill_index;
wire ex_is_CNTinst;
reg wb_is_CNTinst;
wire ex_csr_rstat;
reg wb_csr_rstat;
wire [7:0] ex_inst_ld_en;
wire [7:0] ex_inst_st_en;
wire [31:0] ex_st_data;
reg [7:0] wb_inst_ld_en;
reg [7:0] wb_inst_st_en;
reg [31:0] wb_lsu_vaddr;
reg [31:0] wb_lsu_paddr;
reg [31:0] wb_st_data;
`endif 


pre_IF u_pre_IF(
    .reset    (reset   ),
    .clk      (clk     ),
    .br_taken (br_taken),
    .br_target(br_target),
    .IF1_allowin(IF1_allowin),
    .pre_IF_ready_go(pre_IF_ready_go),

    .pc       (pc      ),
    .nextpc   (nextpc  ),
    .sub_inst_valid(sub_inst_valid),

    .wb_ex    (wb_ex   ),
    .ex_entry (ex_entry),
    .ertn_flush(ertn_flush),
    .ex_exit  (ex_exit ),
    .tlb_remake(tlb_remake),
    .tlb_entry(tlb_entry),
    .pred_taken(pred_taken),
    .pred_target(pred_target)
);

assign BPU_rst = reset | wb_ex | ertn_flush;

BPU u_BPU(
    .clk           (clk),
    .rst           (BPU_rst),
    .clk_rst       (clk_rst),
    .pht_rst       (pht_rst),
    // read port
    .pc            (nextpc),
    .pred_target   (pred_target_pre_IF),
    .pred_hit1     (pred_taken_pre_IF),
    .pred_pht      (pred_pht_pre_IF),

    .pc2           ({nextpc[31:6],{nextpc[5:0]+4'h4}}),//nextpc + 32'h4
    .pred_target_2 (pred_target_pre_IF_2),
    .pred_hit2     (pred_taken_pre_IF_2),
    .pred_pht2     (pred_pht2_pre_IF),
    // write port  
    .br_pc         (pc_buf_MEM),
    .br_target     (actual_target),
    .br_pht        (br_pht),
    .inst_br       (wb_inst_br & MEM_valid),
    .actual_taken  (wb_actual_taken & MEM_valid),
    .call          (call),
    .call_target   (call_target),
    .ret           (ret),
    .ret_wrong     (ret_wrong)
);

IF u_IF(
    .clk          (clk         ),
    .reset        (reset       ),
    .br_taken     (br_taken    ),
    .wb_ex        (wb_ex       ),
    .ertn_flush   (ertn_flush  ),
    .tlb_remake   (tlb_remake  ),

    .pre_IF_ready_go (pre_IF_ready_go),
    .IF1_allowin   (IF1_allowin  ),
    .IF1_ready_go  (IF1_ready_go ),
    .IF2_allowin   (IF2_allowin  ),
    .IF2_ready_go  (IF2_ready_go ),
    .ID_allowin    (ID_allowin   ),

    .nextpc       (nextpc      ),
    .sub_inst_valid(sub_inst_valid),
    .pred_taken_pre_IF_in (pred_taken_pre_IF),
    .pred_target_pre_IF_in (pred_target_pre_IF),
    .pred_pht_pre_IF_in (pred_pht_pre_IF),
    .pred_taken_pre_IF_2_in (pred_taken_pre_IF_2),
    .pred_target_pre_IF_2_in (pred_target_pre_IF_2),
    .pred_pht2_pre_IF_in (pred_pht2_pre_IF),

    .inst_sram_en (inst_sram_en),
    .inst_stall   (fetch_stall   ),
    .inst_sram_rdata (inst_sram_rdata),
    .inst_sram_rdata2 (inst_sram_rdata2),

    .IF1_valid    (IF1_valid   ),
    .inst_en      (inst_en     ),
    .pc_buf_IF1   (pc_buf_IF1  ),
    
    .IF2_valid    (IF2_valid   ),
    .sub_inst_valid_IF2 (sub_inst_valid_IF2),
    .pc_buf_IF2   (pc_buf_IF2  ),
    .IF_inst      (IF_inst     ),
    .IF_inst2     (IF_inst2    ),
    .pred_taken_IF2 (pred_taken_IF2),
    .pred_target_IF2 (pred_target_IF2),
    .pred_pht_IF2 (pred_pht_IF2),
    .pred_taken_IF2_2 (pred_taken_IF2_2),
    .pred_target_IF2_2 (pred_target_IF2_2),
    .pred_pht2_IF2 (pred_pht2_IF2),

    .pred_taken   (pred_taken  ),
    .pred_target  (pred_target ),
    .pred_wating  (pred_wating )
);

//ID级流水线缓存
wire [31:0] pc_buf_ID;
wire [31:0] pc_buf_ID2;
wire [34:0] id_pred_info;
wire [34:0] id_pred_info_2;
wire [15:0] id_ex_info_buf;
wire [15:0] id_ex_info_buf_2;

fetch_buffer fetch_buffer(
    .clk(clk),
    .flush(reset | wb_ex | ertn_flush | tlb_remake | br_taken),
    //write
    .wr(IF2_ready_go & IF2_valid),
    .pc_buf_IF(pc_buf_IF2  ),
    .IF_inst   (IF_inst     ),
    .if_pred_info({pred_pht_IF2, pred_taken_IF2, pred_target_IF2}),
    .if_ex_info({wb_esubcode_IF, wb_ecode_IF, wb_ex_IF}),

    .wr2(IF2_ready_go & IF2_valid & sub_inst_valid_IF2),
    .pc_buf_IF2(pc_buf_IF2 + 32'h4),
    .IF_inst2   (IF_inst2     ),
    .if_pred_info_2({pred_pht2_IF2, pred_taken_IF2_2, pred_target_IF2_2}),
    .if_ex_info_2(16'b0),

    .ID_allowin(ID_allowin),
    //read
    .rd(ID_ready_go & IS_allowin_single),
    .pc_buf_ID(pc_buf_ID  ),
    .ID_inst   (ID_inst     ),
    .id_pred_info(id_pred_info),
    .id_ex_info(id_ex_info_buf),
    .ID_valid(ID_valid),

    .rd2(ID_ready_go_2 & IS_allowin),
    .pc_buf_ID2(pc_buf_ID2  ),
    .ID_inst2   (ID_inst2     ),
    .id_pred_info_2(id_pred_info_2),
    .id_ex_info_2(id_ex_info_buf_2),
    .sub_ID_valid(sub_ID_valid)
);

wire csr_ll_w;
wire ll_w_ID;
wire ll_w_ID_2;
wire llbit;
wire [4:0] id_r1;
wire [4:0] id_r2;
wire [4:0] id_r3;
wire [4:0] id_r4;
wire id_r1_sel;
wire id_r2_sel;
wire id_r3_sel;
wire id_r4_sel;
wire [31:0] id_imm1;
wire [31:0] id_imm2;
wire [31:0] id_imm3;
wire [31:0] id_imm4;
wire [18:0] id_alu_op;
wire [18:0] id_alu_op_2;
wire [10:0] id_bru_op;
wire [10:0] id_bru_op_2;
wire [31:0] id_bru_imm;
wire [31:0] id_bru_imm_2;
wire [ 9:0] id_lsu_op;
wire [ 9:0] id_lsu_op_2;
wire [18:0] id_peu_op;
wire [18:0] id_peu_op_2;
wire [ 3:0] id_ctrl_en;
wire [ 3:0] id_ctrl_en_2;
wire [ 4:0] id_dest;
wire [ 4:0] id_dest_2;
wire        id_dest_we;
wire        id_dest_we_2;
wire [ 2:0] id_dest_from;
wire [ 2:0] id_dest_from_2;
wire [14:0] id_csr_num;
wire [14:0] id_csr_num_2;
wire        id_csr_we;
wire        id_csr_we_2;
wire [15:0] id_ex_info;
wire [15:0] id_ex_info_2;
wire        id_inst_normal;
wire        id_inst_normal_2;
reg [4:0] is_r1;
reg [4:0] is_r2;
reg [4:0] is_r3;
reg [4:0] is_r4;
reg is_r1_sel;
reg is_r2_sel;
reg is_r3_sel;
reg is_r4_sel;
reg [31:0] is_imm1;
reg [31:0] is_imm2;
reg [31:0] is_imm3;
reg [31:0] is_imm4;
reg [18:0] is_alu_op;
reg [18:0] is_alu_op_2;
reg [10:0] is_bru_op;
reg [10:0] is_bru_op_2;
reg [31:0] is_bru_imm;
reg [31:0] is_bru_imm_2;
reg [ 9:0] is_lsu_op;
reg [ 9:0] is_lsu_op_2;
reg [18:0] is_peu_op;
reg [18:0] is_peu_op_2;
reg [ 3:0] is_ctrl_en;
reg [ 3:0] is_ctrl_en_2;
reg [ 4:0] is_dest;
reg [ 4:0] is_dest_2;
reg        is_dest_we;
reg        is_dest_we_2;
reg [ 2:0] is_dest_from;
reg [ 2:0] is_dest_from_2;
reg [14:0] is_csr_num;
reg [14:0] is_csr_num_2;
reg        is_csr_we;
reg        is_csr_we_2;
reg [15:0] is_ex_info;
reg [15:0] is_ex_info_2;
reg        is_inst_normal;
reg        is_inst_normal_2;
//buf
reg [15:0] is_ex_info_buf;
reg [15:0] is_ex_info_buf_2;
reg [34:0] is_pred_info;
reg [34:0] is_pred_info_2;

wire [31:0] is_csr_rvalue;
wire [31:0] is_csr_rvalue_2;

ID u_ID1(
    .inst         (ID_inst                 ),
    .pc           (pc_buf_ID               ),
    .has_int      (has_int                 ),
    .valid        (ID_valid & ~br_taken    ),
    
    .r1           (id_r1                   ),
    .r2           (id_r2                   ),
    .r1_sel       (id_r1_sel               ),
    .r2_sel       (id_r2_sel               ),
    .imm1         (id_imm1                 ),
    .imm2         (id_imm2                 ),
    .alu_op       (id_alu_op               ),
    .bru_op       (id_bru_op               ),
    .bru_imm      (id_bru_imm              ),
    .lsu_op       (id_lsu_op               ),
    .peu_op       (id_peu_op               ),
    .ctrl_en      (id_ctrl_en              ),
    .dest         (id_dest                 ),
    .dest_we      (id_dest_we              ),
    .dest_from    (id_dest_from            ),
    .csr_num      (id_csr_num              ),
    .csr_we       (id_csr_we               ),
    .ex_info      (id_ex_info              ),
    .inst_normal  (id_inst_normal          )
);

ID u_ID2(
    .inst         (ID_inst2                ),
    .pc           (pc_buf_ID2              ),
    .has_int      (has_int                 ),
    .valid        (sub_ID_valid & ~br_taken),

    .r1           (id_r3                   ),
    .r2           (id_r4                   ),
    .r1_sel       (id_r3_sel               ),
    .r2_sel       (id_r4_sel               ),
    .imm1         (id_imm3                 ),
    .imm2         (id_imm4                 ),
    .alu_op       (id_alu_op_2             ),
    .bru_op       (id_bru_op_2             ),
    .bru_imm      (id_bru_imm_2            ),
    .lsu_op       (id_lsu_op_2             ),
    .peu_op       (id_peu_op_2             ),
    .ctrl_en      (id_ctrl_en_2            ),
    .dest         (id_dest_2               ),
    .dest_we      (id_dest_we_2            ),
    .dest_from    (id_dest_from_2          ),
    .csr_num      (id_csr_num_2            ),
    .csr_we       (id_csr_we_2             ),
    .ex_info      (id_ex_info_2            ),
    .inst_normal  (id_inst_normal_2        )
);


always @(posedge clk) begin
    if(reset | wb_ex | ertn_flush | tlb_remake | br_taken) begin
        IS_valid                 <= 1'b0;
        is_ex_info_buf           <= 16'b0;
    end
    else if(ID_ready_go) begin
        if(IS_allowin) begin
            IS_valid                 <= ID_valid;
            is_ex_info_buf           <= id_ex_info_buf[0] ? id_ex_info_buf : id_ex_info;

            is_r1                    <= id_r1;
            is_r2                    <= id_r2;
            is_r1_sel                <= id_r1_sel;
            is_r2_sel                <= id_r2_sel;
            is_imm1                  <= id_imm1;
            is_imm2                  <= id_imm2;
            is_bru_imm               <= id_bru_imm;
            is_alu_op                <= id_alu_op;
            is_bru_op                <= id_bru_op;
            is_lsu_op                <= id_lsu_op;
            is_peu_op                <= id_peu_op;
            is_ctrl_en               <= id_ctrl_en;
            is_dest                  <= id_dest;
            is_dest_we               <= id_dest_we;
            is_dest_from             <= id_dest_from;
            is_csr_num               <= id_csr_num;
            is_csr_we                <= id_csr_we;
            is_inst_normal           <= id_inst_normal & ~(id_ex_info_buf[0] | id_ex_info[0]) & ~id_pred_info[32];

            pc_buf_IS                <= pc_buf_ID;
            IS_inst                  <= ID_inst;
            is_pred_info             <= id_pred_info;
        end else if(IS_ready_go & EXE_allowin) begin
            IS_valid                 <= sub_IS_valid;
            is_ex_info_buf           <= is_ex_info_buf_2;

            is_r1                    <= is_r3;
            is_r2                    <= is_r4;
            is_r1_sel                <= is_r3_sel;
            is_r2_sel                <= is_r4_sel;
            is_imm1                  <= is_imm3;
            is_imm2                  <= is_imm4;
            is_bru_imm               <= is_bru_imm_2;
            is_alu_op                <= is_alu_op_2;
            is_bru_op                <= is_bru_op_2;
            is_lsu_op                <= is_lsu_op_2;
            is_peu_op                <= is_peu_op_2;
            is_ctrl_en               <= is_ctrl_en_2;
            is_dest                  <= is_dest_2;
            is_dest_we               <= is_dest_we_2;
            is_dest_from             <= is_dest_from_2;
            is_csr_num               <= is_csr_num_2;
            is_csr_we                <= is_csr_we_2;
            is_inst_normal           <= is_inst_normal_2;

            pc_buf_IS                <= pc_buf_IS_2;
            IS_inst                  <= IS_inst2;
            is_pred_info             <= is_pred_info_2;
        end
    end else if(IS_ready_go & EXE_allowin) begin
        IS_valid <= 1'b0;
    end
end

always @(posedge clk) begin
    if(reset | wb_ex | ertn_flush | tlb_remake | br_taken) begin
        sub_IS_valid             <= 1'b0;
        is_ex_info_buf_2         <= 16'b0;
    end
    else if(ID_ready_go_2 & IS_allowin) begin
        sub_IS_valid             <= sub_ID_valid;
        is_ex_info_buf_2         <= id_ex_info_buf_2[0] ? id_ex_info_buf_2 : id_ex_info_2;

        is_r3                    <= id_r3;
        is_r4                    <= id_r4;
        is_r3_sel                <= id_r3_sel;
        is_r4_sel                <= id_r4_sel;
        is_imm3                  <= id_imm3;
        is_imm4                  <= id_imm4;
        is_bru_imm_2             <= id_bru_imm_2;
        is_alu_op_2              <= id_alu_op_2;
        is_bru_op_2              <= id_bru_op_2;
        is_lsu_op_2              <= id_lsu_op_2;
        is_peu_op_2              <= id_peu_op_2;
        is_ctrl_en_2             <= id_ctrl_en_2;
        is_dest_2                <= id_dest_2;
        is_dest_we_2             <= id_dest_we_2;
        is_dest_from_2           <= id_dest_from_2;
        is_csr_num_2             <= id_csr_num_2;
        is_csr_we_2              <= id_csr_we_2;
        is_inst_normal_2         <= id_inst_normal_2 & ~(id_ex_info_buf_2[0] | id_ex_info_2[0]) & ~id_pred_info_2[32];

        pc_buf_IS_2              <= pc_buf_ID2;
        IS_inst2                 <= ID_inst2;
        is_pred_info_2           <= id_pred_info_2;
    end else if(ID_ready_go & IS_allowin_single) begin
        sub_IS_valid             <= ID_valid;
        is_ex_info_buf_2         <= id_ex_info_buf[0] ? id_ex_info_buf : id_ex_info;

        is_r3                    <= id_r1;
        is_r4                    <= id_r2;
        is_r3_sel                <= id_r1_sel;
        is_r4_sel                <= id_r2_sel;
        is_imm3                  <= id_imm1;
        is_imm4                  <= id_imm2;
        is_bru_imm_2             <= id_bru_imm;
        is_alu_op_2              <= id_alu_op;
        is_bru_op_2              <= id_bru_op;
        is_lsu_op_2              <= id_lsu_op;
        is_peu_op_2              <= id_peu_op;
        is_ctrl_en_2             <= id_ctrl_en;
        is_dest_2                <= id_dest;
        is_dest_we_2             <= id_dest_we;
        is_dest_from_2           <= id_dest_from;
        is_csr_num_2             <= id_csr_num;
        is_csr_we_2              <= id_csr_we;
        is_inst_normal_2         <= id_inst_normal & ~(id_ex_info_buf[0] | id_ex_info[0]) & ~id_pred_info[32];

        pc_buf_IS_2              <= pc_buf_ID;
        IS_inst2                 <= ID_inst;
        is_pred_info_2           <= id_pred_info;
    end
    else if(IS_ready_go_2 & EXE_allowin) begin
        sub_IS_valid <= 1'b0;
    end
end

wire [31:0] rf_rdata1_out;
wire [31:0] rf_rdata2_out;
wire [31:0] rf_rdata3_out;
wire [31:0] rf_rdata4_out;

regfile u_regfile(
    .clk         (clk          ),
    
    .raddr1      (is_r1        ),
    .rdata1      (rf_rdata1_out    ),
    
    .raddr2      (is_r2        ),
    .rdata2      (rf_rdata2_out    ),
    
    .raddr3      (is_r3        ),
    .rdata3      (rf_rdata3_out    ),
    
    .raddr4      (is_r4        ),
    .rdata4      (rf_rdata4_out    ),
    
    .we1         (rf_we        ),
    .waddr1      (rf_waddr     ),
    .wdata1      (rf_wdata     ),

    .we2         (rf_we2       ),
    .waddr2      (rf_waddr2    ),
    .wdata2      (rf_wdata2    ),

    .turning     (rf_we_turning )
`ifdef DIFFTEST_EN
    ,
    .rf_o        (regs         )
`endif
);

assign rf_rdata1 = (is_r1 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ex_turning) ? EXE_forward_result :
                   (is_r1 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ex_dest_from_2[0] & EXE_forward_ok_2) ? EXE_forward_result_2 :
                   (is_r1 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ~ex_turning) ? EXE_forward_result :
                   ~rf_we_turning ? (is_r1 == rf_waddr2 & rf_we2) ? rf_wdata2 : 
                   (is_r1 == rf_waddr  & rf_we) ? rf_wdata : rf_rdata1_out : 
                   (is_r1 == rf_waddr & rf_we ) ? rf_wdata :
                   (is_r1 == rf_waddr2  & rf_we2) ? rf_wdata2 : rf_rdata1_out;
assign rf_rdata2 = (is_r2 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ex_turning) ? EXE_forward_result :
                   (is_r2 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ex_dest_from_2[0] & EXE_forward_ok_2) ? EXE_forward_result_2 :
                   (is_r2 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ~ex_turning) ? EXE_forward_result :
                   ~rf_we_turning ? (is_r2 == rf_waddr2 & rf_we2) ? rf_wdata2 : 
                   (is_r2 == rf_waddr  & rf_we) ? rf_wdata : rf_rdata2_out : 
                   (is_r2 == rf_waddr & rf_we ) ? rf_wdata :
                   (is_r2 == rf_waddr2  & rf_we2) ? rf_wdata2 : rf_rdata2_out;
assign rf_rdata3 = (is_r3 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ex_turning) ? EXE_forward_result :
                   (is_r3 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ex_dest_from_2[0] & EXE_forward_ok_2) ? EXE_forward_result_2 :
                   (is_r3 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ~ex_turning) ? EXE_forward_result :
                   ~rf_we_turning ? (is_r3 == rf_waddr2 & rf_we2) ? rf_wdata2 : 
                   (is_r3 == rf_waddr  & rf_we) ? rf_wdata : rf_rdata3_out : 
                   (is_r3 == rf_waddr & rf_we ) ? rf_wdata :
                   (is_r3 == rf_waddr2  & rf_we2) ? rf_wdata2 : rf_rdata3_out;
assign rf_rdata4 = (is_r4 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ex_turning) ? EXE_forward_result :
                   (is_r4 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ex_dest_from_2[0] & EXE_forward_ok_2) ? EXE_forward_result_2 :
                   (is_r4 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ~ex_turning) ? EXE_forward_result :
                   ~rf_we_turning ? (is_r4 == rf_waddr2 & rf_we2) ? rf_wdata2 : 
                   (is_r4 == rf_waddr  & rf_we) ? rf_wdata : rf_rdata4_out : 
                   (is_r4 == rf_waddr & rf_we ) ? rf_wdata :
                   (is_r4 == rf_waddr2  & rf_we2) ? rf_wdata2 : rf_rdata4_out;
/*assign rf_rdata4 = (is_r4 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ~ex_turning) ? EXE_forward_result :
                   (is_r4 == ex_dest_2 & ex_dest_we_2 & sub_EXE_valid & ex_dest_from_2[0] & EXE_forward_ok_2) ? EXE_forward_result_2 :
                   (is_r4 == ex_dest & ex_dest_we & EXE_valid & ex_dest_from[0] & EXE_forward_ok & ex_turning) ? EXE_forward_result :
                   (is_r4 == rf_waddr  & rf_we  & ~rf_we_turning) ? rf_wdata :
                   (is_r4 == rf_waddr2 & rf_we2 ) ? rf_wdata2 :
                   (is_r4 == rf_waddr  & rf_we  & rf_we_turning ) ? rf_wdata : rf_rdata4_out;*/


wire IS_to_EXE_inst;
wire inst_waiting;
wire is_raw_wating;
wire peu_wating;
wire peu_wating2;
wire peu_wating3;

assign IS_to_EXE_inst = ((is_inst_normal & ~is_inst_normal_2) | ~IS_valid) & sub_IS_valid; //0为第0条指令，1为第1条指�?
assign inst_waiting = (~is_inst_normal & ~is_inst_normal_2) & IS_valid & sub_IS_valid;//结构冲突
assign is_raw_wating = (is_dest == is_r3 | is_dest == is_r4) & is_dest_we & IS_valid;//同级（IS）数据冲�?
assign peu_wating = ex_csr_we & EXE_valid | wb_csr_we & MEM_valid;
assign peu_wating2 = is_csr_we & IS_valid | ex_csr_we & EXE_valid | wb_csr_we & MEM_valid;
assign peu_wating3 = is_csr_we_2 & sub_IS_valid | is_csr_we & IS_valid | ex_csr_we & EXE_valid | wb_csr_we & MEM_valid;

wire [31:0] is_src1;
wire [31:0] is_src2;
wire [31:0] is_src3;
wire [31:0] is_src4;
assign is_src1 = is_r1_sel ? rf_rdata1 : is_imm1;
assign is_src2 = is_r2_sel ? rf_rdata2 : is_imm2;
assign is_src3 = is_r3_sel ? rf_rdata3 : is_imm3;
assign is_src4 = is_r4_sel ? rf_rdata4 : is_imm4;


reg ex_r1_sel;
reg ex_r2_sel;
reg ex_r3_sel;
reg ex_r4_sel;
wire [31:0] ex_alu_src1;
wire [31:0] ex_alu_src2;
reg [18:0] ex_alu_op;
wire [31:0] ex_alu_src3;
wire [31:0] ex_alu_src4;
reg [18:0] ex_alu_op_2;
reg [31:0] ex_lsu_imm;
reg [31:0] ex_bru_imm;
reg [10:0] ex_bru_op;
reg [31:0] ex_rj_value;
reg [31:0] ex_rd_value;
reg [31:0] ex_rj_value_2;
reg [31:0] ex_rd_value_2;
reg [31:0] ex_imm1;
reg [31:0] ex_imm2;
reg [31:0] ex_imm3;
reg [31:0] ex_imm4;
reg [ 9:0] ex_lsu_op;
reg [18:0] ex_peu_op;
reg [ 3:0] ex_ctrl_en;
reg [ 4:0] ex_dest;
reg        ex_dest_we;
reg [ 2:0] ex_dest_from;
reg [ 4:0] ex_dest_2;
reg        ex_dest_we_2;
reg [ 2:0] ex_dest_from_2;
reg [14:0] ex_csr_num;
reg        ex_csr_we;
reg [15:0] ex_ex_info_buf;
reg        ex_turning;

reg [34:0] ex_pred_info;

wire        ex_mmu_en;
wire [31:0] ex_mem_vaddr;
wire [31:0] ex_mem_paddr;
wire        ex_mem_en;
wire        ex_mem_wr;
wire [ 2:0] ex_mem_rsize;
wire [ 3:0] ex_mem_wen;
wire [31:0] ex_mem_wdata;
wire [ 4:0] ex_ld_sel;
wire        ex_dcache_v;

wire [31:0] ex_alu_result;
wire [31:0] ex_alu_result_2;

reg  [31:0] ex_csr_rvalue;
wire [ 9:0] ex_peu2tlb_en;
wire [31:0] ex_tlbsrch_wmask;
wire [31:0] ex_tlbsrch_wdata;
wire [137:0] ex_tlb2csr_wvalue;
wire ex_ertn;
wire [31:0] ex_peu_result;
wire [ 1:0] ex_csr_wen;
wire [31:0] ex_csr_wmask;
wire [31:0] ex_csr_wvalue;
wire [15:0] ex_lsu_ex_info;
wire [15:0] ex_peu_ex_info;
wire [15:0] ex_mmu_ex_info;
wire        ex_inst_br;
wire        ex_br_taken;
wire [31:0] ex_br_target;
wire [ 1:0] ex_br_pht;
wire        ex_actual_taken;
wire [31:0] ex_actual_target;
wire        ex_call;
wire        ex_ret;
wire        ex_ret_wrong;
wire [31:0] ex_call_target;

//EXE阶段流水线缓存
always @(posedge clk) begin
    if(reset | wb_ex | ertn_flush | tlb_remake | br_taken) begin
        EXE_valid                <= 1'b0;
        ex_ex_info_buf           <= 16'b0;
    end
    else if(IS_ready_go & EXE_allowin & ~IS_to_EXE_inst) begin
        EXE_valid                <= IS_valid;
        ex_ex_info_buf           <= is_ex_info_buf;
        pc_buf_EXE               <= pc_buf_IS;
        EXE_inst                 <= IS_inst;
        ex_pred_info             <= is_pred_info;

        ex_alu_op                <= is_alu_op;
        //ex_alu_src1              <= is_src1;
        //ex_alu_src2              <= is_src2;
        ex_bru_imm               <= is_bru_imm;
        ex_lsu_imm               <= is_imm2;
        ex_r1_sel                <= is_r1_sel;
        ex_r2_sel                <= is_r2_sel;
        ex_rj_value              <= rf_rdata1;
        ex_rd_value              <= rf_rdata2;
        ex_imm1                  <= is_imm1;
        ex_imm2                  <= is_imm2;
        ex_ctrl_en               <= is_ctrl_en;
        ex_bru_op                <= is_bru_op;
        ex_lsu_op                <= is_lsu_op;
        ex_peu_op                <= is_peu_op;
        ex_dest                  <= is_dest;
        ex_dest_we               <= is_dest_we;
        ex_dest_from             <= is_dest_from;
        ex_csr_num               <= is_csr_num;
        ex_csr_we                <= is_csr_we;
        ex_csr_rvalue            <= is_csr_rvalue;
        `ifdef DIFFTEST_EN
        ex_timer_64              <= csr_timer_64_diff;
        `endif
    end
    else if(IS_ready_go_2 & EXE_allowin & IS_to_EXE_inst) begin
        EXE_valid                <= sub_IS_valid;
        ex_ex_info_buf           <= is_ex_info_buf_2;
        pc_buf_EXE               <= pc_buf_IS_2;
        EXE_inst                 <= IS_inst2;
        ex_pred_info             <= is_pred_info_2;

        ex_alu_op                <= is_alu_op_2;
        //ex_alu_src1              <= is_src3;
        //ex_alu_src2              <= is_src4;
        ex_bru_imm               <= is_bru_imm_2;
        ex_lsu_imm               <= is_imm4;
        ex_r1_sel                <= is_r3_sel;
        ex_r2_sel                <= is_r4_sel;
        ex_rj_value              <= rf_rdata3;
        ex_rd_value              <= rf_rdata4;
        ex_imm1                  <= is_imm3;
        ex_imm2                  <= is_imm4;
        ex_ctrl_en               <= is_ctrl_en_2;
        ex_bru_op                <= is_bru_op_2;
        ex_lsu_op                <= is_lsu_op_2;
        ex_peu_op                <= is_peu_op_2;
        ex_dest                  <= is_dest_2;
        ex_dest_we               <= is_dest_we_2;
        ex_dest_from             <= is_dest_from_2;
        ex_csr_num               <= is_csr_num_2;
        ex_csr_we                <= is_csr_we_2;
        ex_csr_rvalue            <= is_csr_rvalue_2;
        `ifdef DIFFTEST_EN
        ex_timer_64              <= csr_timer_64_diff;
        `endif
    end
    else if(EXE_ready_go & MEM_allowin) begin
        EXE_valid <= 1'b0;
    end
end

always @(posedge clk) begin
    if(reset | wb_ex | ertn_flush | tlb_remake | br_taken) begin
        sub_EXE_valid  <= 1'b0;
    end
    else if(IS_ready_go & EXE_allowin & IS_to_EXE_inst) begin
        sub_EXE_valid  <= IS_valid;
        ex_turning         <= 1'b1;
        pc_buf_EXE_2       <= pc_buf_IS;
        EXE_inst2          <= IS_inst;
        
        ex_alu_op_2        <= is_alu_op;
        //ex_alu_src3        <= is_src1;
        //ex_alu_src4        <= is_src2;
        ex_r3_sel          <= is_r1_sel;
        ex_r4_sel          <= is_r2_sel;
        ex_rj_value_2      <= rf_rdata1;
        ex_rd_value_2      <= rf_rdata2;
        ex_imm3            <= is_imm1;
        ex_imm4            <= is_imm2;
        ex_dest_2          <= is_dest;
        ex_dest_we_2       <= is_dest_we;
        ex_dest_from_2     <= is_dest_from;
    end
    else if(IS_ready_go_2 & EXE_allowin & ~IS_to_EXE_inst) begin
        sub_EXE_valid  <= sub_IS_valid;
        ex_turning         <= 1'b0;
        pc_buf_EXE_2       <= pc_buf_IS_2;
        EXE_inst2          <= IS_inst2;

        ex_alu_op_2        <= is_alu_op_2;
        //ex_alu_src3        <= is_src3;
        //ex_alu_src4        <= is_src4;
        ex_r3_sel          <= is_r3_sel;
        ex_r4_sel          <= is_r4_sel;
        ex_rj_value_2      <= rf_rdata3;
        ex_rd_value_2      <= rf_rdata4;
        ex_imm3            <= is_imm3;
        ex_imm4            <= is_imm4;
        ex_dest_2          <= is_dest_2;
        ex_dest_we_2       <= is_dest_we_2;
        ex_dest_from_2     <= is_dest_from_2;
    end
    else if(EXE_ready_go & MEM_allowin) begin
        sub_EXE_valid <= 1'b0;
    end
end

assign ex_alu_src1 = ex_r1_sel ? ex_rj_value : ex_imm1;
assign ex_alu_src2 = ex_r2_sel ? ex_rd_value : ex_imm2;
assign ex_alu_src3 = ex_r3_sel ? ex_rj_value_2 : ex_imm3;
assign ex_alu_src4 = ex_r4_sel ? ex_rd_value_2 : ex_imm4;


alu u_alu1(
    .clk        (clk               ),
    .reset      (reset             ),
    .alu_op     (ex_alu_op         ),
    .alu_src1   (ex_alu_src1       ),
    .alu_src2   (ex_alu_src2       ),
    .alu_result (ex_alu_result     ),
    .div_wating (div_wating        ),
    .mul_wating (mul_wating        ),
    .EXE_valid  (EXE_valid         ),
    .forward_ok (EXE_forward_ok    ),
    .forward_result (EXE_forward_result)
    );

alu u_alu2(
    .clk        (clk               ),
    .reset      (reset             ),
    .alu_op     (ex_alu_op_2       ),
    .alu_src1   (ex_alu_src3       ),
    .alu_src2   (ex_alu_src4       ),
    .alu_result (ex_alu_result_2   ),
    .div_wating (sub_div_wating    ),
    .mul_wating (sub_mul_wating    ),
    .EXE_valid  (sub_EXE_valid     ),
    .forward_ok (EXE_forward_ok_2  ),
    .forward_result (EXE_forward_result_2)
    );

bru u_bru(
    .en((ex_ctrl_en[1] | ex_pred_info[32]) & EXE_valid & ~flush & ~ex_ex_info_buf[0]),
    .op(ex_bru_op      ),
    .rj_value(ex_rj_value  ),
    .rd_value(ex_rd_value  ),
    .imm(ex_bru_imm    ),
    .pc(pc_buf_EXE   ),
    .pred_info(ex_pred_info  ),

    .inst_br(ex_inst_br),
    .br_taken(ex_br_taken    ),
    .br_target(ex_br_target),
    .br_pht(ex_br_pht),
    .actual_taken(ex_actual_taken  ),
    .actual_target(ex_actual_target),
    .call(ex_call),
    .call_addr(ex_call_target),
    .ret(ex_ret),
    .ret_wrong(ex_ret_wrong)
    );

lsu u_lsu(
    .en(ex_ctrl_en[2] & EXE_valid & ~cpu_stall & MEM_allowin & ~flush & ~ex_ex_info_buf[0] & ~wb_br_taken),
    .op(ex_lsu_op      ),
    .rj_value(ex_rj_value  ),
    .rd_value(ex_rd_value  ),
    .imm(ex_lsu_imm        ),
    .llbit(llbit        ),

    .mem_en(ex_mmu_en     ),
    .mem_vaddr(ex_mem_vaddr  ),
    .mem_wr(ex_mem_wr      ),
    .mem_rsize(ex_mem_rsize  ),
    .mem_wen(ex_mem_wen     ),
    .mem_wdata(ex_mem_wdata   ),
    .ld_sel(ex_ld_sel),

    .data_sram_rdata(data_sram_rdata),
    .result_sel(wb_lsu_sel),
    .result_byte(wb_alu_result[1:0]),
    .lsu_result(wb_lsu_result),
    .ex_info(ex_lsu_ex_info)
`ifdef DIFFTEST_EN
    ,
    .ex_inst_ld_en(ex_inst_ld_en),
    .ex_inst_st_en(ex_inst_st_en),
    .ex_st_data   (ex_st_data)
`endif
    );


peu u_peu(
    .en(ex_ctrl_en[3] & EXE_valid & ~cpu_stall & MEM_allowin & ~flush & ~ex_ex_info_buf[0] & ~wb_br_taken),
    .op(ex_peu_op      ),
    .rj_value(ex_rj_value  ),
    .rd_value(ex_rd_value  ),
    .csr_value(ex_csr_rvalue),      
    .llbit(llbit),

    .peu2tlb_en(ex_peu2tlb_en),
    .tlbsrch_wmask(ex_tlbsrch_wmask),
    .tlbsrch_wvalue(ex_tlbsrch_wdata),

    .ertn(ex_ertn),
    .peu_result(ex_peu_result),

    .peu_csr_wen(ex_csr_wen),
    .peu_csr_wmask(ex_csr_wmask),
    .peu_csr_wvalue(ex_csr_wvalue),
    .ex_info(ex_peu_ex_info)
`ifdef DIFFTEST_EN
    ,
    .is_CNTinst(ex_is_CNTinst),
    .csr_rstat(ex_csr_rstat)
`endif 
    );


reg [4:0] wb_lsu_sel; 
reg [31:0] wb_alu_result;
wire [31:0] wb_lsu_result;
reg [31:0] wb_peu_result;
reg [31:0] wb_alu_result_2;
reg [14:0] wb_csr_num;
reg        wb_csr_we;

reg [ 4:0] wb_dest;
reg        wb_dest_we;
reg [ 2:0] wb_dest_from;
reg [ 4:0] wb_dest_2;
reg        wb_dest_we_2;
reg [ 2:0] wb_dest_from_2;

reg [15:0] wb_ex_info;
reg wb_turning;

reg        wb_ertn;
reg [ 1:0] wb_csr_wen;
reg [31:0] wb_csr_wmask;
reg [31:0] wb_csr_wvalue;
reg [137:0] wb_tlb2csr_wvalue;
reg        wb_is_tlbr0;//用于区分出错的vaddr
reg        wb_inst_br;
reg        wb_br_taken;
reg [31:0] wb_br_target;
reg [ 1:0] wb_br_pht;
reg        wb_actual_taken;
reg [31:0] wb_actual_target;
reg        wb_call;
reg [31:0] wb_call_target;
reg        wb_ret;
reg        wb_ret_wrong;

reg  [31:0] wb_mem_paddr;
reg         wb_mem_en;
reg  [ 3:0] wb_mem_wen;
reg  [31:0] wb_mem_wdata;
reg         wb_dcache_v;

reg         wb_commit_once;

// MEM阶段流水线缓存
always @(posedge clk) begin
    if(reset | wb_ex | ertn_flush | br_taken) 
    begin
        MEM_valid                 <= 1'b0;
        sub_MEM_valid             <= 1'b0;
        wb_ex_info                <= 16'b0;
        wb_is_tlbr0               <= 1'b0;
        wb_mem_en                 <= 1'b0;
        wb_mem_paddr              <= 32'b0;
    end
    else if(EXE_ready_go & MEM_allowin)
    begin
        MEM_valid                 <= EXE_valid;
        sub_MEM_valid             <= sub_EXE_valid & ~(ex_br_taken & ~ex_turning);
        pc_buf_MEM                <= pc_buf_EXE;
        pc_buf_MEM_2              <= pc_buf_EXE_2;
        MEM_inst                  <= EXE_inst;
        MEM_inst2                 <= EXE_inst2;
        wb_ex_info                <= ex_ex_info_buf[0] ? ex_ex_info_buf : 
                                     ex_lsu_ex_info[0] ? ex_lsu_ex_info : 
                                     ex_mmu_ex_info[0] ? ex_mmu_ex_info : 
                                                         ex_peu_ex_info;
        wb_is_tlbr0               <= ex_ex_info_buf[0] && (ex_ex_info_buf[6:1] == 6'h3f);
        wb_turning                <= ex_turning;

        wb_alu_result             <= ex_alu_result;
        wb_peu_result             <= ex_peu_result;
        wb_lsu_sel                <= ex_ld_sel;
        wb_dest                   <= ex_dest;
        wb_dest_we                <= ex_dest_we;
        wb_dest_from              <= ex_dest_from;
        
        wb_ertn                   <= ex_ertn;
        wb_csr_num                <= ex_csr_num;
        wb_csr_we                 <= ex_csr_we;
        wb_csr_wen                <= ex_csr_wen;
        wb_csr_wmask              <= ex_csr_wmask;
        wb_csr_wvalue             <= ex_csr_wvalue;
        wb_tlb2csr_wvalue         <= ex_tlb2csr_wvalue;

        wb_alu_result_2           <= ex_alu_result_2;
        wb_dest_2                 <= ex_dest_2;
        wb_dest_we_2              <= ex_dest_we_2;
        wb_dest_from_2            <= ex_dest_from_2;

        wb_inst_br                <= ex_inst_br;
        wb_br_taken               <= ex_br_taken;
        wb_br_target              <= ex_br_target;
        wb_br_pht                 <= ex_br_pht;
        wb_actual_taken           <= ex_actual_taken;
        wb_actual_target          <= ex_actual_target;
        wb_call                   <= ex_call;
        wb_call_target            <= ex_call_target;
        wb_ret                    <= ex_ret;
        wb_ret_wrong              <= ex_ret_wrong;

        wb_mem_en                 <= ex_mem_en & ex_mem_wr;
        wb_mem_wen                <= ex_mem_wen;
        wb_mem_wdata              <= ex_mem_wdata;
        wb_mem_paddr              <= ex_mem_paddr;
        wb_dcache_v               <= ex_dcache_v;
        `ifdef DIFFTEST_EN
        wb_is_CNTinst             <= ex_is_CNTinst;
        wb_csr_rstat              <= ex_csr_rstat && (ex_csr_num == 15'h0005);
        wb_timer_64               <= ex_timer_64;
        wb_inst_ld_en             <= ex_inst_ld_en & {8{ex_mem_en}};
        wb_inst_st_en             <= ex_inst_st_en & {8{ex_mem_en}};
        wb_lsu_vaddr              <= ex_mem_vaddr;
        wb_lsu_paddr              <= ex_mem_paddr;
        wb_st_data                <= ex_st_data;
        `endif  
    end
    else if(MEM_ready_go & WB_allowin)
    begin 
        MEM_valid <= 1'b0;
        sub_MEM_valid <= 1'b0;
    end
end

always @(posedge clk) begin
    if(reset) 
    begin
        wb_commit_once <= 1'b0;
    end else if(EXE_ready_go & MEM_allowin)
    begin 
        wb_commit_once <= 1'b1;
    end else begin
        wb_commit_once <= 1'b0;
    end
end

assign rf_waddr = wb_dest;
assign rf_we    = wb_dest_we & ~wb_ex & ~wb_ertn & MEM_valid & MEM_ready_go;
assign rf_wdata = wb_dest_from[1] ? wb_lsu_result : //(wb_lsu_result_sel ? wb_lsu_result_buf : wb_lsu_result) :双提交时可去掉括号内选择
                  wb_dest_from[2] ? wb_peu_result :
                  wb_alu_result;

assign rf_waddr2 = wb_dest_2;
assign rf_we2 = wb_dest_we_2 & sub_MEM_valid & (~(wb_ex | wb_ertn) | wb_turning);
assign rf_wdata2 = wb_alu_result_2;

assign rf_we_2times = (wb_dest == wb_dest_2);
assign rf_we_turning = wb_turning;


//CSR
assign wb_ex = wb_ex_info[0] & MEM_valid;//wb_ex_info[0] & MEM_ready_go & WB_allowin & MEM_valid;/
assign wb_pc = pc_buf_MEM;
assign wb_ecode = wb_ex_info[6:1];
assign wb_esubcode = wb_ex_info[15:7];
assign wb_vaddr = ((wb_ecode == 6'h08 && ~wb_esubcode[0]) | wb_is_tlbr0) ? pc_buf_MEM : wb_alu_result;

assign csr_wnum = wb_csr_num;
assign csr_we = wb_csr_wen[0] & ~wb_ex & WB_allowin & MEM_valid ;
assign csr_we2 = wb_csr_wen[1] & ~wb_ex & WB_allowin & MEM_valid ;
assign csr_wmask = wb_csr_wmask;
assign csr_wvalue = wb_csr_wvalue;
assign ertn_flush = wb_ertn & ~wb_ex & MEM_valid;

//跳转
assign inst_br = wb_inst_br & wb_commit_once & MEM_valid & ~wb_ex & ~wb_ertn;
assign br_taken = wb_br_taken & MEM_ready_go & WB_allowin & MEM_valid & ~wb_ex & ~wb_ertn;
assign br_target = wb_br_target;
assign br_pht = wb_br_pht;
assign actual_taken = wb_actual_taken & wb_commit_once & MEM_valid & ~wb_ex & ~wb_ertn;
assign actual_target = wb_actual_target;
assign call = wb_call & wb_commit_once & MEM_valid & ~wb_ex & ~wb_ertn;
assign call_target = wb_call_target;
assign ret = wb_ret & wb_commit_once & MEM_valid & ~wb_ex & ~wb_ertn;
assign ret_wrong = wb_ret_wrong & wb_commit_once & MEM_valid & ~wb_ex & ~wb_ertn;

//data
assign data_sram_en = (ex_mem_en & ~ex_mem_wr) | (wb_mem_en & MEM_ready_go & WB_allowin & MEM_valid);
assign data_sram_wen = (wb_mem_en & MEM_valid & MEM_ready_go & WB_allowin) ? wb_mem_wen : 4'b0;
assign data_sram_addr = (wb_mem_en & MEM_valid) ? wb_mem_paddr : ex_mem_paddr;
assign data_sram_waddr = wb_mem_paddr;
assign data_sram_wdata = wb_mem_wdata;//(wb_mem_en & MEM_valid) ? wb_mem_wdata : ex_mem_wdata;
assign data_sram_rsize = ex_mem_rsize;
assign dcache_v = (wb_mem_en & MEM_valid) ? wb_dcache_v : ex_dcache_v;

wire wr_buf_wating;
assign wr_buf_wating = wb_mem_en & MEM_valid & ex_ctrl_en[2] & EXE_valid & ~ex_mem_wr;

CSR0 u_CSR0(
    .clk        (clk             ),
    .reset      (reset           ),
    .intrpt     (intrpt          ),

    .csr_rnum   (is_csr_num      ),
    .csr_rvalue (is_csr_rvalue   ),
    .csr_rnum2  (is_csr_num_2    ),
    .csr_rvalue2(is_csr_rvalue_2 ),
    
    .csr_we     (csr_we          ),
    .csr_wnum   (csr_wnum        ),
    .csr_wmask  (csr_wmask       ),
    .csr_wvalue (csr_wvalue      ),
    .has_int    (has_int         ),

    .ertn_flush (ertn_flush      ),
    .wb_ex      (wb_ex           ),
    .wb_ecode   (wb_ecode        ),
    .wb_esubcode(wb_esubcode     ),
    .wb_pc      (wb_pc           ),
    .wb_vaddr   (wb_vaddr        ),
    .ex_exit    (ex_exit         ),
    .ex_entry   (ex_entry        ),
    
    .dmw0       (csr_dmw0),
    .dmw1       (csr_dmw1),
    .crmd       (csr_crmd),
    .csr_asid   (csr_asid  ),
    .csr_vppn   (csr_vppn  ),
    .csr_ecode  (csr_ecode),
    .tlbelo0_rvalue(tlbelo0_rvalue),
    .tlbelo1_rvalue(tlbelo1_rvalue),
    .tlbidx_rvalue(tlbidx_rvalue),

    .csr_we2_4tlb(csr_we2),
    .tlb2csr_wvalue(wb_tlb2csr_wvalue),
    
    .llbit(llbit)
`ifdef DIFFTEST_EN
    ,
    .csr_crmd_diff     (csr_crmd_diff     ),
    .csr_prmd_diff     (csr_prmd_diff     ),
    .csr_ectl_diff     (csr_ectl_diff     ),
    .csr_estat_diff    (csr_estat_diff    ),
    .csr_era_diff      (csr_era_diff      ),
    .csr_badv_diff     (csr_badv_diff     ),
    .csr_eentry_diff   (csr_eentry_diff   ),
    .csr_tlbidx_diff   (csr_tlbidx_diff   ),
    .csr_tlbehi_diff   (csr_tlbehi_diff   ),
    .csr_tlbelo0_diff  (csr_tlbelo0_diff  ),
    .csr_tlbelo1_diff  (csr_tlbelo1_diff  ),
    .csr_asid_diff     (csr_asid_diff     ),
    .csr_save0_diff    (csr_save0_diff    ),
    .csr_save1_diff    (csr_save1_diff    ),
    .csr_save2_diff    (csr_save2_diff    ),
    .csr_save3_diff    (csr_save3_diff    ),
    .csr_tid_diff      (csr_tid_diff      ),
    .csr_tcfg_diff     (csr_tcfg_diff     ),
    .csr_tval_diff     (csr_tval_diff     ),
    .csr_ticlr_diff    (csr_ticlr_diff    ),
    .csr_llbctl_diff   (csr_llbctl_diff   ),
    .csr_tlbrentry_diff(csr_tlbrentry_diff),
    .csr_dmw0_diff     (csr_dmw0_diff     ),
    .csr_dmw1_diff     (csr_dmw1_diff     ),
    .csr_pgdl_diff     (csr_pgdl_diff     ),
    .csr_pgdh_diff     (csr_pgdh_diff     ),
    .csr_timer_64_diff (csr_timer_64_diff )
`endif
    );

assign tlb_remake = 1'b0;

    MMU u_MMU(
        .clk               (clk                ),
        .reset             (reset              ),
        .wb_ex             (wb_ex              ),
        .ertn_flush        (ertn_flush         ),
        .tlb_remake        (tlb_remake         ),
        .br_taken          (br_taken           ),
        .IF1_ready_go      (IF1_ready_go        ),
        .IF2_allowin       (IF2_allowin        ),
        .IF1_valid         (IF1_valid          ),
        .EXE_ready_go      (EXE_ready_go       ),
        .MEM_allowin       (MEM_allowin        ),
        .EXE_valid         (EXE_valid          ),

        .csr_dmw0         (csr_dmw0          ),
        .csr_dmw1         (csr_dmw1          ),
        .csr_crmd         (csr_crmd          ),
        .csr_asid         (csr_asid          ),
        .csr_vppn         (csr_vppn          ),
        .csr_ecode        (csr_ecode         ),
        .tlbelo0_rvalue   (tlbelo0_rvalue    ),
        .tlbelo1_rvalue   (tlbelo1_rvalue    ),   
        .tlbidx_rvalue    (tlbidx_rvalue     ),

        .inst_en          (inst_en           ),
        .pc_buf_IF1       (pc_buf_IF1        ),
        .fetch_wating     (fetch_wating      ),
        .inst_sram_en     (inst_sram_en      ),
        .inst_sram_addr   (inst_sram_addr    ),

        .mem_vaddr        (ex_mem_vaddr      ),
        .inst_is_load     (~ex_mem_wr        ),
        .inst_is_store    (ex_mem_wr         ),
        .ex_lsu_en        (ex_mmu_en         ),
        .mmu_wating       (mmu_wating        ),
        .data_sram_en     (ex_mem_en         ),
        .data_sram_addr   (ex_mem_paddr      ),

        .peu2tlb_en       (ex_peu2tlb_en     ),
        .rj_value         (ex_rj_value       ),
        .rk_value         (ex_rd_value       ),
        .tlbsrch_wmask    (ex_tlbsrch_wmask  ),
        .tlbsrch_wvalue   (ex_tlbsrch_wdata  ),
        .tlb2csr_wvalue   (ex_tlb2csr_wvalue ),

        .dcache_v         (ex_dcache_v       ),
 
        .wb_tlbr0         (wb_tlbr0          ),
        .wb_ppi0          (wb_ppi0           ),
        .wb_pif           (wb_pif            ),
        .ex_mmu_ex_info   (ex_mmu_ex_info    )
`ifdef DIFFTEST_EN
        ,
        .tlb_fill         (tlb_fill          ),
        .tlb_fill_index   (tlb_fill_index    )
`endif
    );
    

//异常处理
//IF级wb_ex判断
always @(posedge clk) begin
    if(reset | wb_ex | ertn_flush | tlb_remake | br_taken)
    begin
        wb_tlbr0_IF2 <= 1'b0;
        wb_ppi0_IF2 <= 1'b0;
        wb_pif_IF2 <= 1'b0;
    end
    else if(IF1_ready_go & IF2_allowin) begin
        wb_tlbr0_IF2 <= wb_tlbr0;
        wb_ppi0_IF2 <= wb_ppi0;
        wb_pif_IF2 <= wb_pif;
    end
end
assign wb_ex_IF = ((pc_buf_IF2[1:0] != 2'b00) & IF2_valid) | wb_tlbr0_IF2 | wb_ppi0_IF2 | wb_pif_IF2;
assign wb_ecode_IF = ({6{wb_pif_IF2}}   & 6'h03) |
                     ({6{wb_tlbr0_IF2}} & 6'h3f) |
                     ({6{wb_ppi0_IF2}}  & 6'h07) | 
                     ({6{~wb_tlbr0_IF2 & ~wb_ppi0_IF2 & ~wb_pif_IF2}} & 6'h08);
assign wb_esubcode_IF = 9'h0;
assign fetch_tlbwb_IF2 = wb_tlbr0_IF2 | wb_ppi0_IF2 | wb_pif_IF2;


// debug info generate
//差分测试�?


assign WB_allowin = 1'b1;
assign debug_wb_pc = pc_buf_MEM;
assign debug_wb_rf_we = rf_we;
assign debug_wb_rf_wnum = rf_waddr;
assign debug_wb_rf_wdata = rf_wdata;

assign debug1_wb_pc = pc_buf_MEM_2;
assign debug1_wb_rf_we = rf_we2;
assign debug1_wb_rf_wnum = rf_waddr2;
assign debug1_wb_rf_wdata = rf_wdata2;

reg [31:0] cmt_pc;
reg [31:0] cmt_inst;
reg        cmt_valid;
reg        cmt_wen;
reg [7:0]  cmt_wdest;
reg [31:0] cmt_wdata;

reg [31:0] cmt_pc2;
reg [31:0] cmt_inst2;
reg        cmt_valid2;
reg        cmt_wen2;
reg [7:0]  cmt_wdest2;
reg [31:0] cmt_wdata2;

reg        cmt_tlbfill_en;
reg [4:0]  cmt_rand_index;
reg        cmt_cnt_inst;
reg [63:0] cmt_timer_64;
reg        cmt_csr_rstat_en;
reg [31:0] cmt_csr_data;
reg        cmt_excp_flush;
reg        cmt_ertn;
reg [5:0]  cmt_csr_ecode       ;
reg [ 7:0] cmt_inst_ld_en       ;
reg [31:0] cmt_ld_paddr         ;
reg [31:0] cmt_ld_vaddr         ;
reg [ 7:0] cmt_inst_st_en       ;
reg [31:0] cmt_st_paddr         ;
reg [31:0] cmt_st_vaddr         ;
reg [31:0] cmt_st_data          ;

reg [31:0] cmt_ex_pc;
reg [31:0] cmt_ex_inst;

wire sel_sub_pipe = (MEM_valid & sub_MEM_valid) ? rf_we_turning : ~MEM_valid;

`ifdef DIFFTEST_EN

always @(posedge clk) begin
    if (reset) begin
        {cmt_valid, cmt_cnt_inst, cmt_timer_64, cmt_inst_ld_en, cmt_ld_paddr, cmt_ld_vaddr, cmt_inst_st_en, cmt_st_paddr, cmt_st_vaddr, cmt_st_data, cmt_csr_rstat_en, cmt_csr_data} <= 0;
        {cmt_wen, cmt_wdest, cmt_wdata, cmt_pc, cmt_inst, cmt_ex_pc, cmt_ex_inst} <= 0;
        {cmt_valid2, cmt_wen2, cmt_wdest2, cmt_wdata2, cmt_pc2, cmt_inst2} <= 0;
    end else if(MEM_ready_go | wb_ex | ertn_flush) begin
        cmt_valid       <= wb_ex ? rf_we_turning ? sub_MEM_valid : 1'b0 : (MEM_valid | sub_MEM_valid);
        cmt_pc          <= sel_sub_pipe ? pc_buf_MEM_2 : pc_buf_MEM;
        cmt_inst        <= sel_sub_pipe ? MEM_inst2 : MEM_inst;
        cmt_wen         <= sel_sub_pipe ? rf_we2 : rf_we;
        cmt_wdest       <= sel_sub_pipe ? {3'd0, rf_waddr2} : {3'd0, rf_waddr};
        cmt_wdata       <= sel_sub_pipe ? rf_wdata2 : rf_wdata;

        cmt_valid2      <= (wb_ex | ertn_flush) ? 1'b0 : (MEM_valid & sub_MEM_valid);
        cmt_pc2         <= sel_sub_pipe ? pc_buf_MEM : pc_buf_MEM_2;
        cmt_inst2       <= sel_sub_pipe ? MEM_inst : MEM_inst2;
        cmt_wen2        <= sel_sub_pipe ? rf_we : rf_we2;
        cmt_wdest2      <= sel_sub_pipe ? {3'd0, rf_waddr} : {3'd0, rf_waddr2};
        cmt_wdata2      <= sel_sub_pipe ? rf_wdata : rf_wdata2;

        cmt_tlbfill_en  <= tlb_fill & MEM_valid;
        cmt_rand_index  <= {1'b0, tlb_fill_index};
        cmt_cnt_inst    <= wb_is_CNTinst;
        cmt_timer_64    <= wb_timer_64;
        cmt_csr_rstat_en<= wb_csr_rstat;
        cmt_csr_data    <= wb_peu_result;

        cmt_excp_flush  <= wb_ex ;//| ertn_flush;
        cmt_ertn        <= ertn_flush;
        cmt_csr_ecode   <= wb_ecode;

        cmt_inst_ld_en  <= wb_inst_ld_en;
        cmt_ld_paddr    <= wb_lsu_paddr;
        cmt_ld_vaddr    <= wb_lsu_vaddr;

        cmt_inst_st_en  <= wb_inst_st_en;
        cmt_st_paddr    <= wb_lsu_paddr;
        cmt_st_vaddr    <= wb_lsu_vaddr;
        cmt_st_data     <= wb_st_data;
        
        cmt_ex_pc       <= pc_buf_MEM;
        cmt_ex_inst     <= MEM_inst;

    end else begin
        {cmt_valid, cmt_cnt_inst, cmt_timer_64, cmt_inst_ld_en, cmt_ld_paddr, cmt_ld_vaddr, cmt_inst_st_en, cmt_st_paddr, cmt_st_vaddr, cmt_st_data, cmt_csr_rstat_en, cmt_csr_data} <= 0;
        {cmt_wen, cmt_wdest, cmt_wdata, cmt_pc, cmt_inst, cmt_ex_pc, cmt_ex_inst} <= 0;
        {cmt_valid2, cmt_wen2, cmt_wdest2, cmt_wdata2, cmt_pc2, cmt_inst2} <= 0;
    end
end

DifftestInstrCommit DifftestInstrCommit0(
    .clock              (clk            ),
    .coreid             (0              ),
    .index              (0              ),
    .valid              (cmt_valid      ),
    .pc                 (cmt_pc         ),
    .instr              (cmt_inst       ),
    .skip               (0              ),
    .is_TLBFILL         (cmt_tlbfill_en ),
    .TLBFILL_index      (cmt_rand_index ),
    .is_CNTinst         (cmt_cnt_inst   ),
    .timer_64_value     (cmt_timer_64   ),
    .wen                (cmt_wen        ),
    .wdest              (cmt_wdest      ),
    .wdata              (cmt_wdata      ),
    .csr_rstat          (cmt_csr_rstat_en),
    .csr_data           (cmt_csr_data   )
);

DifftestInstrCommit DifftestInstrCommit1(
    .clock              (clk            ),
    .coreid             (0              ),
    .index              (1              ),
    .valid              (cmt_valid2      ),
    .pc                 (cmt_pc2         ),
    .instr              (cmt_inst2       ),
    .skip               (0               ),
    .is_TLBFILL         (0               ),
    .TLBFILL_index      (0               ),
    .is_CNTinst         (0               ),
    .timer_64_value     (64'b0           ),
    .wen                (cmt_wen2        ),
    .wdest              (cmt_wdest2      ),
    .wdata              (cmt_wdata2      ),
    .csr_rstat          (0               ),
    .csr_data           (32'b0           )
);

DifftestExcpEvent DifftestExcpEvent(
    .clock              (clk           ),
    .coreid             (0              ),
    .excp_valid         (cmt_excp_flush ),
    .eret               (cmt_ertn       ),
    .intrNo             (csr_estat_diff[12:2]),
    .cause              (csr_estat_diff[21:16]),
    .exceptionPC        (cmt_ex_pc      ),
    .exceptionInst      (cmt_ex_inst    )
);

DifftestTrapEvent DifftestTrapEvent(
    .clock              (clk           ),
    .coreid             (0              ),
    .valid              (           ),
    .code               (      ),
    .pc                 (         ),
    .cycleCnt           (       ),
    .instrCnt           (       )
);

DifftestStoreEvent DifftestStoreEvent(
    .clock              (clk           ),
    .coreid             (0              ),
    .index              (0              ),
    .valid              (cmt_inst_st_en ),
    .storePAddr         (cmt_st_paddr   ),
    .storeVAddr         (cmt_st_vaddr   ),
    .storeData          (cmt_st_data    )
);

DifftestLoadEvent DifftestLoadEvent(
    .clock              (clk           ),
    .coreid             (0              ),
    .index              (0              ),
    .valid              (cmt_inst_ld_en ),
    .paddr              (cmt_ld_paddr   ),
    .vaddr              (cmt_ld_vaddr   )
);

DifftestCSRRegState DifftestCSRRegState(
    .clock              (clk               ),
    .coreid             (0                  ),
    .crmd               (csr_crmd_diff      ),
    .prmd               (csr_prmd_diff      ),
    .euen               (0                  ),
    .ecfg               (csr_ectl_diff      ),
    .estat              (csr_estat_diff     ),
    .era                (csr_era_diff       ),
    .badv               (csr_badv_diff      ),
    .eentry             (csr_eentry_diff    ),
    .tlbidx             (csr_tlbidx_diff    ),
    .tlbehi             (csr_tlbehi_diff    ),
    .tlbelo0            (csr_tlbelo0_diff   ),
    .tlbelo1            (csr_tlbelo1_diff   ),
    .asid               (csr_asid_diff      ),
    .pgdl               (csr_pgdl_diff      ),
    .pgdh               (csr_pgdh_diff      ),
    .save0              (csr_save0_diff     ),
    .save1              (csr_save1_diff     ),
    .save2              (csr_save2_diff     ),
    .save3              (csr_save3_diff     ),
    .tid                (csr_tid_diff       ),
    .tcfg               (csr_tcfg_diff      ),
    .tval               (csr_tval_diff      ),
    .ticlr              (csr_ticlr_diff     ),
    .llbctl             (csr_llbctl_diff    ),
    .tlbrentry          (csr_tlbrentry_diff ),
    .dmw0               (csr_dmw0_diff      ),
    .dmw1               (csr_dmw1_diff      )
);

DifftestGRegState DifftestGRegState(
    .clock              (clk       ),
    .coreid             (0          ),
    .gpr_0              (0          ),
    .gpr_1              (regs[1]    ),
    .gpr_2              (regs[2]    ),
    .gpr_3              (regs[3]    ),
    .gpr_4              (regs[4]    ),
    .gpr_5              (regs[5]    ),
    .gpr_6              (regs[6]    ),
    .gpr_7              (regs[7]    ),
    .gpr_8              (regs[8]    ),
    .gpr_9              (regs[9]    ),
    .gpr_10             (regs[10]   ),
    .gpr_11             (regs[11]   ),
    .gpr_12             (regs[12]   ),
    .gpr_13             (regs[13]   ),
    .gpr_14             (regs[14]   ),
    .gpr_15             (regs[15]   ),
    .gpr_16             (regs[16]   ),
    .gpr_17             (regs[17]   ),
    .gpr_18             (regs[18]   ),
    .gpr_19             (regs[19]   ),
    .gpr_20             (regs[20]   ),
    .gpr_21             (regs[21]   ),
    .gpr_22             (regs[22]   ),
    .gpr_23             (regs[23]   ),
    .gpr_24             (regs[24]   ),
    .gpr_25             (regs[25]   ),
    .gpr_26             (regs[26]   ),
    .gpr_27             (regs[27]   ),
    .gpr_28             (regs[28]   ),
    .gpr_29             (regs[29]   ),
    .gpr_30             (regs[30]   ),
    .gpr_31             (regs[31]   )
);

`endif 

reg  [31:0] timer1;
reg  [31:0] timer2;
reg  [31:0] timer3;
reg  [31:0] timer4;
reg  [31:0] timer5;

always @(posedge clk) begin
    if(reset) begin
        timer1 <= 32'b0;
    end
    else if(br_taken & actual_taken) begin
        timer1 <= timer1 + 1'b1;
    end
end

always @(posedge clk) begin
    if(reset) begin
        timer2 <= 32'b0;
    end
    else if(br_taken & ~actual_taken) begin
        timer2 <= timer2 + 1'b1;
    end
end

always @(posedge clk) begin
    if(reset) begin
        timer3 <= 32'b0;
    end
    else if(~br_taken & inst_br) begin
        timer3 <= timer3 + 1'b1;
    end
end

always @(posedge clk) begin
    if(reset) begin
        timer5 <= 32'b0;
    end
    else if(inst_br) begin
        timer5 <= timer5 + 1'b1;
    end
end




endmodule

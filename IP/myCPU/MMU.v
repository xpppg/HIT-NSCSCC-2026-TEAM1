module MMU(
    input wire        clk,
    input wire        reset,
    input wire        wb_ex,
    input wire        ertn_flush,
    input wire        tlb_remake,
    input wire        br_taken,
    input wire        IF1_ready_go,
    input wire        IF2_allowin,
    input wire        IF1_valid,
    input wire        EXE_ready_go,
    input wire        MEM_allowin,
    input wire        EXE_valid,

    input wire [ 9:0] csr_asid,
    input wire [18:0] csr_vppn,
    input wire [31:0] csr_dmw0,
    input wire [31:0] csr_dmw1,
    input wire [31:0] csr_crmd,
    input wire [31:0] tlbidx_rvalue,
    input wire [ 5:0] csr_ecode,
    input wire [31:0] tlbelo0_rvalue,
    input wire [31:0] tlbelo1_rvalue,
    
    input  wire        inst_en,
    input  wire [31:0] pc_buf_IF1,
    output wire        fetch_wating,
    output wire        inst_sram_en,
    output wire [31:0] inst_sram_addr,

    input  wire [31:0] mem_vaddr,
    input  wire        inst_is_load,
    input  wire        inst_is_store,
    input  wire        ex_lsu_en,
    output wire        mmu_wating,
    output wire        data_sram_en,
    output wire [31:0] data_sram_addr,
    
    input  wire [ 9:0] peu2tlb_en,
    input  wire [31:0] rj_value,
    input  wire [31:0] rk_value,
    output wire [31:0] tlbsrch_wmask,
    output wire [31:0] tlbsrch_wvalue,
    output wire [137:0] tlb2csr_wvalue,

    output wire        dcache_v,

    output wire        wb_tlbr0,
    output wire        wb_ppi0,
    output wire        wb_pif,
    output wire [15:0] ex_mmu_ex_info
`ifdef DIFFTEST_EN
    ,
    output reg tlb_fill,
    output reg [3:0] tlb_fill_index
`endif 
);
wire        wb_tlbr1;
wire        wb_ppi1;
wire        wb_pil;
wire        wb_pis;
wire        wb_pme;
wire        mmu_ex;
wire [ 5:0] mmu_ecode;
wire [ 8:0] mmu_esubcode;

// search port 0 (for fetch)
wire [ 18:0] s0_vppn;
wire s0_va_bit12;
wire [ 9:0] s0_asid;
wire s0_found_IF1;
wire [ 3:0] s0_index_IF1;
wire [ 19:0] s0_ppn_IF1;
wire [ 5:0] s0_ps_IF1;
wire [ 1:0] s0_plv_IF1;
wire [ 1:0] s0_mat_IF1;
wire s0_d_IF1;
wire s0_v_IF1;
reg  s0_found;
reg  [ 3:0] s0_index;
reg  [ 19:0] s0_ppn;
reg  [ 5:0] s0_ps;
reg  [ 1:0] s0_plv;
reg  [ 1:0] s0_mat;
reg  s0_d;
reg  s0_v;
// search port 1 (for load/store)
wire [ 18:0] s1_vppn;
wire s1_va_bit12;
wire [ 9:0] s1_asid;
wire  s1_found;
wire  [ 3:0] s1_index;
wire  [ 19:0] s1_ppn;
wire  [ 5:0] s1_ps;
wire  [ 1:0] s1_plv;
wire  [ 1:0] s1_mat;
wire  s1_d;
wire  s1_v;
wire w_e;
wire [ 3:0] w_index;
wire [ 18:0] w_vppn;
wire [ 5:0] w_ps;
wire [ 9:0] w_asid;
wire w_g;
wire [ 19:0] w_ppn0;
wire [ 1:0] w_plv0;
wire [ 1:0] w_mat0;
wire w_d0;
wire w_v0;
wire [ 19:0] w_ppn1;
wire [ 1:0] w_plv1;
wire [ 1:0] w_mat1;
wire w_d1;
wire w_v1;
// read port
wire [ 3:0] r_index;
wire r_e;
wire [ 18:0] r_vppn;
wire [ 5:0] r_ps;
wire [ 9:0] r_asid;
wire r_g;
wire [ 19:0] r_ppn0;
wire [ 1:0] r_plv0;
wire [ 1:0] r_mat0;
wire r_d0;
wire r_v0;
wire [ 19:0] r_ppn1;
wire [ 1:0] r_plv1;
wire [ 1:0] r_mat1;
wire r_d1;
wire r_v1;


wire [9:0] asid_wvalue;
wire [31:0] tlbehi_wvalue;
wire [31:0] tlbelo0_wvalue;
wire [31:0] tlbelo1_wvalue;
wire [31:0] tlbidx_wvalue;

wire   csr_da;
wire   csr_pg;
wire   [1:0] csr_plv;

//used for tlb waiting
reg  tlb_l2_ready_fetch;
reg  tlb_l2_ready;
reg  s1_found_l2;
reg  [ 3:0] s1_index_l2;
reg  [ 19:0] s1_ppn_l2;
reg  [ 5:0] s1_ps_l2;
reg  [ 1:0] s1_plv_l2;
reg  [ 1:0] s1_mat_l2;
reg  s1_d_l2;
reg  s1_v_l2;

assign csr_da = csr_crmd[3];
assign csr_pg = csr_crmd[4];
assign csr_plv = csr_crmd[1:0];

always @(posedge clk) begin
    if(reset) begin
        tlb_l2_ready_fetch <= 1'b0;
        s0_found <= 1'b0;
        s0_index <= 4'b0;
        s0_ppn   <= 20'b0;
        s0_ps    <= 6'b0;
        s0_plv   <= 2'b0;
        s0_mat   <= 2'b0;
        s0_d     <= 1'b0;
        s0_v     <= 1'b0;
    end
    else if(fetch_wating & ~tlb_l2_ready_fetch)
    begin
        tlb_l2_ready_fetch <= 1'b1;
        s0_found <= s0_found_IF1;
        s0_index <= s0_index_IF1;
        s0_ppn   <= s0_ppn_IF1;
        s0_ps    <= s0_ps_IF1;
        s0_plv   <= s0_plv_IF1;
        s0_mat   <= s0_mat_IF1;
        s0_d     <= s0_d_IF1;
        s0_v     <= s0_v_IF1;
    end
    else if(IF1_ready_go & IF2_allowin) begin
        tlb_l2_ready_fetch <= 1'b0;
    end
end

always @(posedge clk) begin
    if(reset) begin
        tlb_l2_ready <= 1'b0;
        s1_found_l2 <= 1'b0;
        s1_index_l2 <= 4'b0;
        s1_ppn_l2   <= 20'b0;
        s1_ps_l2    <= 6'b0;
        s1_plv_l2   <= 2'b0;
        s1_mat_l2   <= 2'b0;
        s1_d_l2     <= 1'b0;
        s1_v_l2     <= 1'b0;
    end
    else if(mmu_wating & ~tlb_l2_ready) begin
        tlb_l2_ready <= 1'b1;
        s1_found_l2 <= s1_found;
        s1_index_l2 <= s1_index;
        s1_ppn_l2   <= s1_ppn;
        s1_ps_l2    <= s1_ps;
        s1_plv_l2   <= s1_plv;
        s1_mat_l2   <= s1_mat;
        s1_d_l2     <= s1_d;
        s1_v_l2     <= s1_v;
    end
    else if(EXE_ready_go & MEM_allowin) begin
        tlb_l2_ready <= 1'b0;
    end
end

assign fetch_wating = ~tlb_l2_ready_fetch & inst_en & IF1_valid & ~inst_addr_sel0 & ~inst_addr_sel1_0 & ~inst_addr_sel1_1 & ~wb_ex & ~ertn_flush & ~tlb_remake & ~br_taken;
assign mmu_wating = ~tlb_l2_ready & ex_lsu_en & ~data_addr_sel0 & ~data_addr_sel1_0 & ~data_addr_sel1_1 ;

assign s0_vppn     = pc_buf_IF1[31:13];
assign s0_va_bit12 = pc_buf_IF1[12];
assign s0_asid     = csr_asid;

wire inst_tlbsrch;
wire inst_tlbrd;
wire inst_tlbwr;
wire inst_tlbfill;
wire inst_invtlb;
wire [4:0] invtlb_op;

assign {invtlb_op,inst_invtlb,inst_tlbfill,inst_tlbwr,inst_tlbrd,inst_tlbsrch} = peu2tlb_en;

assign s1_vppn     = inst_tlbsrch ? csr_vppn : mem_vaddr[31:13];
assign s1_va_bit12 = inst_tlbsrch ? 1'b0 : mem_vaddr[12];
assign s1_asid     = csr_asid;
assign tlbsrch_wmask  = {1'b1,27'b0,{4{s1_found}}};
assign tlbsrch_wvalue = {~s1_found,27'b0,s1_index};

assign r_index              = tlbidx_rvalue[3:0];
assign asid_wvalue[9:0]     = r_e ? r_asid : 10'h0;
assign tlbehi_wvalue[31:0]  = r_e ? {r_vppn,13'b0} : 32'h0;
assign tlbelo0_wvalue[31:0] = r_e ? {4'b0,r_ppn0,1'b0,r_g,r_mat0,r_plv0,r_d0,r_v0} : 32'h0;
assign tlbelo1_wvalue[31:0] = r_e ? {4'b0,r_ppn1,1'b0,r_g,r_mat1,r_plv1,r_d1,r_v1} : 32'h0;
assign tlbidx_wvalue[31:0]  = r_e ? {2'b0,r_ps,24'b0} : {1'b1,31'b0};
assign tlb2csr_wvalue = {asid_wvalue,tlbehi_wvalue,tlbelo0_wvalue,tlbelo1_wvalue,tlbidx_wvalue};

reg [3:0] tlbfill_index;

always @(posedge clk) begin
    if(reset) begin
        tlbfill_index <= 4'b0;
    end
    else begin
        tlbfill_index <= tlbfill_index + 4'b1;
    end
end

assign we = inst_tlbwr | inst_tlbfill;
assign w_index = inst_tlbfill ? tlbfill_index : tlbidx_rvalue[3:0];
assign w_e = (csr_ecode == 6'h3f) ? 1'b1 :
                        tlbidx_rvalue[31] ? 1'b0 : 1'b1;
assign w_vppn = csr_vppn;
assign w_ps   = tlbidx_rvalue[29:24];
assign w_asid = csr_asid[9:0];
assign w_g    = tlbelo0_rvalue[6] & tlbelo1_rvalue[6];
assign w_ppn0 = tlbelo0_rvalue[27:8];
assign w_plv0 = tlbelo0_rvalue[3:2];
assign w_mat0 = tlbelo0_rvalue[5:4];
assign w_d0   = tlbelo0_rvalue[1];
assign w_v0   = tlbelo0_rvalue[0];
assign w_ppn1 = tlbelo1_rvalue[27:8];
assign w_plv1 = tlbelo1_rvalue[3:2];
assign w_mat1 = tlbelo1_rvalue[5:4];
assign w_d1   = tlbelo1_rvalue[1];
assign w_v1   = tlbelo1_rvalue[0];

tlb u_tlb(
    .clk        (clk       ),
    // search port 0 (for fetch)
    .s0_vppn    (s0_vppn),
    .s0_va_bit12(s0_va_bit12),
    .s0_asid    (s0_asid),
    .s0_found   (s0_found_IF1),
    .s0_index   (s0_index_IF1),
    .s0_ppn     (s0_ppn_IF1),
    .s0_ps      (s0_ps_IF1),
    .s0_plv     (s0_plv_IF1),
    .s0_mat     (s0_mat_IF1),
    .s0_d       (s0_d_IF1),
    .s0_v       (s0_v_IF1),
    // search port 1 (for load/store)
    .s1_vppn    (s1_vppn),
    .s1_va_bit12(s1_va_bit12),
    .s1_asid    (s1_asid),
    .s1_found   (s1_found),
    .s1_index   (s1_index),
    .s1_ppn     (s1_ppn),
    .s1_ps      (s1_ps),
    .s1_plv     (s1_plv),
    .s1_mat     (s1_mat),
    .s1_d       (s1_d),
    .s1_v       (s1_v),
    // invtlb opcode
    .invtlb_valid(inst_invtlb),
    .invtlb_op  (invtlb_op),
    .invtlb_vppn(rk_value[31:13]),
    .invtlb_asid(rj_value[9:0]),
    // write port
    .we         (we),
    .w_index    (w_index),
    .w_e        (w_e),
    .w_vppn     (w_vppn),
    .w_ps       (w_ps),
    .w_asid     (w_asid),
    .w_g        (w_g),
    .w_ppn0     (w_ppn0),
    .w_plv0     (w_plv0),
    .w_mat0     (w_mat0),
    .w_d0       (w_d0),
    .w_v0       (w_v0),
    .w_ppn1     (w_ppn1),
    .w_plv1     (w_plv1),
    .w_mat1     (w_mat1),
    .w_d1       (w_d1),
    .w_v1       (w_v1),
    // read port
    .r_index    (r_index),
    .r_e        (r_e),
    .r_vppn     (r_vppn),
    .r_ps       (r_ps),
    .r_asid     (r_asid),
    .r_g        (r_g),
    .r_ppn0     (r_ppn0),
    .r_plv0     (r_plv0),
    .r_mat0     (r_mat0),
    .r_d0       (r_d0),
    .r_v0       (r_v0),
    .r_ppn1     (r_ppn1),
    .r_plv1     (r_plv1),
    .r_mat1     (r_mat1),
    .r_d1       (r_d1),
    .r_v1       (r_v1)
);

//MMU
wire [31:0] inst_addr0;
wire [31:0] inst_addr1_0;
wire [31:0] inst_addr1_1;
wire [31:0] inst_addr2;

wire [31:0] data_addr0;
wire [31:0] data_addr1_0;
wire [31:0] data_addr1_1;
wire [31:0] data_addr2;

wire inst_addr_sel0;
wire inst_addr_sel1_0;
wire inst_addr_sel1_1;
wire inst_addr_sel2;
wire inst_addr_v;

wire dcache_v_0;
wire dcache_v_1_0;
wire dcache_v_1_1;
wire dcache_v_2;
wire data_addr_sel0;
wire data_addr_sel1_0;
wire data_addr_sel1_1;
wire data_addr_sel2;
wire data_addr_v;
reg data_addr_v_EXE;

//地址翻译
assign inst_addr0 = pc_buf_IF1;
assign inst_addr1_0 = {csr_dmw0[27:25], pc_buf_IF1[28:0]};
assign inst_addr1_1 = {csr_dmw1[27:25], pc_buf_IF1[28:0]};
assign inst_addr2 = {s0_ppn, pc_buf_IF1[11:0]};

assign inst_addr_sel0 = (csr_da == 2'b01) && (csr_pg == 2'b00);
assign inst_addr_sel1_0 = (pc_buf_IF1[31:29] == csr_dmw0[31:29]) && (((csr_plv == 2'h0) && csr_dmw0[0]) || ((csr_plv == 2'h3) && csr_dmw0[3]));
assign inst_addr_sel1_1 = (pc_buf_IF1[31:29] == csr_dmw1[31:29]) && (((csr_plv == 2'h0) && csr_dmw1[0]) || ((csr_plv == 2'h3) && csr_dmw1[3]));
assign inst_addr_sel2 = s0_found && s0_v && ~s0_d && (s0_plv >= csr_plv);
assign inst_addr_v = inst_addr_sel0 | inst_addr_sel1_0 | inst_addr_sel1_1 | inst_addr_sel2;

assign inst_sram_addr  = inst_addr_sel0 ? inst_addr0 :
                         inst_addr_sel1_0 ? inst_addr1_0 :
                         inst_addr_sel1_1 ? inst_addr1_1 : inst_addr2;
assign inst_sram_en   = inst_en & inst_addr_v & ~wb_ex & ~ertn_flush & ~tlb_remake & ~br_taken & IF1_ready_go & IF2_allowin;



assign data_addr0 = mem_vaddr[31:0];
assign data_addr1_0 = {csr_dmw0[27:25], mem_vaddr[28:0]};
assign data_addr1_1 = {csr_dmw1[27:25], mem_vaddr[28:0]};
assign data_addr2 = {s1_ppn_l2, mem_vaddr[11:0]};

assign data_addr_sel0 = (csr_da == 2'b01) && (csr_pg == 2'b00);
assign data_addr_sel1_0 = (mem_vaddr[31:29] == csr_dmw0[31:29]) && (((csr_plv == 2'h0) && csr_dmw0[0]) || ((csr_plv == 2'h3) && csr_dmw0[3]));
assign data_addr_sel1_1 = (mem_vaddr[31:29] == csr_dmw1[31:29]) && (((csr_plv == 2'h0) && csr_dmw1[0]) || ((csr_plv == 2'h3) && csr_dmw1[3]));
assign data_addr_sel2 = ~(ex_lsu_en & ~s1_found_l2) & ~(ex_lsu_en & s1_found_l2 & s1_v_l2 & (s1_plv_l2 < csr_plv)) 
                        & ~(ex_lsu_en & inst_is_load & s1_found_l2 & ~s1_v_l2) & ~(ex_lsu_en & inst_is_store & s1_found_l2 & ~s1_v_l2) 
                        & ~(ex_lsu_en & inst_is_store & s1_found_l2 & s1_v_l2 & (s1_plv_l2 >= csr_plv) & ~s1_d_l2);
assign data_addr_v = data_addr_sel0 | data_addr_sel1_0 | data_addr_sel1_1 | data_addr_sel2;

assign data_sram_addr  = data_addr_sel0 ? data_addr0 :
                         data_addr_sel1_0 ? data_addr1_0 :
                         data_addr_sel1_1 ? data_addr1_1 : data_addr2;
assign data_sram_en   = ex_lsu_en & data_addr_v & EXE_ready_go & MEM_allowin;

assign dcache_v_0 = (csr_crmd[8:7] == 2'b01); 
assign dcache_v_1_0 = (csr_dmw0[5:4] == 2'b01);
assign dcache_v_1_1 = (csr_dmw1[5:4] == 2'b01);
assign dcache_v_2 = (s1_mat_l2 == 2'b01);

assign dcache_v = data_addr_sel0   ? dcache_v_0 :
                  data_addr_sel1_0 ? dcache_v_1_0 :
                  data_addr_sel1_1 ? dcache_v_1_1 :
                  data_addr_sel2   ? dcache_v_2 : 1'b0;


//TLB异常
assign wb_tlbr0 = ~inst_addr_sel0 & ~inst_addr_sel1_0 & ~inst_addr_sel1_1 & ~s0_found & IF1_valid;
assign wb_ppi0  = ~inst_addr_sel0 & ~inst_addr_sel1_0 & ~inst_addr_sel1_1 & s0_found & s0_v & (s0_plv < csr_plv) & IF1_valid;
assign wb_pif   = ~inst_addr_sel0 & ~inst_addr_sel1_0 & ~inst_addr_sel1_1 & s0_found & ~s0_v & IF1_valid;

assign wb_tlbr1 = ex_lsu_en & EXE_valid & ~data_addr_sel0 & ~data_addr_sel1_0 & ~data_addr_sel1_1 & ~s1_found_l2;
assign wb_ppi1  = ex_lsu_en & EXE_valid & ~data_addr_sel0 & ~data_addr_sel1_0 & ~data_addr_sel1_1 & s1_found_l2 & s1_v_l2 & (s1_plv_l2 < csr_plv);
assign wb_pil   = ex_lsu_en & inst_is_load & EXE_valid & ~data_addr_sel0 & ~data_addr_sel1_0 & ~data_addr_sel1_1 & s1_found_l2 & ~s1_v_l2;
assign wb_pis   = ex_lsu_en & inst_is_store & EXE_valid & ~data_addr_sel0 & ~data_addr_sel1_0 & ~data_addr_sel1_1 & s1_found_l2 & ~s1_v_l2;
assign wb_pme   = ex_lsu_en & inst_is_store & EXE_valid & ~data_addr_sel0 & ~data_addr_sel1_0 & ~data_addr_sel1_1 & s1_found_l2 & s1_v_l2 & (s1_plv_l2 >= csr_plv) & ~s1_d_l2;


assign mmu_ex = wb_tlbr1 | wb_ppi1 | wb_pil | wb_pis | wb_pme;
assign mmu_ecode = ({6{wb_tlbr1}} & 6'h3f) |
                  ({6{wb_ppi1}}  & 6'h07) |
                  ({6{wb_pil}}   & 6'h01) |
                  ({6{wb_pis}}   & 6'h02) |
                  ({6{wb_pme}}   & 6'h04) ;
assign mmu_esubcode = 9'h0;

assign ex_mmu_ex_info = {mmu_esubcode, mmu_ecode, mmu_ex};

`ifdef DIFFTEST_EN

always @(posedge clk) begin
    if(reset) begin
        tlb_fill <= 1'b0;
        tlb_fill_index <= 4'b0;
    end
    else begin
        tlb_fill <= inst_tlbfill;
        tlb_fill_index <= tlbfill_index;
    end
end

`endif 


endmodule
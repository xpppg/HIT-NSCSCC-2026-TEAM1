module ID(
    input  wire [31:0] inst,
    input  wire [31:0] pc,
    input  wire        has_int,
    input  wire        valid,

    output wire [ 4:0] r1,
    output wire [ 4:0] r2,
    output wire        r1_sel,//1:reg
    output wire        r2_sel,//1:reg
    output wire [31:0] imm1,
    output wire [31:0] imm2,

    output wire [18:0] alu_op,
    output wire [ 8:0] bru_op,
    output wire [31:0] bru_imm,
    output wire [ 9:0] lsu_op,
    output wire [18:0] peu_op,  // invtlb_op = peu_op[18:14]
    output wire [ 3:0] ctrl_en, // [3]:peu, [2]:lsu, [1]:bru, [0]:alu 

    output wire [ 4:0] dest,
    output wire        dest_we,
    output wire [ 2:0] dest_from,
    output wire [14:0] csr_num,
    output wire        csr_we,
    //例外中断检测
    output wire [15:0] ex_info,
    //ISSUE 
    output wire        inst_normal
);
wire        bru_en;
wire        lsu_en;
wire        peu_en;
wire        basic_int;
wire        wb_ex_ID;
wire [ 5:0] wb_ecode_ID;
wire [ 8:0] wb_esubcode_ID;

wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;
wire [13:0] i14;

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_lu12i_w;
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_pcaddu12i;
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_div_w;
wire        inst_mod_w;
wire        inst_div_wu;
wire        inst_mod_wu;
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;
wire        inst_syscall;
wire        inst_break;
wire        inst_csrrd;
wire        inst_csrwr;
wire        inst_csrxchg;
wire        inst_ertn;
wire        inst_rdcntid_w;
wire        inst_rdcntvl_w;
wire        inst_rdcntvh_w;
wire        inst_tlbsrch;
wire        inst_tlbrd;
wire        inst_tlbwr;
wire        inst_tlbfill;
wire        inst_invtlb;
wire        inst_cacop;
wire        inst_cpucfg;
wire        inst_dbar;
wire        inst_ibar;
wire        inst_ll_w;
wire        inst_sc_w;
wire        inst_idle;

wire        need_ui5;
wire        need_ui12;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        need_si14;
wire        src2_is_4;

wire [31:0] cpucfg_wdata;
wire [31:0] br_offs;
wire [31:0] jirl_offs;
wire [31:0] imm;
wire gr_we;

wire        src1_is_pc;
wire        src2_is_imm;
wire        dst_is_r1;
wire        dst_is_rj;
wire        src_reg_is_rd;
wire        dst_is_r0;

wire        inst_not_exist;

assign op_31_26  = inst[31:26];
assign op_25_22  = inst[25:22];
assign op_21_20  = inst[21:20];
assign op_19_15  = inst[19:15];

assign rd   = inst[ 4: 0];
assign rj   = inst[ 9: 5];
assign rk   = inst[14:10];

assign i12  = inst[21:10];
assign i20  = inst[24: 5];
assign i16  = inst[25:10];
assign i26  = {inst[ 9: 0], inst[25:10]};
assign i14  = inst[23:10];

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~inst[25];
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_sll_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_pcaddu12i = op_31_26_d[6'h07] & ~inst[25];
assign inst_mul_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu= op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];
assign inst_blt    = op_31_26_d[6'h18];
assign inst_bge    = op_31_26_d[6'h19];
assign inst_bltu   = op_31_26_d[6'h1a];
assign inst_bgeu   = op_31_26_d[6'h1b];
assign inst_ld_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_bu  = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu  = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_syscall = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h16];
assign inst_break  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h14];
assign inst_csrrd  = op_31_26_d[6'h01] & ~inst[25] & ~inst[24] & (rj == 5'b00000);
assign inst_csrwr  = op_31_26_d[6'h01] & ~inst[25] & ~inst[24] & (rj == 5'b00001);
assign inst_csrxchg= op_31_26_d[6'h01] & ~inst[25] & ~inst[24] & (rj != 5'b00000) & (rj != 5'b00001);
assign inst_ertn   = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'b01110);
assign inst_rdcntid_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & (rk == 5'b11000) & (rd == 5'b00000); 
assign inst_rdcntvl_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & (rk == 5'b11000) & (rj == 5'b00000);
assign inst_rdcntvh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & (rk == 5'b11001) & (rj == 5'b00000);
assign inst_tlbsrch = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'b01010) & (rj == 5'b00000) & (rd == 5'b00000);
assign inst_tlbrd   = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'b01011) & (rj == 5'b00000) & (rd == 5'b00000);
assign inst_tlbwr   = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'b01100) & (rj == 5'b00000) & (rd == 5'b00000);
assign inst_tlbfill = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'b01101) & (rj == 5'b00000) & (rd == 5'b00000);
assign inst_invtlb  = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h13];
assign inst_cacop   = op_31_26_d[6'h01] & op_25_22_d[4'h8];
assign inst_cpucfg  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & (rk == 5'b11011);
assign inst_dbar    = op_31_26_d[6'h0e] & op_25_22_d[4'h1] & op_21_20_d[2'h3] & op_19_15_d[5'h04];
assign inst_ibar    = op_31_26_d[6'h0e] & op_25_22_d[4'h1] & op_21_20_d[2'h3] & op_19_15_d[5'h05];
assign inst_ll_w    = op_31_26_d[6'd08] & ~inst[25] & ~inst[24];
assign inst_sc_w    = op_31_26_d[6'd08] & ~inst[25] & inst[24];
assign inst_idle    = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h11];

assign inst_not_exist = ~(inst_add_w | inst_sub_w | inst_slt | inst_sltu | inst_nor | inst_and | inst_or | inst_xor
                    | inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w | inst_ld_w | inst_st_w
                    | inst_jirl | inst_b | inst_bl | inst_beq | inst_bne 
                    | inst_lu12i_w | inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori
                    | inst_sll_w | inst_srl_w | inst_sra_w | inst_pcaddu12i | inst_mul_w | inst_mulh_w | inst_mulh_wu
                    | inst_div_w | inst_mod_w | inst_div_wu | inst_mod_wu
                    | inst_blt | inst_bge | inst_bltu | inst_bgeu
                    | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu
                    | inst_st_b | inst_st_h
                    | inst_syscall | inst_break
                    | inst_csrrd | inst_csrwr | inst_csrxchg
                    | inst_ertn | inst_rdcntid_w | inst_rdcntvl_w | inst_rdcntvh_w
                    | inst_tlbsrch | inst_tlbrd | inst_tlbfill | inst_tlbwr | inst_invtlb 
                    | inst_cacop | inst_cpucfg | inst_dbar | inst_ibar | inst_ll_w | inst_sc_w | inst_idle
                    );

assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                    | inst_jirl | inst_bl | inst_pcaddu12i 
                    | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu
                    | inst_st_b | inst_st_h | inst_ll_w | inst_sc_w;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt | inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltui;
assign alu_op[ 4] = inst_and | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or | inst_ori;
assign alu_op[ 7] = inst_xor | inst_xori;
assign alu_op[ 8] = inst_slli_w | inst_sll_w;
assign alu_op[ 9] = inst_srli_w | inst_srl_w;
assign alu_op[10] = inst_srai_w | inst_sra_w;
assign alu_op[11] = inst_lu12i_w | inst_cpucfg;
assign alu_op[12] = inst_mul_w ;
assign alu_op[13] = inst_mulh_w;
assign alu_op[14] = inst_mulh_wu;
assign alu_op[15] = inst_div_w ;
assign alu_op[16] = inst_mod_w ;
assign alu_op[17] = inst_div_wu;
assign alu_op[18] = inst_mod_wu; 

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_ui12  =  inst_andi | inst_ori | inst_xori;
assign need_si12  =  inst_addi_w | inst_ld_w | inst_st_w | inst_slti | inst_sltui
                     | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h;
assign need_si16  =  inst_jirl | inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;
assign need_si20  =  inst_lu12i_w | inst_pcaddu12i;
assign need_si26  =  inst_b | inst_bl;
assign need_si14  =  inst_ll_w | inst_sc_w;
assign src2_is_4  =  inst_jirl | inst_bl;
assign cpucfg_wdata = 32'b0;

assign imm = inst_cpucfg ? cpucfg_wdata :
             src2_is_4 ? 32'h4                      :
             need_si20 ? {i20[19:0], 12'b0}         :
             need_ui12 ? {{20{1'b0}}, i12[11:0]}    :
             need_si14 ? {{16{i14[13]}}, i14[13:0], 2'b0} :
/*need_ui5 || need_si12*/{{20{i12[11]}}, i12[11:0]} ;

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w | inst_blt | inst_bge | inst_bltu | inst_bgeu | inst_st_b | inst_st_h | inst_csrrd | inst_csrwr | inst_csrxchg | inst_sc_w;

assign src1_is_pc    = inst_bl | inst_jirl | inst_pcaddu12i;

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_ld_w   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_jirl   |
                       inst_bl     |
                       inst_slti   |
                       inst_sltui  |
                       inst_andi   |
                       inst_ori    |
                       inst_xori   |
                       inst_pcaddu12i|
                       inst_ld_b   |
                       inst_ld_h   |
                       inst_ld_bu  |
                       inst_ld_hu  |
                       inst_st_b   |
                       inst_st_h   |
                       inst_cpucfg |
                       inst_ll_w   |
                       inst_sc_w   ;

assign dst_is_r1     = inst_bl;
assign dst_is_rj     = inst_rdcntid_w;
assign dest = dst_is_r1 ? 5'd1 : 
                           dst_is_rj ? rj : rd;
assign dst_is_r0     = (dest == 5'd0);
assign gr_we         = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b & ~inst_blt & ~inst_tlbsrch & ~inst_tlbrd & ~inst_tlbwr & ~inst_tlbfill & ~inst_invtlb
                       & ~inst_bge & ~inst_bltu & ~inst_bgeu & ~inst_st_b & ~inst_st_h & ~inst_syscall & ~inst_ertn & ~inst_break & ~inst_not_exist & ~inst_cacop & ~inst_dbar & ~inst_ibar & ~inst_idle & ~dst_is_r0;

//assign alu_src1 = src1_is_pc  ? pc[31:0] : rj_value;
//assign alu_src2 = src2_is_imm ? imm : rkd_value;
assign imm1 = pc;
assign imm2 = imm;
assign r1_sel = ~src1_is_pc;
assign r2_sel = ~src2_is_imm;
assign r1 = rj;
assign r2 = src_reg_is_rd ? rd : rk;
assign dest_we    = gr_we;
assign dest_from[0] = ~dest_from[2] & ~dest_from[1];
assign dest_from[1] = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_ll_w;
assign dest_from[2] = inst_csrrd | inst_csrwr | inst_csrxchg | inst_rdcntid_w | inst_rdcntvl_w | inst_rdcntvh_w | inst_sc_w;


//给BRU的信号
assign bru_en = inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu | inst_b | inst_bl | inst_jirl;
assign bru_op[0] = inst_beq;
assign bru_op[1] = inst_bne;
assign bru_op[2] = inst_blt;
assign bru_op[3] = inst_bge;
assign bru_op[4] = inst_bltu;
assign bru_op[5] = inst_bgeu;
assign bru_op[6] = inst_b;
assign bru_op[7] = inst_bl;
assign bru_op[8] = inst_jirl;

assign bru_imm = inst_jirl ? jirl_offs : br_offs;

//LSU相关信号
assign lsu_en = inst_st_w | inst_st_b | inst_st_h | inst_sc_w |inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_ll_w ;
assign lsu_op[0] = inst_st_w;
assign lsu_op[1] = inst_st_b;
assign lsu_op[2] = inst_st_h;
assign lsu_op[3] = inst_sc_w;
assign lsu_op[4] = inst_ld_w;
assign lsu_op[5] = inst_ld_b;
assign lsu_op[6] = inst_ld_h;
assign lsu_op[7] = inst_ld_bu;
assign lsu_op[8] = inst_ld_hu;
assign lsu_op[9] = inst_ll_w;

//PEU相关信号
assign peu_en = inst_csrrd | inst_csrwr | inst_csrxchg | inst_rdcntid_w | inst_rdcntvl_w | inst_rdcntvh_w 
                | inst_tlbsrch | inst_tlbrd | inst_tlbwr | inst_tlbfill | inst_invtlb | inst_ertn | inst_ll_w |inst_sc_w;
assign peu_op[ 0] = inst_csrrd;
assign peu_op[ 1] = inst_csrwr;
assign peu_op[ 2] = inst_csrxchg;
assign peu_op[ 3] = inst_rdcntid_w;
assign peu_op[ 4] = inst_rdcntvl_w;
assign peu_op[ 5] = inst_rdcntvh_w;
assign peu_op[ 6] = inst_tlbsrch;
assign peu_op[ 7] = inst_tlbrd;
assign peu_op[ 8] = inst_tlbwr;
assign peu_op[ 9] = inst_tlbfill;
assign peu_op[10] = inst_invtlb;
assign peu_op[11] = inst_ertn;
assign peu_op[12] = inst_ll_w;
assign peu_op[13] = inst_sc_w;
assign peu_op[18:14]  = inst[4:0];

//CSR读写相关
assign csr_num    = (inst_ll_w | inst_sc_w) ? 15'h0203 :
                    inst_rdcntid_w ? 15'h0202 : 
                    inst_rdcntvl_w ? 15'h0200 :
                    inst_rdcntvh_w ? 15'h0201 : 
                    inst_tlbsrch   ? 15'h0010 : 
                    inst_tlbwr     ? 15'h0005 : inst[23:10];
assign csr_we     = inst_csrwr | inst_csrxchg | inst_tlbsrch | inst_tlbrd | inst_ll_w | inst_sc_w;

//异常检测逻辑
assign wb_ex_ID = (inst_syscall | inst_break  | inst_not_exist | has_int) & valid;
assign wb_ecode_ID = inst_not_exist ? 6'h0d :
                       inst_syscall ? 6'h0b : 
                        inst_break  ? 6'h0c : 6'h00;
assign wb_esubcode_ID = 9'h0;
assign ex_info[15:0] = {wb_esubcode_ID,wb_ecode_ID,wb_ex_ID};

assign ctrl_en[0] = 1'b1;
assign ctrl_en[1] = bru_en;
assign ctrl_en[2] = lsu_en;
assign ctrl_en[3] = peu_en;

assign basic_int = inst_add_w | inst_sub_w | inst_addi_w | inst_lu12i_w | inst_slt | inst_sltu | 
                   inst_slti | inst_sltui | inst_pcaddu12i | inst_and | inst_or | inst_nor | inst_xor |inst_andi | inst_ori | inst_xori | 
                   inst_sll_w | inst_srl_w | inst_sra_w | inst_slli_w | inst_srli_w | inst_srai_w;
assign inst_normal = inst_add_w | inst_sub_w | inst_addi_w | inst_lu12i_w |
                     inst_slt | inst_sltu | inst_slti | inst_sltui |
                     inst_pcaddu12i | inst_and | inst_or | inst_nor | inst_xor |
                     inst_andi | inst_ori | inst_xori |
                     inst_mul_w | inst_mulh_w | inst_mulh_wu |
                     inst_sll_w | inst_srl_w | inst_sra_w |
                     inst_slli_w | inst_srli_w | inst_srai_w |
                     inst_cpucfg | inst_cacop | inst_dbar | inst_ibar;





endmodule
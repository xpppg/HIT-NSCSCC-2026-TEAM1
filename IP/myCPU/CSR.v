`define CRMD 15'h0000
`define PRMD 15'h0001
`define ESTAT 15'h0005
`define ERA 15'h0006
`define EENTRY 15'h000c
`define SAVE0 15'h0030
`define SAVE1 15'h0031
`define SAVE2 15'h0032
`define SAVE3 15'h0033
`define ECFG 15'h0004
`define BADV 15'h0007
`define TID 15'h0040
`define TCFG 15'h0041
`define TVAL 15'h0042
`define TICLR 15'h0044 
`define ASID 15'h0018
`define TLBIDX 15'h0010
`define TLBEHI 15'h0011
`define TLBELO0 15'h0012
`define TLBELO1 15'h0013
`define TLBENTRY 15'h0088
`define TLBDMW0 15'h0180
`define TLBDMW1 15'h0181
`define PGDL 15'h0019
`define PGDH 15'h001a
`define PGD 15'h001b
`define LLBCTL 15'h0060

//自定义地�??编码，便于进行访问CSR的统�??
`define RDCNTVL 15'h0200
`define RDCNTVH 15'h0201
`define RDCNTID 15'h0202
`define LLBit   15'h0203

module CSR0(
    input  wire clk,
    input  wire reset,
    input  wire [ 7:0] intrpt,

    input  wire [14:0] csr_rnum,
    output wire [31:0] csr_rvalue,
    input  wire [14:0] csr_rnum2,
    output wire [31:0] csr_rvalue2,
 
    input  wire csr_we,
    input  wire [14:0] csr_wnum,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wvalue,
    output wire has_int,

    input  wire ertn_flush,
    input  wire wb_ex,
    input  wire [5:0] wb_ecode,
    input  wire [8:0] wb_esubcode,
    input  wire [31:0] wb_pc,
    input  wire [31:0] wb_vaddr,
    output wire [31:0] ex_exit,
    output wire [31:0] ex_entry,
    // 地址翻译相关
    output wire [5:0] csr_ecode,
    output wire [31:0] dmw0,
    output wire [31:0] dmw1,
    output wire [31:0] crmd,
    output wire [9:0] csr_asid,
    output wire [18:0] csr_vppn,
    output wire [31:0] tlbelo0_rvalue,
    output wire [31:0] tlbelo1_rvalue,
    output wire [31:0] tlbidx_rvalue,
    
    input  wire csr_we2_4tlb,
    input  wire [137:0] tlb2csr_wvalue,

    output wire llbit
`ifdef DIFFTEST_EN
    ,
    output wire [31:0] csr_crmd_diff,
    output wire [31:0] csr_prmd_diff,
    output wire [31:0] csr_ectl_diff,
    output wire [31:0] csr_estat_diff,
    output wire [31:0] csr_era_diff,
    output wire [31:0] csr_badv_diff,
    output wire [31:0] csr_eentry_diff,
    output wire [31:0] csr_tlbidx_diff,
    output wire [31:0] csr_tlbehi_diff,
    output wire [31:0] csr_tlbelo0_diff,
    output wire [31:0] csr_tlbelo1_diff,
    output wire [31:0] csr_asid_diff,
    output wire [31:0] csr_save0_diff,
    output wire [31:0] csr_save1_diff,
    output wire [31:0] csr_save2_diff,
    output wire [31:0] csr_save3_diff,
    output wire [31:0] csr_tid_diff,
    output wire [31:0] csr_tcfg_diff,
    output wire [31:0] csr_tval_diff,
    output wire [31:0] csr_ticlr_diff,
    output wire [31:0] csr_llbctl_diff,
    output wire [31:0] csr_tlbrentry_diff,
    output wire [31:0] csr_dmw0_diff,
    output wire [31:0] csr_dmw1_diff,
    output wire [31:0] csr_pgdl_diff,
    output wire [31:0] csr_pgdh_diff,
    output wire [63:0] csr_timer_64_diff
`endif
);
wire [31:0] tlbehi_wvalue;
wire [31:0] tlbelo0_wvalue;
wire [31:0] tlbelo1_wvalue;
wire [31:0] tlbidx_wvalue;
wire [9:0] asid_wvalue;

assign {asid_wvalue,tlbehi_wvalue,tlbelo0_wvalue,tlbelo1_wvalue,tlbidx_wvalue} = tlb2csr_wvalue;

reg [31:0] csr_crmd;
reg [31:0] csr_prmd;
reg [31:0] csr_estat;
reg [31:0] csr_era;
reg [31:0] csr_eentry;
reg [31:0] csr_save0;
reg [31:0] csr_save1;
reg [31:0] csr_save2;
reg [31:0] csr_save3;
reg [31:0] csr_ecfg;
reg [31:0] csr_badv;
reg [31:0] csr_tid;
reg [31:0] csr_tcfg;
wire [31:0] csr_tval;
reg [31:0] csr_ticlr;
reg [31:0] csr_ASID;
reg [31:0] csr_tlbidx;
reg [31:0] csr_tlbehi;
reg [31:0] csr_tlbelo0;
reg [31:0] csr_tlbelo1;
reg [31:0] csr_tlbentry;
reg [31:0] csr_dmw0;
reg [31:0] csr_dmw1;
reg [31:0] csr_pgdl;
reg [31:0] csr_pgdh;
wire [31:0] csr_pgd;
reg [31:0] csr_llbctl;

reg [31:0] csr_ovalue;
reg [31:0] timer_cnt;
wire [31:0] tcfg_next_value;
wire wb_ex_tlb;
wire wb_ex_addr_err;
reg [63:0] csr_timer_64;

always @(posedge clk) begin
    if(reset)
    begin
        csr_crmd[1:0] <= 2'b0;
        csr_crmd[2] <= 1'b0;
        csr_crmd[3] <= 1'b1;
        csr_crmd[4] <= 1'b0;
        csr_crmd[6:5] <= 2'b0;
        csr_crmd[8:7] <= 2'b0;
    end
    else if(wb_ex)
    begin
        csr_crmd[1:0] <= 2'b0;
        csr_crmd[2] <= 1'b0;
        if(wb_ecode == 6'h3f)
        begin
            csr_crmd[3] <= 1'b1; // TLB重填
            csr_crmd[4] <= 1'b0; 
        end
    end
    else if(ertn_flush)
    begin
        csr_crmd[1:0] <= csr_prmd[1:0];
        csr_crmd[2] <= csr_prmd[2];
        if(csr_estat[21:16] == 6'h3f)
        begin
            csr_crmd[3] <= 1'b0; 
            csr_crmd[4] <= 1'b1; 
        end
    end
    else if(csr_we && csr_wnum == `CRMD)
        csr_crmd[8:0] <= csr_wmask[8:0] & csr_wvalue[8:0]
                      | ~csr_wmask[8:0] & csr_crmd[8:0];
    csr_crmd[31:9] <= 23'b0;
end


always @(posedge clk) begin
    if(wb_ex) begin
      csr_prmd[1:0] <= csr_crmd[1:0];
      csr_prmd[2] <= csr_crmd[2];
    end
    else if (csr_we && csr_wnum == `PRMD) begin
      csr_prmd[1:0] <= csr_wmask[1:0] & csr_wvalue[1:0]
                    | ~csr_wmask[1:0] & csr_prmd[1:0];
      csr_prmd[2] <= csr_wmask[2] & csr_wvalue[2]
                  | ~csr_wmask[2] & csr_prmd[2];
    end
end

always @(posedge clk) begin
    csr_prmd[31:3] <= 29'b0;
end

always @(posedge clk) begin
    if(reset) begin
        csr_estat[1:0] <= 2'b00;
        csr_estat[9:2] <= 8'b0;
    end
    else if (csr_we && csr_wnum == `ESTAT) begin
        csr_estat[1:0] <= csr_wmask[1:0] & csr_wvalue[1:0]
                        | ~csr_wmask[1:0] & csr_estat[1:0];
        csr_estat[9:2] <= intrpt[7:0];
    end
    else begin
        csr_estat[9:2] <= intrpt[7:0];
    end
    csr_estat[10] <= 1'b0;

    csr_estat[12] <= 1'b0;
end

always @(posedge clk) begin
    if(csr_tcfg[0] && timer_cnt == 32'b0)
        csr_estat[11] <= 1'b1;
    else if(csr_we && csr_wnum == `TICLR && csr_wmask[0] && csr_wvalue[0])
        csr_estat[11] <= 1'b0;
end

always @(posedge clk) begin
    if(wb_ex) begin
      csr_estat[21:16] <= wb_ecode;
      csr_estat[30:22] <= wb_esubcode;
    end
    csr_estat[15:13] <= 3'b0;
    csr_estat[31] <= 1'b0;
end

always @(posedge clk) begin
    if(wb_ex) 
        csr_era <= wb_pc;
    else if (csr_we && csr_wnum == `ERA)
        csr_era <= csr_wmask & csr_wvalue
                | ~csr_wmask & csr_era;
end

always @(posedge clk) begin
    if(csr_we && csr_wnum == `EENTRY)
        csr_eentry[31:6] <= csr_wmask[31:6] & csr_wvalue[31:6]
                         | ~csr_wmask[31:6] & csr_eentry[31:6];
    csr_eentry[5:0] <= 6'b0;
end

always @(posedge clk) begin
    if(csr_we && csr_wnum == `SAVE0)
        csr_save0 <= csr_wmask & csr_wvalue
                  | ~csr_wmask & csr_save0;
    if(csr_we && csr_wnum == `SAVE1)
        csr_save1 <= csr_wmask & csr_wvalue
                  | ~csr_wmask & csr_save1;
    if(csr_we && csr_wnum == `SAVE2)
        csr_save2 <= csr_wmask & csr_wvalue
                  | ~csr_wmask & csr_save2;
    if(csr_we && csr_wnum == `SAVE3)
        csr_save3 <= csr_wmask & csr_wvalue
                  | ~csr_wmask & csr_save3;
end

always @(posedge clk) begin
    if(reset) begin
        csr_ecfg[12:0] <= 13'b0;
    end
    else if (csr_we && csr_wnum == `ECFG) begin
        csr_ecfg[12:0] <= csr_wmask[12:0] & 13'h1bff & csr_wvalue[12:0]
                        | ~csr_wmask[12:0] & 13'h1bff & csr_ecfg[12:0];
    end
    csr_ecfg[31:13] <= 19'b0;
end

assign wb_ex_tlb = (wb_ecode == 6'h01 || wb_ecode == 6'h02 || wb_ecode == 6'h03 || wb_ecode == 6'h04 || wb_ecode == 6'h07 || wb_ecode == 6'h3f);
assign wb_ex_addr_err = ((wb_ecode == 6'h08 && wb_esubcode == 9'h0) || wb_ecode == 6'h09);
always @(posedge clk) begin
    if(wb_ex && (wb_ex_addr_err || wb_ex_tlb)) begin
        csr_badv <= ((wb_ecode == 6'h08 && wb_esubcode == 9'h0) || wb_ecode == 6'h03) ? wb_pc : wb_vaddr; 
    end else if(csr_we && csr_wnum == `BADV)
        csr_badv <= csr_wmask & csr_wvalue
                 | ~csr_wmask & csr_badv;
end

always @(posedge clk) begin
    if(reset)
        csr_tid <= 32'b0;
    else if(csr_we && csr_wnum == `TID)
        csr_tid <= csr_wmask & csr_wvalue
                | ~csr_wmask & csr_tid;
end

always @(posedge clk) begin
    if(reset)
        csr_tcfg[0] <= 1'b0;
    else if (csr_we && csr_wnum == `TCFG)
        csr_tcfg[0] <= csr_wmask[0] & csr_wvalue[0]
                    | ~csr_wmask[0] & csr_tcfg[0];
    if(csr_we && csr_wnum == `TCFG) begin
        csr_tcfg[1] <= csr_wmask[1] & csr_wvalue[1]
                    | ~csr_wmask[1] & csr_tcfg[1];
        csr_tcfg[31:2] <= csr_wmask[31:2] & csr_wvalue[31:2]
                       | ~csr_wmask[31:2] & csr_tcfg[31:2];
    end
end

assign tcfg_next_value = csr_wmask & csr_wvalue
                        | ~csr_wmask & csr_tcfg;

always @(posedge clk) begin
    if(reset)
        timer_cnt <= 32'hffffffff;
    else if (csr_we && csr_wnum == `TCFG && tcfg_next_value[0] )
        timer_cnt <= {tcfg_next_value[31:2],2'b0};
    else if (csr_tcfg[0] && timer_cnt != 32'hffffffff) begin
        if(timer_cnt == 32'b0 && csr_tcfg[1])
            timer_cnt <= {csr_tcfg[31:2],2'b0};
        else
            timer_cnt <= timer_cnt - 1'b1;
    end
end

assign csr_tval = timer_cnt;

always @(posedge clk) begin
    csr_ticlr <= 32'b0;
end

always @(posedge clk) begin
    if(reset)
        csr_timer_64 <= 64'b0;
    else
        csr_timer_64 <= csr_timer_64 + 1'b1;
end

always @(posedge clk) begin
    if(csr_we && csr_wnum == `ASID)
        csr_ASID[9:0] <= csr_wmask[9:0] & csr_wvalue[9:0]
                         | ~csr_wmask[9:0] & csr_ASID[9:0];
    else if(csr_we2_4tlb)
        csr_ASID[9:0] <= asid_wvalue[9:0];
    csr_ASID[15:10] <= 6'b0;
    csr_ASID[23:16] <= 8'd10;
    csr_ASID[31:24] <= 8'b0;
end

always @(posedge clk) begin
    if(csr_we && csr_wnum == `TLBIDX)
    begin
        csr_tlbidx[3:0] <= csr_wmask[3:0] & csr_wvalue[3:0]
                         | ~csr_wmask[3:0] & csr_tlbidx[3:0];
        csr_tlbidx[29:24] <= csr_wmask[29:24] & csr_wvalue[29:24]
                         | ~csr_wmask[29:24] & csr_tlbidx[29:24];
        csr_tlbidx[31] <= csr_wmask[31] & csr_wvalue[31]
                         | ~csr_wmask[31] & csr_tlbidx[31];
    end
    else if(csr_we2_4tlb)
    begin
        csr_tlbidx[29:24] <= tlbidx_wvalue[29:24];
        csr_tlbidx[31] <= tlbidx_wvalue[31];
    end
    csr_tlbidx[15: 4] <= 12'b0;
    csr_tlbidx[23:16] <= 8'b0;
    csr_tlbidx[30] <= 1'b0;
end

always @(posedge clk) begin
    if(wb_ex && wb_ex_tlb)
        csr_tlbehi[31:13] <= ((wb_ecode == 6'h08 && wb_esubcode == 9'h0) || wb_ecode == 6'h03) ? wb_pc[31:13] : wb_vaddr[31:13];
    else if(csr_we && csr_wnum == `TLBEHI)
        csr_tlbehi[31:13] <= csr_wmask[31:13] & csr_wvalue[31:13]
                         | ~csr_wmask[31:13] & csr_tlbehi[31:13];
    else if(csr_we2_4tlb)
        csr_tlbehi[31:13] <= tlbehi_wvalue[31:13];
    csr_tlbehi[12:0] <= 12'b0;
end

always @(posedge clk) begin
    if(csr_we && csr_wnum == `TLBELO0)
    begin
        csr_tlbelo0[6:0] <= csr_wmask[6:0] & csr_wvalue[6:0]
                         | ~csr_wmask[6:0] & csr_tlbelo0[6:0];
        csr_tlbelo0[27:8] <= csr_wmask[27:8] & csr_wvalue[27:8]
                         | ~csr_wmask[27:8] & csr_tlbelo0[27:8];
    end
    else if(csr_we2_4tlb)
    begin
        csr_tlbelo0[6:0] <= tlbelo0_wvalue[6:0];
        csr_tlbelo0[27:8] <= tlbelo0_wvalue[27:8];
    end
    csr_tlbelo0[7] <= 1'b0;
    csr_tlbelo0[31:28] <= 4'b0;
end

always @(posedge clk) begin
    if(csr_we && csr_wnum == `TLBELO1)
    begin
        csr_tlbelo1[6:0] <= csr_wmask[6:0] & csr_wvalue[6:0]
                         | ~csr_wmask[6:0] & csr_tlbelo1[6:0];
        csr_tlbelo1[27:8] <= csr_wmask[27:8] & csr_wvalue[27:8]
                         | ~csr_wmask[27:8] & csr_tlbelo1[27:8];
    end
    else if(csr_we2_4tlb)
    begin
        csr_tlbelo1[6:0] <= tlbelo1_wvalue[6:0];
        csr_tlbelo1[27:8] <= tlbelo1_wvalue[27:8];
    end
    csr_tlbelo1[7] <= 1'b0;
    csr_tlbelo1[31:28] <= 4'b0;
end

always @(posedge clk) begin
    if(csr_we && csr_wnum == `TLBENTRY)
        csr_tlbentry[31:6] <= csr_wmask[31:6] & csr_wvalue[31:6]
                         | ~csr_wmask[31:6] & csr_tlbentry[31:6];
    csr_tlbentry[5:0] <= 6'b0;
end

always @(posedge clk) begin
    if(reset)
    begin
        csr_dmw0[0] <= 1'b0;
        csr_dmw0[3] <= 1'b0;
    end
    else if(csr_we && csr_wnum == `TLBDMW0)
    begin
        csr_dmw0[0] <= csr_wmask[0] & csr_wvalue[0]
                         | ~csr_wmask[0] & csr_dmw0[0];
        csr_dmw0[5:3] <= csr_wmask[5:3] & csr_wvalue[5:3]
                         | ~csr_wmask[5:3] & csr_dmw0[5:3];
        csr_dmw0[27:25] <= csr_wmask[27:25] & csr_wvalue[27:25]
                         | ~csr_wmask[27:25] & csr_dmw0[27:25];
        csr_dmw0[31:29] <= csr_wmask[31:29] & csr_wvalue[31:29]
                         | ~csr_wmask[31:29] & csr_dmw0[31:29]; 
    end
    csr_dmw0[2:1] <= 2'b0;
    csr_dmw0[24:6] <= 19'b0;
    csr_dmw0[28] <= 1'b0; 
end

always @(posedge clk) begin
    if(reset)
    begin
        csr_dmw1[0] <= 1'b0;
        csr_dmw1[3] <= 1'b0;
    end
    else if(csr_we && csr_wnum == `TLBDMW1)
    begin
        csr_dmw1[0] <= csr_wmask[0] & csr_wvalue[0]
                         | ~csr_wmask[0] & csr_dmw1[0];
        csr_dmw1[5:3] <= csr_wmask[5:3] & csr_wvalue[5:3]
                         | ~csr_wmask[5:3] & csr_dmw1[5:3];
        csr_dmw1[27:25] <= csr_wmask[27:25] & csr_wvalue[27:25]
                         | ~csr_wmask[27:25] & csr_dmw1[27:25];
        csr_dmw1[31:29] <= csr_wmask[31:29] & csr_wvalue[31:29]
                         | ~csr_wmask[31:29] & csr_dmw1[31:29]; 
    end
    csr_dmw1[2:1] <= 2'b0;
    csr_dmw1[24:6] <= 19'b0;
    csr_dmw1[28] <= 1'b0;
end

always @(posedge clk) begin
    if(csr_we && csr_wnum == `PGDL)
    begin
        csr_pgdl[31:12]  <= csr_wmask[31:12] & csr_wvalue[31:12]
                         | ~csr_wmask[31:12] & csr_pgdl[31:12];
    end
    csr_pgdl[11:0] <= 12'b0;
end

always @(posedge clk) begin
    if(csr_we && csr_wnum == `PGDH)
    begin
        csr_pgdh[31:12]  <= csr_wmask[31:12] & csr_wvalue[31:12]
                         | ~csr_wmask[31:12] & csr_pgdh[31:12];
    end
    csr_pgdh[11:0] <= 12'b0;
end

assign csr_pgd[11:0] = 12'b0;
assign csr_pgd[31:12] = csr_badv[31] ? csr_pgdh[31:12] : csr_pgdl[31:12];

always @(posedge clk) begin
    if(reset) begin
        csr_llbctl[0] <= 1'b0;
        csr_llbctl[2] <= 1'b0; 
    end 
    else if(ertn_flush) begin
        csr_llbctl[0] <= csr_llbctl[2] ? csr_llbctl[0] : 1'b0;
        csr_llbctl[2] <= 1'b0; 
    end
    else if(csr_we && csr_wnum == `LLBCTL)
    begin
        csr_llbctl[2]  <= csr_wmask[2] & csr_wvalue[2]
                         | ~csr_wmask[2] & csr_llbctl[2];
        csr_llbctl[0]  <= (csr_wmask[1] & csr_wvalue[1]) ? 1'b0 : csr_llbctl[0];
    end
    else if(csr_we && csr_wnum == `LLBit) begin
        csr_llbctl[0] <= csr_wvalue[0]; 
    end
    csr_llbctl[1] <= 1'b0; 
    csr_llbctl[31:3] <= 29'b0;
end

assign llbit = csr_llbctl[0];


assign csr_rvalue = ({32{csr_rnum == `CRMD    }} & csr_crmd)   |
                    ({32{csr_rnum == `PRMD    }} & csr_prmd)   |
                    ({32{csr_rnum == `ESTAT   }} & csr_estat)  |
                    ({32{csr_rnum == `ERA     }} & csr_era)    |
                    ({32{csr_rnum == `EENTRY  }} & csr_eentry) |
                    ({32{csr_rnum == `SAVE0   }} & csr_save0)  |
                    ({32{csr_rnum == `SAVE1   }} & csr_save1)  |
                    ({32{csr_rnum == `SAVE2   }} & csr_save2)  |
                    ({32{csr_rnum == `SAVE3   }} & csr_save3)  |
                    ({32{csr_rnum == `ECFG    }} & csr_ecfg)   |
                    ({32{csr_rnum == `BADV    }} & csr_badv)   |
                    ({32{csr_rnum == `TID     }} & csr_tid)    |
                    ({32{csr_rnum == `TCFG    }} & csr_tcfg)   |
                    ({32{csr_rnum == `TVAL    }} & csr_tval)   |
                    ({32{csr_rnum == `TICLR   }} & csr_ticlr)  |
                    ({32{csr_rnum == `RDCNTVL }} & csr_timer_64[31:0]) |
                    ({32{csr_rnum == `RDCNTVH }} & csr_timer_64[63:32]) |
                    ({32{csr_rnum == `RDCNTID }} & csr_tid)    |
                    ({32{csr_rnum == `ASID    }} & csr_ASID)   |
                    ({32{csr_rnum == `TLBIDX  }} & csr_tlbidx) |
                    ({32{csr_rnum == `TLBEHI  }} & csr_tlbehi) |
                    ({32{csr_rnum == `TLBELO0 }} & csr_tlbelo0) |
                    ({32{csr_rnum == `TLBELO1 }} & csr_tlbelo1) |
                    ({32{csr_rnum == `TLBENTRY}} & csr_tlbentry) |
                    ({32{csr_rnum == `TLBDMW0 }} & csr_dmw0) |
                    ({32{csr_rnum == `TLBDMW1 }} & csr_dmw1) |
                    ({32{csr_rnum == `LLBit   }} & {31'b0,llbit}) |
                    ({32{csr_rnum == `PGDL    }} & csr_pgdl)   |
                    ({32{csr_rnum == `PGDH    }} & csr_pgdh)   |
                    ({32{csr_rnum == `PGD     }} & csr_pgd)    |
                    ({32{csr_rnum == `LLBCTL  }} & csr_llbctl) ;

assign csr_rvalue2 = ({32{csr_rnum2 == `CRMD    }} & csr_crmd)   |
                    ({32{csr_rnum2 == `PRMD    }} & csr_prmd)   |
                    ({32{csr_rnum2 == `ESTAT   }} & csr_estat)  |
                    ({32{csr_rnum2 == `ERA     }} & csr_era)    |
                    ({32{csr_rnum2 == `EENTRY  }} & csr_eentry) |
                    ({32{csr_rnum2 == `SAVE0   }} & csr_save0)  |
                    ({32{csr_rnum2 == `SAVE1   }} & csr_save1)  |
                    ({32{csr_rnum2 == `SAVE2   }} & csr_save2)  |
                    ({32{csr_rnum2 == `SAVE3   }} & csr_save3)  |
                    ({32{csr_rnum2 == `ECFG    }} & csr_ecfg)   |
                    ({32{csr_rnum2 == `BADV    }} & csr_badv)   |
                    ({32{csr_rnum2 == `TID     }} & csr_tid)    |
                    ({32{csr_rnum2 == `TCFG    }} & csr_tcfg)   |
                    ({32{csr_rnum2 == `TVAL    }} & csr_tval)   |
                    ({32{csr_rnum2 == `TICLR   }} & csr_ticlr)  |
                    ({32{csr_rnum2 == `RDCNTVL }} & csr_timer_64[31:0]) |
                    ({32{csr_rnum2 == `RDCNTVH }} & csr_timer_64[63:32]) |
                    ({32{csr_rnum2 == `RDCNTID }} & csr_tid)    |
                    ({32{csr_rnum2 == `ASID    }} & csr_ASID)   |
                    ({32{csr_rnum2 == `TLBIDX  }} & csr_tlbidx) |
                    ({32{csr_rnum2 == `TLBEHI  }} & csr_tlbehi) |
                    ({32{csr_rnum2 == `TLBELO0 }} & csr_tlbelo0) |
                    ({32{csr_rnum2 == `TLBELO1 }} & csr_tlbelo1) |
                    ({32{csr_rnum2 == `TLBENTRY}} & csr_tlbentry) |
                    ({32{csr_rnum2 == `TLBDMW0 }} & csr_dmw0) |
                    ({32{csr_rnum2 == `TLBDMW1 }} & csr_dmw1) |
                    ({32{csr_rnum2 == `LLBit   }} & {31'b0,llbit}) |
                    ({32{csr_rnum2 == `PGDL    }} & csr_pgdl)   |
                    ({32{csr_rnum2 == `PGDH    }} & csr_pgdh)   |
                    ({32{csr_rnum2 == `PGD     }} & csr_pgd)    |
                    ({32{csr_rnum2 == `LLBCTL  }} & csr_llbctl) ;

`ifdef DIFFTEST_EN
assign csr_crmd_diff     = csr_crmd;
assign csr_prmd_diff     = csr_prmd;
assign csr_ectl_diff     = csr_ecfg;
assign csr_estat_diff    = csr_estat;
assign csr_era_diff      = csr_era;
assign csr_badv_diff     = csr_badv;
assign csr_eentry_diff   = csr_eentry;
assign csr_tlbidx_diff   = csr_tlbidx;
assign csr_tlbehi_diff   = csr_tlbehi;
assign csr_tlbelo0_diff  = csr_tlbelo0;
assign csr_tlbelo1_diff  = csr_tlbelo1;
assign csr_asid_diff     = csr_ASID;
assign csr_save0_diff    = csr_save0;
assign csr_save1_diff    = csr_save1;
assign csr_save2_diff    = csr_save2;
assign csr_save3_diff    = csr_save3;
assign csr_tid_diff      = csr_tid;
assign csr_tcfg_diff     = csr_tcfg;
assign csr_tval_diff     = csr_tval;
assign csr_ticlr_diff    = csr_ticlr;
assign csr_llbctl_diff   = csr_llbctl;
assign csr_tlbrentry_diff = csr_tlbentry;
assign csr_dmw0_diff     = csr_dmw0;
assign csr_dmw1_diff     = csr_dmw1;
assign csr_pgdl_diff     = csr_pgdl;
assign csr_pgdh_diff     = csr_pgdh;
assign csr_timer_64_diff = csr_timer_64;
`endif

/*always @(posedge clk) begin
    if (reset) begin
        csr_ovalue <= 32'b0;
    end else if (csr_we) begin
        case (csr_wnum)
            `CRMD:     csr_ovalue <= csr_crmd;
            `PRMD:     csr_ovalue <= csr_prmd;
            `ESTAT:    csr_ovalue <= csr_estat;
            `ERA:      csr_ovalue <= csr_era;
            `EENTRY:   csr_ovalue <= csr_eentry;
            `SAVE0:    csr_ovalue <= csr_save0;
            `SAVE1:    csr_ovalue <= csr_save1;
            `SAVE2:    csr_ovalue <= csr_save2;
            `SAVE3:    csr_ovalue <= csr_save3;
            `ECFG:     csr_ovalue <= csr_ecfg;
            `BADV:     csr_ovalue <= csr_badv;
            `TID:      csr_ovalue <= csr_tid;
            `TCFG:     csr_ovalue <= csr_tcfg;
            `TVAL:     csr_ovalue <= csr_tval;
            `TICLR:    csr_ovalue <= csr_ticlr;
            `ASID:     csr_ovalue <= csr_ASID;
            `TLBIDX:   csr_ovalue <= csr_tlbidx;
            `TLBEHI:   csr_ovalue <= csr_tlbehi;
            `TLBELO0:  csr_ovalue <= csr_tlbelo0;
            `TLBELO1:  csr_ovalue <= csr_tlbelo1;
            `TLBENTRY: csr_ovalue <= csr_tlbentry;
            `TLBDMW0:  csr_ovalue <= csr_dmw0;
            `TLBDMW1:  csr_ovalue <= csr_dmw1;
            `PGDL:     csr_ovalue <= csr_pgdl;
            `PGDH:     csr_ovalue <= csr_pgdh;
            `LLBCTL:   csr_ovalue <= csr_llbctl;
            default:   csr_ovalue <= csr_ovalue; // 保持原�??
        endcase
    end
    // 若csr_we=0，则csr_ovalue保持不变（隐式行为）
end

assign csr_rovalue = csr_ovalue;
*/
assign ex_entry = (wb_ecode == 6'h3f) ? csr_tlbentry : csr_eentry;
assign ex_exit  = csr_era;
assign has_int = (((csr_estat[12:0] & csr_ecfg[12:0]) != 13'h0000) && (csr_crmd[2] == 1'b1));
assign csr_asid = csr_ASID[9:0];
assign csr_vppn = csr_tlbehi[31:13];
assign tlbelo0_rvalue = csr_tlbelo0;
assign tlbelo1_rvalue = csr_tlbelo1;
assign tlbidx_rvalue = csr_tlbidx;
assign csr_ecode = csr_estat[21:16];
assign dmw0 = csr_dmw0;
assign dmw1 = csr_dmw1;
assign crmd = csr_crmd;




endmodule
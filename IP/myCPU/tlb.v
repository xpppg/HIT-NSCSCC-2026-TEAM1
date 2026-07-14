module tlb
(
    input wire clk,
    // search port 0 (for fetch)
    input wire [ 18:0] s0_vppn,
    input wire s0_va_bit12,
    input wire [ 9:0] s0_asid,
    output wire s0_found,
    output wire [ 3:0] s0_index,
    output wire [ 19:0] s0_ppn,
    output wire [ 5:0] s0_ps,
    output wire [ 1:0] s0_plv,
    output wire [ 1:0] s0_mat,
    output wire s0_d,
    output wire s0_v,
    // search port 1 (for load/store)
    input wire [ 18:0] s1_vppn,
    input wire s1_va_bit12,
    input wire [ 9:0] s1_asid,
    output wire s1_found,
    output wire [ 3:0] s1_index,
    output wire [ 19:0] s1_ppn,
    output wire [ 5:0] s1_ps,
    output wire [ 1:0] s1_plv,
    output wire [ 1:0] s1_mat,
    output wire s1_d,
    output wire s1_v,
    // invtlb opcode
    input wire invtlb_valid,
    input wire [ 4:0] invtlb_op,
    input wire [ 18:0] invtlb_vppn,
    input wire [  9:0] invtlb_asid,
    // write port
    input wire we, //w(rite) e(nable)
    input wire [ 3:0] w_index,
    input wire w_e,
    input wire [ 18:0] w_vppn,
    input wire [ 5:0] w_ps,
    input wire [ 9:0] w_asid,
    input wire w_g,
    input wire [ 19:0] w_ppn0,
    input wire [ 1:0] w_plv0,
    input wire [ 1:0] w_mat0,
    input wire w_d0,
    input wire w_v0,
    input wire [ 19:0] w_ppn1,
    input wire [ 1:0] w_plv1,
    input wire [ 1:0] w_mat1,
    input wire w_d1,
    input wire w_v1,
    // read port
    input wire [ 3:0] r_index,
    output wire r_e,
    output wire [ 18:0] r_vppn,
    output wire [ 5:0] r_ps,
    output wire [ 9:0] r_asid,
    output wire r_g,
    output wire [ 19:0] r_ppn0,
    output wire [ 1:0] r_plv0,
    output wire [ 1:0] r_mat0,
    output wire r_d0,
    output wire r_v0,
    output wire [ 19:0] r_ppn1,
    output wire [ 1:0] r_plv1,
    output wire [ 1:0] r_mat1,
    output wire r_d1,
    output wire r_v1
);
reg [15:0] tlb_e;
reg [15:0] tlb_ps; //pagesize 1:4MB, 0:4KB
reg [ 18:0] tlb_vppn [15:0];
reg [ 9:0] tlb_asid [15:0];
reg tlb_g [15:0];
reg [ 19:0] tlb_ppn0 [15:0];
reg [ 1:0] tlb_plv0 [15:0];
reg [ 1:0] tlb_mat0 [15:0];
reg tlb_d0 [15:0];
reg tlb_v0 [15:0];
reg [ 19:0] tlb_ppn1 [15:0];
reg [ 1:0] tlb_plv1 [15:0];
reg [ 1:0] tlb_mat1 [15:0];
reg tlb_d1 [15:0];
reg tlb_v1 [15:0];

wire [15:0] match0;
wire [15:0] match1;
wire [15:0] inv_match;

//WRITE
always @(posedge clk) begin
    if (we) begin
        tlb_e[w_index] <= w_e;
        tlb_ps[w_index] <= (w_ps == 6'd21) ? 1'b1 : 1'b0;
        tlb_vppn[w_index] <= w_vppn;
        tlb_asid[w_index] <= w_asid;
        tlb_g[w_index] <= w_g;
        tlb_ppn0[w_index] <= w_ppn0;
        tlb_plv0[w_index] <= w_plv0;
        tlb_mat0[w_index] <= w_mat0;
        tlb_d0[w_index] <= w_d0;
        tlb_v0[w_index] <= w_v0;
        tlb_ppn1[w_index] <= w_ppn1;
        tlb_plv1[w_index] <= w_plv1;
        tlb_mat1[w_index] <= w_mat1;
        tlb_d1[w_index] <= w_d1;
        tlb_v1[w_index] <= w_v1;
    end
    else if(invtlb_valid) begin
        tlb_e <= tlb_e & ~inv_match;
    end
end

//READ OUT 
assign r_e = tlb_e[r_index];
assign r_vppn = tlb_vppn[r_index];
assign r_ps = tlb_ps[r_index] ? 6'd21 : 6'd12; // 1:4MB, 0:4KB
assign r_asid = tlb_asid[r_index];
assign r_g = tlb_g[r_index];
assign r_ppn0 = tlb_ppn0[r_index];
assign r_plv0 = tlb_plv0[r_index];
assign r_mat0 = tlb_mat0[r_index];
assign r_d0 = tlb_d0[r_index];
assign r_v0 = tlb_v0[r_index];
assign r_ppn1 = tlb_ppn1[r_index];
assign r_plv1 = tlb_plv1[r_index];
assign r_mat1 = tlb_mat1[r_index];
assign r_d1 = tlb_d1[r_index];
assign r_v1 = tlb_v1[r_index];

//SEARCH PORT 0
assign match0[ 0] = (s0_vppn[18:9] == tlb_vppn[ 0][18:9])
                && (tlb_ps[ 0] || s0_vppn[8:0] == tlb_vppn[ 0][8:0])
                && ((s0_asid==tlb_asid[ 0]) || tlb_g[ 0]) && tlb_e[0];
assign match0[ 1] = (s0_vppn[18:9] == tlb_vppn[ 1][18:9])
                && (tlb_ps[ 1] || s0_vppn[8:0] == tlb_vppn[ 1][8:0])
                && ((s0_asid==tlb_asid[ 1]) || tlb_g[ 1]) && tlb_e[1];
assign match0[ 2] = (s0_vppn[18:9] == tlb_vppn[ 2][18:9])
                && (tlb_ps[ 2] || s0_vppn[8:0] == tlb_vppn[ 2][8:0])
                && ((s0_asid==tlb_asid[ 2]) || tlb_g[ 2]) && tlb_e[2];
assign match0[ 3] = (s0_vppn[18:9] == tlb_vppn[ 3][18:9])
                && (tlb_ps[ 3] || s0_vppn[8:0] == tlb_vppn[ 3][8:0])
                && ((s0_asid==tlb_asid[ 3]) || tlb_g[ 3]) && tlb_e[3];
assign match0[ 4] = (s0_vppn[18:9] == tlb_vppn[ 4][18:9])
                && (tlb_ps[ 4] || s0_vppn[8:0] == tlb_vppn[ 4][8:0])
                && ((s0_asid==tlb_asid[ 4]) || tlb_g[ 4]) && tlb_e[4];
assign match0[ 5] = (s0_vppn[18:9] == tlb_vppn[ 5][18:9])
                && (tlb_ps[ 5] || s0_vppn[8:0] == tlb_vppn[ 5][8:0])
                && ((s0_asid==tlb_asid[ 5]) || tlb_g[ 5]) && tlb_e[5];
assign match0[ 6] = (s0_vppn[18:9] == tlb_vppn[ 6][18:9])
                && (tlb_ps[ 6] || s0_vppn[8:0] == tlb_vppn[ 6][8:0])
                && ((s0_asid==tlb_asid[ 6]) || tlb_g[ 6]) && tlb_e[6];
assign match0[ 7] = (s0_vppn[18:9] == tlb_vppn[ 7][18:9])
                && (tlb_ps[ 7] || s0_vppn[8:0] == tlb_vppn[ 7][8:0])
                && ((s0_asid==tlb_asid[ 7]) || tlb_g[ 7]) && tlb_e[7];
assign match0[ 8] = (s0_vppn[18:9] == tlb_vppn[ 8][18:9])
                && (tlb_ps[ 8] || s0_vppn[8:0] == tlb_vppn[ 8][8:0])
                && ((s0_asid==tlb_asid[ 8]) || tlb_g[ 8]) && tlb_e[8];
assign match0[ 9] = (s0_vppn[18:9] == tlb_vppn[ 9][18:9])
                && (tlb_ps[ 9] || s0_vppn[8:0] == tlb_vppn[ 9][8:0])
                && ((s0_asid==tlb_asid[ 9]) || tlb_g[ 9]) && tlb_e[9];
assign match0[10] = (s0_vppn[18:9] == tlb_vppn[10][18:9])
                && (tlb_ps[10] || s0_vppn[8:0] == tlb_vppn[10][8:0])
                && ((s0_asid==tlb_asid[10]) || tlb_g[10]) && tlb_e[10];
assign match0[11] = (s0_vppn[18:9] == tlb_vppn[11][18:9])
                && (tlb_ps[11] || s0_vppn[8:0] == tlb_vppn[11][8:0])
                && ((s0_asid==tlb_asid[11]) || tlb_g[11]) && tlb_e[11];
assign match0[12] = (s0_vppn[18:9] == tlb_vppn[12][18:9])
                && (tlb_ps[12] || s0_vppn[8:0] == tlb_vppn[12][8:0])
                && ((s0_asid==tlb_asid[12]) || tlb_g[12]) && tlb_e[12];
assign match0[13] = (s0_vppn[18:9] == tlb_vppn[13][18:9])
                && (tlb_ps[13] || s0_vppn[8:0] == tlb_vppn[13][8:0])
                && ((s0_asid==tlb_asid[13]) || tlb_g[13]) && tlb_e[13];
assign match0[14] = (s0_vppn[18:9] == tlb_vppn[14][18:9])
                && (tlb_ps[14] || s0_vppn[8:0] == tlb_vppn[14][8:0])
                && ((s0_asid==tlb_asid[14]) || tlb_g[14]) && tlb_e[14];
assign match0[15] = (s0_vppn[18:9] == tlb_vppn[15][18:9])
                && (tlb_ps[15] || s0_vppn[8:0] == tlb_vppn[15][8:0])
                && ((s0_asid==tlb_asid[15]) || tlb_g[15]) && tlb_e[15];

assign s0_index = ({4{match0[0]}} & 4'd0) |
                  ({4{match0[1]}} & 4'd1) |
                  ({4{match0[2]}} & 4'd2) |
                  ({4{match0[3]}} & 4'd3) |
                  ({4{match0[4]}} & 4'd4) |
                  ({4{match0[5]}} & 4'd5) |
                  ({4{match0[6]}} & 4'd6) |
                  ({4{match0[7]}} & 4'd7) |
                  ({4{match0[8]}} & 4'd8) |
                  ({4{match0[9]}} & 4'd9) |
                  ({4{match0[10]}} & 4'd10) |
                  ({4{match0[11]}} & 4'd11) |
                  ({4{match0[12]}} & 4'd12) |
                  ({4{match0[13]}} & 4'd13) |
                  ({4{match0[14]}} & 4'd14) |
                  ({4{match0[15]}} & 4'd15) ;

assign s0_found = match0[0] || match0[1] || match0[2] || match0[3]
                || match0[4] || match0[5] || match0[6] || match0[7] 
                || match0[8] || match0[9] || match0[10] || match0[11]
                || match0[12] || match0[13] || match0[14] || match0[15] ;
assign s0_ppn = ({20{match0[0]}} & {20{~(tlb_ps[0] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[0]) |
                ({20{match0[1]}} & {20{~(tlb_ps[1] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[1]) |
                ({20{match0[2]}} & {20{~(tlb_ps[2] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[2]) |
                ({20{match0[3]}} & {20{~(tlb_ps[3] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[3]) |
                ({20{match0[4]}} & {20{~(tlb_ps[4] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[4]) |
                ({20{match0[5]}} & {20{~(tlb_ps[5] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[5]) |
                ({20{match0[6]}} & {20{~(tlb_ps[6] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[6]) |
                ({20{match0[7]}} & {20{~(tlb_ps[7] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[7]) |
                ({20{match0[8]}} & {20{~(tlb_ps[8] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[8]) |
                ({20{match0[9]}} & {20{~(tlb_ps[9] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[9]) |
                ({20{match0[10]}} & {20{~(tlb_ps[10] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[10]) |
                ({20{match0[11]}} & {20{~(tlb_ps[11] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[11]) |
                ({20{match0[12]}} & {20{~(tlb_ps[12] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[12]) |
                ({20{match0[13]}} & {20{~(tlb_ps[13] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[13]) |
                ({20{match0[14]}} & {20{~(tlb_ps[14] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[14]) |
                ({20{match0[15]}} & {20{~(tlb_ps[15] ? s0_vppn[8] : s0_va_bit12)}} & tlb_ppn0[15]) |
                ({20{match0[ 0]}} & {20{tlb_ps[0] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 0]) |
                ({20{match0[ 1]}} & {20{tlb_ps[1] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 1]) |
                ({20{match0[ 2]}} & {20{tlb_ps[2] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 2]) |
                ({20{match0[ 3]}} & {20{tlb_ps[3] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 3]) |
                ({20{match0[ 4]}} & {20{tlb_ps[4] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 4]) |
                ({20{match0[ 5]}} & {20{tlb_ps[5] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 5]) |
                ({20{match0[ 6]}} & {20{tlb_ps[6] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 6]) |
                ({20{match0[ 7]}} & {20{tlb_ps[7] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 7]) |
                ({20{match0[ 8]}} & {20{tlb_ps[8] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 8]) |
                ({20{match0[ 9]}} & {20{tlb_ps[9] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[ 9]) |
                ({20{match0[10]}} & {20{tlb_ps[10] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[10]) |
                ({20{match0[11]}} & {20{tlb_ps[11] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[11]) |
                ({20{match0[12]}} & {20{tlb_ps[12] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[12]) |
                ({20{match0[13]}} & {20{tlb_ps[13] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[13]) |
                ({20{match0[14]}} & {20{tlb_ps[14] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[14]) |
                ({20{match0[15]}} & {20{tlb_ps[15] ? s0_vppn[8] : s0_va_bit12}} & tlb_ppn1[15]) ;

assign s0_ps = ({6{match0[0]}} & (tlb_ps[0] ? 6'd21 : 6'd12)) |
                ({6{match0[1]}} & (tlb_ps[1] ? 6'd21 : 6'd12)) |
                ({6{match0[2]}} & (tlb_ps[2] ? 6'd21 : 6'd12)) |
                ({6{match0[3]}} & (tlb_ps[3] ? 6'd21 : 6'd12)) |
                ({6{match0[4]}} & (tlb_ps[4] ? 6'd21 : 6'd12)) |
                ({6{match0[5]}} & (tlb_ps[5] ? 6'd21 : 6'd12)) |
                ({6{match0[6]}} & (tlb_ps[6] ? 6'd21 : 6'd12)) |
                ({6{match0[7]}} & (tlb_ps[7] ? 6'd21 : 6'd12)) |
                ({6{match0[8]}} & (tlb_ps[8] ? 6'd21 : 6'd12)) |
                ({6{match0[9]}} & (tlb_ps[9] ? 6'd21 : 6'd12)) |
                ({6{match0[10]}} & (tlb_ps[10] ? 6'd21 : 6'd12)) |
                ({6{match0[11]}} & (tlb_ps[11] ? 6'd21 : 6'd12)) |
                ({6{match0[12]}} & (tlb_ps[12] ? 6'd21 : 6'd12)) |
                ({6{match0[13]}} & (tlb_ps[13] ? 6'd21 : 6'd12)) |
                ({6{match0[14]}} & (tlb_ps[14] ? 6'd21 : 6'd12)) |
                ({6{match0[15]}} & (tlb_ps[15] ? 6'd21 : 6'd12)) ;

assign s0_plv = ({2{match0[0]}} & {2{~(tlb_ps[0] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[0]) |
                ({2{match0[1]}} & {2{~(tlb_ps[1] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[1]) |
                ({2{match0[2]}} & {2{~(tlb_ps[2] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[2]) |
                ({2{match0[3]}} & {2{~(tlb_ps[3] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[3]) |
                ({2{match0[4]}} & {2{~(tlb_ps[4] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[4]) |
                ({2{match0[5]}} & {2{~(tlb_ps[5] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[5]) |
                ({2{match0[6]}} & {2{~(tlb_ps[6] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[6]) |
                ({2{match0[7]}} & {2{~(tlb_ps[7] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[7]) |
                ({2{match0[8]}} & {2{~(tlb_ps[8] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[8]) |
                ({2{match0[9]}} & {2{~(tlb_ps[9] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[9]) |
                ({2{match0[10]}} & {2{~(tlb_ps[10] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[10]) |
                ({2{match0[11]}} & {2{~(tlb_ps[11] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[11]) |
                ({2{match0[12]}} & {2{~(tlb_ps[12] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[12]) |
                ({2{match0[13]}} & {2{~(tlb_ps[13] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[13]) |
                ({2{match0[14]}} & {2{~(tlb_ps[14] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[14]) |
                ({2{match0[15]}} & {2{~(tlb_ps[15] ? s0_vppn[8] : s0_va_bit12)}} & tlb_plv0[15]) |
                ({2{match0[ 0]}} & {2{tlb_ps[0] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 0]) |
                ({2{match0[ 1]}} & {2{tlb_ps[1] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 1]) |
                ({2{match0[ 2]}} & {2{tlb_ps[2] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 2]) |
                ({2{match0[ 3]}} & {2{tlb_ps[3] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 3]) |
                ({2{match0[ 4]}} & {2{tlb_ps[4] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 4]) |
                ({2{match0[ 5]}} & {2{tlb_ps[5] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 5]) |
                ({2{match0[ 6]}} & {2{tlb_ps[6] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 6]) |
                ({2{match0[ 7]}} & {2{tlb_ps[7] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 7]) |
                ({2{match0[ 8]}} & {2{tlb_ps[8] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 8]) |
                ({2{match0[ 9]}} & {2{tlb_ps[9] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[ 9]) |
                ({2{match0[10]}} & {2{tlb_ps[10] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[10]) |
                ({2{match0[11]}} & {2{tlb_ps[11] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[11]) |
                ({2{match0[12]}} & {2{tlb_ps[12] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[12]) |
                ({2{match0[13]}} & {2{tlb_ps[13] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[13]) |
                ({2{match0[14]}} & {2{tlb_ps[14] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[14]) |
                ({2{match0[15]}} & {2{tlb_ps[15] ? s0_vppn[8] : s0_va_bit12}} & tlb_plv1[15]) ;

assign s0_mat = ({2{match0[0]}} & {2{~(tlb_ps[0] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[0]) |
                ({2{match0[1]}} & {2{~(tlb_ps[1] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[1]) |
                ({2{match0[2]}} & {2{~(tlb_ps[2] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[2]) |
                ({2{match0[3]}} & {2{~(tlb_ps[3] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[3]) |
                ({2{match0[4]}} & {2{~(tlb_ps[4] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[4]) |
                ({2{match0[5]}} & {2{~(tlb_ps[5] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[5]) |
                ({2{match0[6]}} & {2{~(tlb_ps[6] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[6]) |
                ({2{match0[7]}} & {2{~(tlb_ps[7] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[7]) |
                ({2{match0[8]}} & {2{~(tlb_ps[8] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[8]) |
                ({2{match0[9]}} & {2{~(tlb_ps[9] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[9]) |
                ({2{match0[10]}} & {2{~(tlb_ps[10] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[10]) |
                ({2{match0[11]}} & {2{~(tlb_ps[11] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[11]) |
                ({2{match0[12]}} & {2{~(tlb_ps[12] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[12]) |
                ({2{match0[13]}} & {2{~(tlb_ps[13] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[13]) |
                ({2{match0[14]}} & {2{~(tlb_ps[14] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[14]) |
                ({2{match0[15]}} & {2{~(tlb_ps[15] ? s0_vppn[8] : s0_va_bit12)}} & tlb_mat0[15]) |
                ({2{match0[ 0]}} & {2{tlb_ps[0] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 0]) |
                ({2{match0[ 1]}} & {2{tlb_ps[1] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 1]) |
                ({2{match0[ 2]}} & {2{tlb_ps[2] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 2]) |
                ({2{match0[ 3]}} & {2{tlb_ps[3] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 3]) |
                ({2{match0[ 4]}} & {2{tlb_ps[4] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 4]) |
                ({2{match0[ 5]}} & {2{tlb_ps[5] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 5]) |
                ({2{match0[ 6]}} & {2{tlb_ps[6] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 6]) |
                ({2{match0[ 7]}} & {2{tlb_ps[7] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 7]) |
                ({2{match0[ 8]}} & {2{tlb_ps[8] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 8]) |
                ({2{match0[ 9]}} & {2{tlb_ps[9] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[ 9]) |
                ({2{match0[10]}} & {2{tlb_ps[10] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[10]) |
                ({2{match0[11]}} & {2{tlb_ps[11] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[11]) |
                ({2{match0[12]}} & {2{tlb_ps[12] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[12]) |
                ({2{match0[13]}} & {2{tlb_ps[13] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[13]) |
                ({2{match0[14]}} & {2{tlb_ps[14] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[14]) |
                ({2{match0[15]}} & {2{tlb_ps[15] ? s0_vppn[8] : s0_va_bit12}} & tlb_mat1[15]) ;

assign s0_d = (match0[0] & ~(tlb_ps[0] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[0]) |
              (match0[1] & ~(tlb_ps[1] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[1]) |
              (match0[2] & ~(tlb_ps[2] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[2]) |
              (match0[3] & ~(tlb_ps[3] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[3]) |
              (match0[4] & ~(tlb_ps[4] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[4]) |
              (match0[5] & ~(tlb_ps[5] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[5]) |
              (match0[6] & ~(tlb_ps[6] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[6]) |
              (match0[7] & ~(tlb_ps[7] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[7]) |
              (match0[8] & ~(tlb_ps[8] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[8]) |
              (match0[9] & ~(tlb_ps[9] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[9]) |
              (match0[10] & ~(tlb_ps[10] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[10]) |
              (match0[11] & ~(tlb_ps[11] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[11]) |
              (match0[12] & ~(tlb_ps[12] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[12]) |
              (match0[13] & ~(tlb_ps[13] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[13]) |
              (match0[14] & ~(tlb_ps[14] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[14]) |
              (match0[15] & ~(tlb_ps[15] ? s0_vppn[8] : s0_va_bit12) & tlb_d0[15]) |
              (match0[ 0] & (tlb_ps[0] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 0]) |
              (match0[ 1] & (tlb_ps[1] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 1]) |
              (match0[ 2] & (tlb_ps[2] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 2]) |
              (match0[ 3] & (tlb_ps[3] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 3]) |
              (match0[ 4] & (tlb_ps[4] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 4]) |
              (match0[ 5] & (tlb_ps[5] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 5]) |
              (match0[ 6] & (tlb_ps[6] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 6]) |
              (match0[ 7] & (tlb_ps[7] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 7]) |
              (match0[ 8] & (tlb_ps[8] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 8]) |
              (match0[ 9] & (tlb_ps[9] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[ 9]) |
              (match0[10] & (tlb_ps[10] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[10]) |
              (match0[11] & (tlb_ps[11] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[11]) |
              (match0[12] & (tlb_ps[12] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[12]) |
              (match0[13] & (tlb_ps[13] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[13]) |
              (match0[14] & (tlb_ps[14] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[14]) |
              (match0[15] & (tlb_ps[15] ? s0_vppn[8] : s0_va_bit12) & tlb_d1[15]) ;

assign s0_v = (match0[0] & ~(tlb_ps[0] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[0]) |
              (match0[1] & ~(tlb_ps[1] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[1]) |
              (match0[2] & ~(tlb_ps[2] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[2]) |
              (match0[3] & ~(tlb_ps[3] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[3]) |
              (match0[4] & ~(tlb_ps[4] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[4]) |
              (match0[5] & ~(tlb_ps[5] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[5]) |
              (match0[6] & ~(tlb_ps[6] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[6]) |
              (match0[7] & ~(tlb_ps[7] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[7]) |
              (match0[8] & ~(tlb_ps[8] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[8]) |
              (match0[9] & ~(tlb_ps[9] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[9]) |
              (match0[10] & ~(tlb_ps[10] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[10]) |
              (match0[11] & ~(tlb_ps[11] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[11]) |
              (match0[12] & ~(tlb_ps[12] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[12]) |
              (match0[13] & ~(tlb_ps[13] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[13]) |
              (match0[14] & ~(tlb_ps[14] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[14]) |
              (match0[15] & ~(tlb_ps[15] ? s0_vppn[8] : s0_va_bit12) & tlb_v0[15]) |
              (match0[ 0] & (tlb_ps[0] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 0]) |
              (match0[ 1] & (tlb_ps[1] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 1]) |
              (match0[ 2] & (tlb_ps[2] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 2]) |
              (match0[ 3] & (tlb_ps[3] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 3]) |
              (match0[ 4] & (tlb_ps[4] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 4]) |
              (match0[ 5] & (tlb_ps[5] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 5]) |
              (match0[ 6] & (tlb_ps[6] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 6]) |
              (match0[ 7] & (tlb_ps[7] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 7]) |
              (match0[ 8] & (tlb_ps[8] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 8]) |
              (match0[ 9] & (tlb_ps[9] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[ 9]) |
              (match0[10] & (tlb_ps[10] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[10]) |
              (match0[11] & (tlb_ps[11] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[11]) |
              (match0[12] & (tlb_ps[12] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[12]) |
              (match0[13] & (tlb_ps[13] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[13]) |
              (match0[14] & (tlb_ps[14] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[14]) |
              (match0[15] & (tlb_ps[15] ? s0_vppn[8] : s0_va_bit12) & tlb_v1[15]) ;


//SEARCH PORT 1
assign match1[ 0] = (s1_vppn[18:9] == tlb_vppn[ 0][18:9])
                && (tlb_ps[ 0] || s1_vppn[8:0] == tlb_vppn[ 0][8:0])
                && ((s1_asid==tlb_asid[ 0]) || tlb_g[ 0]) && tlb_e[0];
assign match1[ 1] = (s1_vppn[18:9] == tlb_vppn[ 1][18:9])
                && (tlb_ps[ 1] || s1_vppn[8:0] == tlb_vppn[ 1][8:0])
                && ((s1_asid==tlb_asid[ 1]) || tlb_g[ 1]) && tlb_e[1];
assign match1[ 2] = (s1_vppn[18:9] == tlb_vppn[ 2][18:9])
                && (tlb_ps[ 2] || s1_vppn[8:0] == tlb_vppn[ 2][8:0])
                && ((s1_asid==tlb_asid[ 2]) || tlb_g[ 2]) && tlb_e[2];
assign match1[ 3] = (s1_vppn[18:9] == tlb_vppn[ 3][18:9])
                && (tlb_ps[ 3] || s1_vppn[8:0] == tlb_vppn[ 3][8:0])
                && ((s1_asid==tlb_asid[ 3]) || tlb_g[ 3]) && tlb_e[3];
assign match1[ 4] = (s1_vppn[18:9] == tlb_vppn[ 4][18:9])
                && (tlb_ps[ 4] || s1_vppn[8:0] == tlb_vppn[ 4][8:0])
                && ((s1_asid==tlb_asid[ 4]) || tlb_g[ 4]) && tlb_e[4];
assign match1[ 5] = (s1_vppn[18:9] == tlb_vppn[ 5][18:9])
                && (tlb_ps[ 5] || s1_vppn[8:0] == tlb_vppn[ 5][8:0])
                && ((s1_asid==tlb_asid[ 5]) || tlb_g[ 5]) && tlb_e[5];
assign match1[ 6] = (s1_vppn[18:9] == tlb_vppn[ 6][18:9])
                && (tlb_ps[ 6] || s1_vppn[8:0] == tlb_vppn[ 6][8:0])
                && ((s1_asid==tlb_asid[ 6]) || tlb_g[ 6]) && tlb_e[6];
assign match1[ 7] = (s1_vppn[18:9] == tlb_vppn[ 7][18:9])
                && (tlb_ps[ 7] || s1_vppn[8:0] == tlb_vppn[ 7][8:0])
                && ((s1_asid==tlb_asid[ 7]) || tlb_g[ 7]) && tlb_e[7];
assign match1[ 8] = (s1_vppn[18:9] == tlb_vppn[ 8][18:9])
                && (tlb_ps[ 8] || s1_vppn[8:0] == tlb_vppn[ 8][8:0])
                && ((s1_asid==tlb_asid[ 8]) || tlb_g[ 8]) && tlb_e[8];
assign match1[ 9] = (s1_vppn[18:9] == tlb_vppn[ 9][18:9])
                && (tlb_ps[ 9] || s1_vppn[8:0] == tlb_vppn[ 9][8:0])
                && ((s1_asid==tlb_asid[ 9]) || tlb_g[ 9]) && tlb_e[9];
assign match1[10] = (s1_vppn[18:9] == tlb_vppn[10][18:9])
                && (tlb_ps[10] || s1_vppn[8:0] == tlb_vppn[10][8:0])
                && ((s1_asid==tlb_asid[10]) || tlb_g[10]) && tlb_e[10];
assign match1[11] = (s1_vppn[18:9] == tlb_vppn[11][18:9])
                && (tlb_ps[11] || s1_vppn[8:0] == tlb_vppn[11][8:0])
                && ((s1_asid==tlb_asid[11]) || tlb_g[11]) && tlb_e[11];
assign match1[12] = (s1_vppn[18:9] == tlb_vppn[12][18:9])
                && (tlb_ps[12] || s1_vppn[8:0] == tlb_vppn[12][8:0])
                && ((s1_asid==tlb_asid[12]) || tlb_g[12]) && tlb_e[12];
assign match1[13] = (s1_vppn[18:9] == tlb_vppn[13][18:9])
                && (tlb_ps[13] || s1_vppn[8:0] == tlb_vppn[13][8:0])
                && ((s1_asid==tlb_asid[13]) || tlb_g[13]) && tlb_e[13];
assign match1[14] = (s1_vppn[18:9] == tlb_vppn[14][18:9])
                && (tlb_ps[14] || s1_vppn[8:0] == tlb_vppn[14][8:0])
                && ((s1_asid==tlb_asid[14]) || tlb_g[14]) && tlb_e[14];
assign match1[15] = (s1_vppn[18:9] == tlb_vppn[15][18:9])
                && (tlb_ps[15] || s1_vppn[8:0] == tlb_vppn[15][8:0])
                && ((s1_asid==tlb_asid[15]) || tlb_g[15]) && tlb_e[15] ;


assign s1_index = ({4{match1[0]}} & 4'd0) |
                ({4{match1[1]}} & 4'd1) |
                ({4{match1[2]}} & 4'd2) |
                ({4{match1[3]}} & 4'd3) |
                ({4{match1[4]}} & 4'd4) |
                ({4{match1[5]}} & 4'd5) |
                ({4{match1[6]}} & 4'd6) |
                ({4{match1[7]}} & 4'd7) |
                ({4{match1[8]}} & 4'd8) |
                ({4{match1[9]}} & 4'd9) |
                ({4{match1[10]}} & 4'd10) |
                ({4{match1[11]}} & 4'd11) |
                ({4{match1[12]}} & 4'd12) |
                ({4{match1[13]}} & 4'd13) |
                ({4{match1[14]}} & 4'd14) |
                ({4{match1[15]}} & 4'd15) ;

assign s1_found = match1[0] || match1[1] || match1[2] || match1[3]
                || match1[4] || match1[5] || match1[6] || match1[7]
                || match1[8] || match1[9] || match1[10] || match1[11]
                || match1[12] || match1[13] || match1[14] || match1[15] ;

assign s1_ppn = ({20{match1[0]}} & {20{~(tlb_ps[0] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[0]) |
                ({20{match1[1]}} & {20{~(tlb_ps[1] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[1]) |
                ({20{match1[2]}} & {20{~(tlb_ps[2] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[2]) |
                ({20{match1[3]}} & {20{~(tlb_ps[3] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[3]) |
                ({20{match1[4]}} & {20{~(tlb_ps[4] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[4]) |
                ({20{match1[5]}} & {20{~(tlb_ps[5] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[5]) |
                ({20{match1[6]}} & {20{~(tlb_ps[6] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[6]) |
                ({20{match1[7]}} & {20{~(tlb_ps[7] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[7]) |
                ({20{match1[8]}} & {20{~(tlb_ps[8] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[8]) |
                ({20{match1[9]}} & {20{~(tlb_ps[9] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[9]) |
                ({20{match1[10]}} & {20{~(tlb_ps[10] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[10]) |
                ({20{match1[11]}} & {20{~(tlb_ps[11] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[11]) |
                ({20{match1[12]}} & {20{~(tlb_ps[12] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[12]) |
                ({20{match1[13]}} & {20{~(tlb_ps[13] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[13]) |
                ({20{match1[14]}} & {20{~(tlb_ps[14] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[14]) |
                ({20{match1[15]}} & {20{~(tlb_ps[15] ? s1_vppn[8] : s1_va_bit12)}} & tlb_ppn0[15]) |
                ({20{match1[ 0]}} & {20{tlb_ps[0] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 0]) |
                ({20{match1[ 1]}} & {20{tlb_ps[1] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 1]) |
                ({20{match1[ 2]}} & {20{tlb_ps[2] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 2]) |
                ({20{match1[ 3]}} & {20{tlb_ps[3] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 3]) |
                ({20{match1[ 4]}} & {20{tlb_ps[4] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 4]) |
                ({20{match1[ 5]}} & {20{tlb_ps[5] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 5]) |
                ({20{match1[ 6]}} & {20{tlb_ps[6] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 6]) |
                ({20{match1[ 7]}} & {20{tlb_ps[7] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 7]) |
                ({20{match1[ 8]}} & {20{tlb_ps[8] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 8]) |
                ({20{match1[ 9]}} & {20{tlb_ps[9] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[ 9]) |
                ({20{match1[10]}} & {20{tlb_ps[10] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[10]) |
                ({20{match1[11]}} & {20{tlb_ps[11] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[11]) |
                ({20{match1[12]}} & {20{tlb_ps[12] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[12]) |
                ({20{match1[13]}} & {20{tlb_ps[13] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[13]) |
                ({20{match1[14]}} & {20{tlb_ps[14] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[14]) |
                ({20{match1[15]}} & {20{tlb_ps[15] ? s1_vppn[8] : s1_va_bit12}} & tlb_ppn1[15]) ;

assign s1_ps = ({6{match1[0]}} & (tlb_ps[0] ? 6'd21 : 6'd12)) |
                ({6{match1[1]}} & (tlb_ps[1] ? 6'd21 : 6'd12)) |
                ({6{match1[2]}} & (tlb_ps[2] ? 6'd21 : 6'd12)) |
                ({6{match1[3]}} & (tlb_ps[3] ? 6'd21 : 6'd12)) |
                ({6{match1[4]}} & (tlb_ps[4] ? 6'd21 : 6'd12)) |
                ({6{match1[5]}} & (tlb_ps[5] ? 6'd21 : 6'd12)) |
                ({6{match1[6]}} & (tlb_ps[6] ? 6'd21 : 6'd12)) |
                ({6{match1[7]}} & (tlb_ps[7] ? 6'd21 : 6'd12)) |
                ({6{match1[8]}} & (tlb_ps[8] ? 6'd21 : 6'd12)) |
                ({6{match1[9]}} & (tlb_ps[9] ? 6'd21 : 6'd12)) |
                ({6{match1[10]}} & (tlb_ps[10] ? 6'd21 : 6'd12)) |
                ({6{match1[11]}} & (tlb_ps[11] ? 6'd21 : 6'd12)) |
                ({6{match1[12]}} & (tlb_ps[12] ? 6'd21 : 6'd12)) |
                ({6{match1[13]}} & (tlb_ps[13] ? 6'd21 : 6'd12)) |
                ({6{match1[14]}} & (tlb_ps[14] ? 6'd21 : 6'd12)) |
                ({6{match1[15]}} & (tlb_ps[15] ? 6'd21 : 6'd12)) ;

assign s1_plv = ({2{match1[0]}} & {2{~(tlb_ps[0] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[0]) |
                ({2{match1[1]}} & {2{~(tlb_ps[1] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[1]) |
                ({2{match1[2]}} & {2{~(tlb_ps[2] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[2]) |
                ({2{match1[3]}} & {2{~(tlb_ps[3] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[3]) |
                ({2{match1[4]}} & {2{~(tlb_ps[4] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[4]) |
                ({2{match1[5]}} & {2{~(tlb_ps[5] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[5]) |
                ({2{match1[6]}} & {2{~(tlb_ps[6] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[6]) |
                ({2{match1[7]}} & {2{~(tlb_ps[7] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[7]) |
                ({2{match1[8]}} & {2{~(tlb_ps[8] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[8]) |
                ({2{match1[9]}} & {2{~(tlb_ps[9] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[9]) |
                ({2{match1[10]}} & {2{~(tlb_ps[10] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[10]) |
                ({2{match1[11]}} & {2{~(tlb_ps[11] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[11]) |
                ({2{match1[12]}} & {2{~(tlb_ps[12] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[12]) |
                ({2{match1[13]}} & {2{~(tlb_ps[13] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[13]) |
                ({2{match1[14]}} & {2{~(tlb_ps[14] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[14]) |
                ({2{match1[15]}} & {2{~(tlb_ps[15] ? s1_vppn[8] : s1_va_bit12)}} & tlb_plv0[15]) |
                ({2{match1[ 0]}} & {2{tlb_ps[0] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 0]) |
                ({2{match1[ 1]}} & {2{tlb_ps[1] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 1]) |
                ({2{match1[ 2]}} & {2{tlb_ps[2] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 2]) |
                ({2{match1[ 3]}} & {2{tlb_ps[3] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 3]) |
                ({2{match1[ 4]}} & {2{tlb_ps[4] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 4]) |
                ({2{match1[ 5]}} & {2{tlb_ps[5] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 5]) |
                ({2{match1[ 6]}} & {2{tlb_ps[6] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 6]) |
                ({2{match1[ 7]}} & {2{tlb_ps[7] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 7]) |
                ({2{match1[ 8]}} & {2{tlb_ps[8] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 8]) |
                ({2{match1[ 9]}} & {2{tlb_ps[9] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[ 9]) |
                ({2{match1[10]}} & {2{tlb_ps[10] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[10]) |
                ({2{match1[11]}} & {2{tlb_ps[11] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[11]) |
                ({2{match1[12]}} & {2{tlb_ps[12] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[12]) |
                ({2{match1[13]}} & {2{tlb_ps[13] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[13]) |
                ({2{match1[14]}} & {2{tlb_ps[14] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[14]) |
                ({2{match1[15]}} & {2{tlb_ps[15] ? s1_vppn[8] : s1_va_bit12}} & tlb_plv1[15]) ;

assign s1_mat = ({2{match1[0]}} & {2{~(tlb_ps[0] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[0]) |
                ({2{match1[1]}} & {2{~(tlb_ps[1] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[1]) |
                ({2{match1[2]}} & {2{~(tlb_ps[2] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[2]) |
                ({2{match1[3]}} & {2{~(tlb_ps[3] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[3]) |
                ({2{match1[4]}} & {2{~(tlb_ps[4] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[4]) |
                ({2{match1[5]}} & {2{~(tlb_ps[5] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[5]) |
                ({2{match1[6]}} & {2{~(tlb_ps[6] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[6]) |
                ({2{match1[7]}} & {2{~(tlb_ps[7] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[7]) |
                ({2{match1[8]}} & {2{~(tlb_ps[8] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[8]) |
                ({2{match1[9]}} & {2{~(tlb_ps[9] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[9]) |
                ({2{match1[10]}} & {2{~(tlb_ps[10] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[10]) |
                ({2{match1[11]}} & {2{~(tlb_ps[11] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[11]) |
                ({2{match1[12]}} & {2{~(tlb_ps[12] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[12]) |
                ({2{match1[13]}} & {2{~(tlb_ps[13] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[13]) |
                ({2{match1[14]}} & {2{~(tlb_ps[14] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[14]) |
                ({2{match1[15]}} & {2{~(tlb_ps[15] ? s1_vppn[8] : s1_va_bit12)}} & tlb_mat0[15]) |
                ({2{match1[ 0]}} & {2{tlb_ps[0] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 0]) |
                ({2{match1[ 1]}} & {2{tlb_ps[1] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 1]) |
                ({2{match1[ 2]}} & {2{tlb_ps[2] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 2]) |
                ({2{match1[ 3]}} & {2{tlb_ps[3] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 3]) |
                ({2{match1[ 4]}} & {2{tlb_ps[4] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 4]) |
                ({2{match1[ 5]}} & {2{tlb_ps[5] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 5]) |
                ({2{match1[ 6]}} & {2{tlb_ps[6] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 6]) |
                ({2{match1[ 7]}} & {2{tlb_ps[7] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 7]) |
                ({2{match1[ 8]}} & {2{tlb_ps[8] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 8]) |
                ({2{match1[ 9]}} & {2{tlb_ps[9] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[ 9]) |
                ({2{match1[10]}} & {2{tlb_ps[10] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[10]) |
                ({2{match1[11]}} & {2{tlb_ps[11] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[11]) |
                ({2{match1[12]}} & {2{tlb_ps[12] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[12]) |
                ({2{match1[13]}} & {2{tlb_ps[13] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[13]) |
                ({2{match1[14]}} & {2{tlb_ps[14] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[14]) |
                ({2{match1[15]}} & {2{tlb_ps[15] ? s1_vppn[8] : s1_va_bit12}} & tlb_mat1[15]) ;

assign s1_d = (match1[0] & ~(tlb_ps[0] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[0]) |
              (match1[1] & ~(tlb_ps[1] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[1]) |
              (match1[2] & ~(tlb_ps[2] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[2]) |
              (match1[3] & ~(tlb_ps[3] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[3]) |
              (match1[4] & ~(tlb_ps[4] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[4]) |
              (match1[5] & ~(tlb_ps[5] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[5]) |
              (match1[6] & ~(tlb_ps[6] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[6]) |
              (match1[7] & ~(tlb_ps[7] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[7]) |
              (match1[8] & ~(tlb_ps[8] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[8]) |
              (match1[9] & ~(tlb_ps[9] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[9]) |
              (match1[10] & ~(tlb_ps[10] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[10]) |
              (match1[11] & ~(tlb_ps[11] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[11]) |
              (match1[12] & ~(tlb_ps[12] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[12]) |
              (match1[13] & ~(tlb_ps[13] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[13]) |
              (match1[14] & ~(tlb_ps[14] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[14]) |
              (match1[15] & ~(tlb_ps[15] ? s1_vppn[8] : s1_va_bit12) & tlb_d0[15]) |
              (match1[ 0] & (tlb_ps[0] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 0]) |
              (match1[ 1] & (tlb_ps[1] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 1]) |
              (match1[ 2] & (tlb_ps[2] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 2]) |
              (match1[ 3] & (tlb_ps[3] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 3]) |
              (match1[ 4] & (tlb_ps[4] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 4]) |
              (match1[ 5] & (tlb_ps[5] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 5]) |
              (match1[ 6] & (tlb_ps[6] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 6]) |
              (match1[ 7] & (tlb_ps[7] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 7]) |
              (match1[ 8] & (tlb_ps[8] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 8]) |
              (match1[ 9] & (tlb_ps[9] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[ 9]) |
              (match1[10] & (tlb_ps[10] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[10]) |
              (match1[11] & (tlb_ps[11] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[11]) |
              (match1[12] & (tlb_ps[12] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[12]) |
              (match1[13] & (tlb_ps[13] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[13]) |
              (match1[14] & (tlb_ps[14] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[14]) |
              (match1[15] & (tlb_ps[15] ? s1_vppn[8] : s1_va_bit12) & tlb_d1[15]) ;

assign s1_v = (match1[0] & ~(tlb_ps[0] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[0]) |
              (match1[1] & ~(tlb_ps[1] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[1]) |
              (match1[2] & ~(tlb_ps[2] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[2]) |
              (match1[3] & ~(tlb_ps[3] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[3]) |
              (match1[4] & ~(tlb_ps[4] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[4]) |
              (match1[5] & ~(tlb_ps[5] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[5]) |
              (match1[6] & ~(tlb_ps[6] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[6]) |
              (match1[7] & ~(tlb_ps[7] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[7]) |
              (match1[8] & ~(tlb_ps[8] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[8]) |
              (match1[9] & ~(tlb_ps[9] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[9]) |
              (match1[10] & ~(tlb_ps[10] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[10]) |
              (match1[11] & ~(tlb_ps[11] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[11]) |
              (match1[12] & ~(tlb_ps[12] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[12]) |
              (match1[13] & ~(tlb_ps[13] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[13]) |
              (match1[14] & ~(tlb_ps[14] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[14]) |
              (match1[15] & ~(tlb_ps[15] ? s1_vppn[8] : s1_va_bit12) & tlb_v0[15]) |
              (match1[ 0] & (tlb_ps[0] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 0]) |
              (match1[ 1] & (tlb_ps[1] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 1]) |
              (match1[ 2] & (tlb_ps[2] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 2]) |
              (match1[ 3] & (tlb_ps[3] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 3]) |
              (match1[ 4] & (tlb_ps[4] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 4]) |
              (match1[ 5] & (tlb_ps[5] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 5]) |
              (match1[ 6] & (tlb_ps[6] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 6]) |
              (match1[ 7] & (tlb_ps[7] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 7]) |
              (match1[ 8] & (tlb_ps[8] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 8]) |
              (match1[ 9] & (tlb_ps[9] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[ 9]) |
              (match1[10] & (tlb_ps[10] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[10]) |
              (match1[11] & (tlb_ps[11] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[11]) |
              (match1[12] & (tlb_ps[12] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[12]) |
              (match1[13] & (tlb_ps[13] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[13]) |
              (match1[14] & (tlb_ps[14] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[14]) |
              (match1[15] & (tlb_ps[15] ? s1_vppn[8] : s1_va_bit12) & tlb_v1[15]) ;


//INVTLB
assign inv_match[0] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[0]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[0]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[0] && (invtlb_asid == tlb_asid[0])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[0] && (invtlb_asid == tlb_asid[0]) && (invtlb_vppn[18:9] == tlb_vppn[ 0][18:9]) && (tlb_ps[ 0] || invtlb_vppn[8:0] == tlb_vppn[ 0][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[0] || (invtlb_asid == tlb_asid[0])) && (invtlb_vppn[18:9] == tlb_vppn[ 0][18:9]) && (tlb_ps[ 0] || invtlb_vppn[8:0] == tlb_vppn[ 0][8:0]));
assign inv_match[1] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[1]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[1]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[1] && (invtlb_asid == tlb_asid[1])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[1] && (invtlb_asid == tlb_asid[1]) && (invtlb_vppn[18:9] == tlb_vppn[ 1][18:9]) && (tlb_ps[ 1] || invtlb_vppn[8:0] == tlb_vppn[ 1][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[1] || (invtlb_asid == tlb_asid[1])) && (invtlb_vppn[18:9] == tlb_vppn[ 1][18:9]) && (tlb_ps[ 1] || invtlb_vppn[8:0] == tlb_vppn[ 1][8:0]));
assign inv_match[2] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[2]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[2]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[2] && (invtlb_asid == tlb_asid[2])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[2] && (invtlb_asid == tlb_asid[2]) && (invtlb_vppn[18:9] == tlb_vppn[ 2][18:9]) && (tlb_ps[ 2] || invtlb_vppn[8:0] == tlb_vppn[ 2][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[2] || (invtlb_asid == tlb_asid[2])) && (invtlb_vppn[18:9] == tlb_vppn[ 2][18:9]) && (tlb_ps[ 2] || invtlb_vppn[8:0] == tlb_vppn[ 2][8:0]));
assign inv_match[3] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[3]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[3]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[3] && (invtlb_asid == tlb_asid[3])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[3] && (invtlb_asid == tlb_asid[3]) && (invtlb_vppn[18:9] == tlb_vppn[ 3][18:9]) && (tlb_ps[ 3] || invtlb_vppn[8:0] == tlb_vppn[ 3][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[3] || (invtlb_asid == tlb_asid[3])) && (invtlb_vppn[18:9] == tlb_vppn[ 3][18:9]) && (tlb_ps[ 3] || invtlb_vppn[8:0] == tlb_vppn[ 3][8:0]));
assign inv_match[4] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[4]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[4]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[4] && (invtlb_asid == tlb_asid[4])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[4] && (invtlb_asid == tlb_asid[4]) && (invtlb_vppn[18:9] == tlb_vppn[ 4][18:9]) && (tlb_ps[ 4] || invtlb_vppn[8:0] == tlb_vppn[ 4][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[4] || (invtlb_asid == tlb_asid[4])) && (invtlb_vppn[18:9] == tlb_vppn[ 4][18:9]) && (tlb_ps[ 4] || invtlb_vppn[8:0] == tlb_vppn[ 4][8:0]));
assign inv_match[5] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[5]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[5]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[5] && (invtlb_asid == tlb_asid[5])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[5] && (invtlb_asid == tlb_asid[5]) && (invtlb_vppn[18:9] == tlb_vppn[ 5][18:9]) && (tlb_ps[ 5] || invtlb_vppn[8:0] == tlb_vppn[ 5][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[5] || (invtlb_asid == tlb_asid[5])) && (invtlb_vppn[18:9] == tlb_vppn[ 5][18:9]) && (tlb_ps[ 5] || invtlb_vppn[8:0] == tlb_vppn[ 5][8:0]));
assign inv_match[6] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[6]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[6]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[6] && (invtlb_asid == tlb_asid[6])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[6] && (invtlb_asid == tlb_asid[6]) && (invtlb_vppn[18:9] == tlb_vppn[ 6][18:9]) && (tlb_ps[ 6] || invtlb_vppn[8:0] == tlb_vppn[ 6][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[6] || (invtlb_asid == tlb_asid[6])) && (invtlb_vppn[18:9] == tlb_vppn[ 6][18:9]) && (tlb_ps[ 6] || invtlb_vppn[8:0] == tlb_vppn[ 6][8:0]));
assign inv_match[7] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[7]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[7]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[7] && (invtlb_asid == tlb_asid[7])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[7] && (invtlb_asid == tlb_asid[7]) && (invtlb_vppn[18:9] == tlb_vppn[ 7][18:9]) && (tlb_ps[ 7] || invtlb_vppn[8:0] == tlb_vppn[ 7][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[7] || (invtlb_asid == tlb_asid[7])) && (invtlb_vppn[18:9] == tlb_vppn[ 7][18:9]) && (tlb_ps[ 7] || invtlb_vppn[8:0] == tlb_vppn[ 7][8:0]));
assign inv_match[8] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[8]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[8]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[8] && (invtlb_asid == tlb_asid[8])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[8] && (invtlb_asid == tlb_asid[8]) && (invtlb_vppn[18:9] == tlb_vppn[ 8][18:9]) && (tlb_ps[ 8] || invtlb_vppn[8:0] == tlb_vppn[ 8][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[8] || (invtlb_asid == tlb_asid[8])) && (invtlb_vppn[18:9] == tlb_vppn[ 8][18:9]) && (tlb_ps[ 8] || invtlb_vppn[8:0] == tlb_vppn[ 8][8:0]));
assign inv_match[9] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                      ((invtlb_op == 5'h2) && tlb_g[9]) |
                      ((invtlb_op == 5'h3) && ~tlb_g[9]) |
                      ((invtlb_op == 5'h4) && ~tlb_g[9] && (invtlb_asid == tlb_asid[9])) |
                      ((invtlb_op == 5'h5) && ~tlb_g[9] && (invtlb_asid == tlb_asid[9]) && (invtlb_vppn[18:9] == tlb_vppn[ 9][18:9]) && (tlb_ps[ 9] || invtlb_vppn[8:0] == tlb_vppn[ 9][8:0])) |
                      ((invtlb_op == 5'h6) && (tlb_g[9] || (invtlb_asid == tlb_asid[9])) && (invtlb_vppn[18:9] == tlb_vppn[ 9][18:9]) && (tlb_ps[ 9] || invtlb_vppn[8:0] == tlb_vppn[ 9][8:0]));
assign inv_match[10] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                       ((invtlb_op == 5'h2) && tlb_g[10]) |
                       ((invtlb_op == 5'h3) && ~tlb_g[10]) |
                       ((invtlb_op == 5'h4) && ~tlb_g[10] && (invtlb_asid == tlb_asid[10])) |
                       ((invtlb_op == 5'h5) && ~tlb_g[10] && (invtlb_asid == tlb_asid[10]) && (invtlb_vppn[18:9] == tlb_vppn[ 10][18:9]) && (tlb_ps[ 10] || invtlb_vppn[8:0] == tlb_vppn[ 10][8:0])) |
                       ((invtlb_op == 5'h6) && (tlb_g[10] || (invtlb_asid == tlb_asid[10])) && (invtlb_vppn[18:9] == tlb_vppn[ 10][18:9]) && (tlb_ps[ 10] || invtlb_vppn[8:0] == tlb_vppn[ 10][8:0]));
assign inv_match[11] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                       ((invtlb_op == 5'h2) && tlb_g[11]) |
                       ((invtlb_op == 5'h3) && ~tlb_g[11]) |
                       ((invtlb_op == 5'h4) && ~tlb_g[11] && (invtlb_asid == tlb_asid[11])) |
                       ((invtlb_op == 5'h5) && ~tlb_g[11] && (invtlb_asid == tlb_asid[11]) && (invtlb_vppn[18:9] == tlb_vppn[ 11][18:9]) && (tlb_ps[ 11] || invtlb_vppn[8:0] == tlb_vppn[ 11][8:0])) |
                       ((invtlb_op == 5'h6) && (tlb_g[11] || (invtlb_asid == tlb_asid[11])) && (invtlb_vppn[18:9] == tlb_vppn[ 11][18:9]) && (tlb_ps[ 11] || invtlb_vppn[8:0] == tlb_vppn[ 11][8:0]));
assign inv_match[12] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                       ((invtlb_op == 5'h2) && tlb_g[12]) |
                       ((invtlb_op == 5'h3) && ~tlb_g[12]) |
                       ((invtlb_op == 5'h4) && ~tlb_g[12] && (invtlb_asid == tlb_asid[12])) |
                       ((invtlb_op == 5'h5) && ~tlb_g[12] && (invtlb_asid == tlb_asid[12]) && (invtlb_vppn[18:9] == tlb_vppn[ 12][18:9]) && (tlb_ps[ 12] || invtlb_vppn[8:0] == tlb_vppn[ 12][8:0])) |
                       ((invtlb_op == 5'h6) && (tlb_g[12] || (invtlb_asid == tlb_asid[12])) && (invtlb_vppn[18:9] == tlb_vppn[ 12][18:9]) && (tlb_ps[ 12] || invtlb_vppn[8:0] == tlb_vppn[ 12][8:0]));
assign inv_match[13] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                       ((invtlb_op == 5'h2) && tlb_g[13]) |
                       ((invtlb_op == 5'h3) && ~tlb_g[13]) |
                       ((invtlb_op == 5'h4) && ~tlb_g[13] && (invtlb_asid == tlb_asid[13])) |
                       ((invtlb_op == 5'h5) && ~tlb_g[13] && (invtlb_asid == tlb_asid[13]) && (invtlb_vppn[18:9] == tlb_vppn[ 13][18:9]) && (tlb_ps[ 13] || invtlb_vppn[8:0] == tlb_vppn[ 13][8:0])) |
                       ((invtlb_op == 5'h6) && (tlb_g[13] || (invtlb_asid == tlb_asid[13])) && (invtlb_vppn[18:9] == tlb_vppn[ 13][18:9]) && (tlb_ps[ 13] || invtlb_vppn[8:0] == tlb_vppn[ 13][8:0]));
assign inv_match[14] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                       ((invtlb_op == 5'h2) && tlb_g[14]) |
                       ((invtlb_op == 5'h3) && ~tlb_g[14]) |
                       ((invtlb_op == 5'h4) && ~tlb_g[14] && (invtlb_asid == tlb_asid[14])) |
                       ((invtlb_op == 5'h5) && ~tlb_g[14] && (invtlb_asid == tlb_asid[14]) && (invtlb_vppn[18:9] == tlb_vppn[ 14][18:9]) && (tlb_ps[ 14] || invtlb_vppn[8:0] == tlb_vppn[ 14][8:0])) |
                       ((invtlb_op == 5'h6) && (tlb_g[14] || (invtlb_asid == tlb_asid[14])) && (invtlb_vppn[18:9] == tlb_vppn[ 14][18:9]) && (tlb_ps[ 14] || invtlb_vppn[8:0] == tlb_vppn[ 14][8:0]));
assign inv_match[15] = ((invtlb_op == 5'h0) || (invtlb_op == 5'h1)) |
                       ((invtlb_op == 5'h2) && tlb_g[15]) |
                       ((invtlb_op == 5'h3) && ~tlb_g[15]) |
                       ((invtlb_op == 5'h4) && ~tlb_g[15] && (invtlb_asid == tlb_asid[15])) |
                       ((invtlb_op == 5'h5) && ~tlb_g[15] && (invtlb_asid == tlb_asid[15]) && (invtlb_vppn[18:9] == tlb_vppn[ 15][18:9]) && (tlb_ps[ 15] || invtlb_vppn[8:0] == tlb_vppn[ 15][8:0])) |
                       ((invtlb_op == 5'h6) && (tlb_g[15] || (invtlb_asid == tlb_asid[15])) && (invtlb_vppn[18:9] == tlb_vppn[ 15][18:9]) && (tlb_ps[ 15] || invtlb_vppn[8:0] == tlb_vppn[ 15][8:0]));


endmodule
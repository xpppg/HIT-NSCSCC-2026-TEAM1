module alu(
  input  clk,
  input  reset,
  input  wire [18:0] alu_op,
  input  wire [31:0] alu_src1,
  input  wire [31:0] alu_src2,
  output wire [31:0] alu_result,
  output wire div_wating,
  output wire mul_wating,
  output wire forward_ok,
  output wire [31:0] forward_result,
  input  wire EXE_valid
);

wire op_add;   //add operation
wire op_sub;   //sub operation
wire op_slt;   //signed compared and set less than
wire op_sltu;  //unsigned compared and set less than
wire op_and;   //bitwise and
wire op_nor;   //bitwise nor
wire op_or;    //bitwise or
wire op_xor;   //bitwise xor
wire op_sll;   //logic left shift
wire op_srl;   //logic right shift
wire op_sra;   //arithmetic right shift
wire op_lui;   //Load Upper Immediate
wire op_mul;
wire op_mulh_w;
wire op_mulh_wu;
wire op_div_w;
wire op_mod_w;
wire op_div_wu;
wire op_mod_wu;

// control code decomposition
assign op_add  = alu_op[ 0];
assign op_sub  = alu_op[ 1];
assign op_slt  = alu_op[ 2];
assign op_sltu = alu_op[ 3];
assign op_and  = alu_op[ 4];
assign op_nor  = alu_op[ 5];
assign op_or   = alu_op[ 6];
assign op_xor  = alu_op[ 7];
assign op_sll  = alu_op[ 8];
assign op_srl  = alu_op[ 9];
assign op_sra  = alu_op[10];
assign op_lui  = alu_op[11];
assign op_mul  = alu_op[12];
assign op_mulh_w  = alu_op[13];
assign op_mulh_wu  = alu_op[14];
assign op_div_w  = alu_op[15];
assign op_mod_w  = alu_op[16];
assign op_div_wu  = alu_op[17];
assign op_mod_wu  = alu_op[18];

wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;


// 32-bit adder
wire [31:0] adder_a;
wire [31:0] adder_b;
wire        adder_cin;
wire [31:0] adder_result;
wire        adder_cout;

assign adder_a   = alu_src1;
assign adder_b   = (op_sub | op_slt | op_sltu) ? ~alu_src2 : alu_src2;  //src1 - src2 rj-rk
assign adder_cin = (op_sub | op_slt | op_sltu) ? 1'b1      : 1'b0;
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;

//乘法器
wire mul;
reg  mul_in_done;
wire mul_complete;
wire [63:0] mul_total;
wire [31:0] mul_result;

assign mul = (op_mul | op_mulh_w | op_mulh_wu) & ~mul_in_done & EXE_valid;
assign mul_wating = (op_mul | op_mulh_w | op_mulh_wu) & ~mul_complete & EXE_valid;

always @(posedge clk) begin
  if(mul) begin
    mul_in_done <= 1'b1;
  end
  else if (mul_wating) begin
    mul_in_done <= mul_in_done;
  end
  else begin
    mul_in_done <= 1'b0;
  end
end

mul u_mul(
    .clk(clk),
    .reset(reset),
    .en(mul),
    .A(alu_src1),
    .B(alu_src2),
    .signed_en(op_mulh_w),
    .result(mul_total),
    .result_valid(mul_complete)
);

assign mul_result = (op_mulh_w|op_mulh_wu) ? mul_total[63:32] : mul_total[31:0];

//除法器
wire div;
reg t_in_done;
wire div_complete;

wire [31:0] div_result;
wire [31:0] mod_result;

assign div = (op_div_w | op_mod_w | op_div_wu | op_mod_wu) & ~t_in_done & EXE_valid;
assign div_wating = (op_div_w | op_mod_w | op_div_wu | op_mod_wu) & ~div_complete & EXE_valid;

always @(posedge clk) begin
  if(div) begin
    t_in_done <= 1'b1;
  end
  else if (div_wating) begin
    t_in_done <= t_in_done;
  end
  else begin
    t_in_done <= 1'b0;
  end
end

div u_div(
    .div_clk(clk),
    .reset(reset),
    .div(div | div_wating),
    .div_signed(op_div_w | op_mod_w),
    .x(alu_src1),
    .y(alu_src2),
    .complete(div_complete),
    .s(div_result),
    .r(mod_result)
);


// ADD, SUB result
assign add_sub_result = adder_result;

// SLT result
assign slt_result[31:1] = 31'b0;   //rj < rk 1
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31])
                        | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);

// SLTU result
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// bitwise operation
assign and_result = alu_src1 & alu_src2;
assign or_result  = alu_src1 | alu_src2;
assign nor_result = ~or_result;
assign xor_result = alu_src1 ^ alu_src2;
assign lui_result = alu_src2;

// SLL result
assign sll_result = alu_src1 << alu_src2[4:0];   //rj << i5

// SRL, SRA result
assign sr64_result = {{32{op_sra & alu_src1[31]}}, alu_src1[31:0]} >> alu_src2[4:0]; //rj >> i5

assign sr_result   = sr64_result[31:0];

// final result mux
assign alu_result = ({32{op_add|op_sub}} & add_sub_result)
                  | ({32{op_slt       }} & slt_result)
                  | ({32{op_sltu      }} & sltu_result)
                  | ({32{op_and       }} & and_result)
                  | ({32{op_nor       }} & nor_result)
                  | ({32{op_or        }} & or_result)
                  | ({32{op_xor       }} & xor_result)
                  | ({32{op_lui       }} & lui_result)
                  | ({32{op_sll       }} & sll_result)
                  | ({32{op_srl|op_sra}} & sr_result)
                  | ({32{op_mul|op_mulh_w|op_mulh_wu}} & mul_result)
                  | ({32{op_div_w|op_div_wu}} & div_result)
                  | ({32{op_mod_w|op_mod_wu}} & mod_result);

assign forward_ok = alu_op[0] | alu_op[1] | alu_op[2] | alu_op[3] | alu_op[4] | alu_op[5] | alu_op[6] | alu_op[7]
                  | alu_op[8] | alu_op[9] | alu_op[10] | alu_op[11];
assign forward_result = ({32{op_add|op_sub}} & add_sub_result)
                      | ({32{op_slt       }} & slt_result)
                      | ({32{op_sltu      }} & sltu_result)
                      | ({32{op_and       }} & and_result)
                      | ({32{op_nor       }} & nor_result)
                      | ({32{op_or        }} & or_result)
                      | ({32{op_xor       }} & xor_result)
                      | ({32{op_lui       }} & lui_result)
                      | ({32{op_sll       }} & sll_result)
                      | ({32{op_srl|op_sra}} & sr_result);

endmodule


module mul(
    input           clk,
    input           reset,          
    input           en,             
    input[31:0]     A,
    input[31:0]     B,
    input           signed_en,
    output[63:0]    result,
    output          result_valid    
);

wire[31:0] rA = (signed_en & A[31]) ? (0 - A) : A;
wire[31:0] rB = (signed_en & B[31]) ? (0 - B) : B;

reg[15:0] A00, B00, A10, B10;
reg[15:0] A01, B01, A11, B11;
reg sign;   

always @(posedge clk) begin
    if (reset) begin
        A00 <= 0; B00 <= 0; A10 <= 0; B10 <= 0;
        A01 <= 0; B01 <= 0; A11 <= 0; B11 <= 0;
        sign <= 0;
    end else if (en) begin   // 仅当使能时更新
        A00 <= rA[15:0]; A01 <= rA[15:0];
        B00 <= rB[15:0]; B01 <= rB[15:0];
        A10 <= rA[31:16]; A11 <= rA[31:16];
        B10 <= rB[31:16]; B11 <= rB[31:16];
        sign <= signed_en & (A[31] ^ B[31]);
    end
end

(* use_dsp48 = "yes" *) wire[31:0] mult0_comb = A00 * B00;  // A0*B0
(* use_dsp48 = "yes" *) wire[31:0] mult1_comb = A01 * B10;  // A0*B1
(* use_dsp48 = "yes" *) wire[31:0] mult2_comb = A10 * B01;  // A1*B0
(* use_dsp48 = "yes" *) wire[31:0] mult3_comb = A11 * B11;  // A1*B1


reg[31:0] A0_B0, A0_B1, A1_B0, A1_B1;
reg sign1;   

always @(posedge clk) begin
    if (reset) begin
        A0_B0 <= 0; A0_B1 <= 0; A1_B0 <= 0; A1_B1 <= 0;
        sign1 <= 0;
    end else if (valid_stage0) begin   // 仅当使能时更新
        A0_B0 <= mult0_comb;
        A0_B1 <= mult1_comb;
        A1_B0 <= mult2_comb;
        A1_B1 <= mult3_comb;
        sign1 <= sign;
    end
end

wire[63:0] res = {A1_B1, A0_B0} + {15'b0, {1'b0, A1_B0} + {1'b0, A0_B1}, 16'b0};
assign result = sign1 ? (0 - res) : res;

reg valid_stage0, valid_stage1;

always @(posedge clk) begin
    if (reset) begin
        valid_stage0 <= 1'b0;
        valid_stage1 <= 1'b0;
    end else begin
        // Stage 0 有效表示当前周期有输入被采样
        valid_stage0 <= en;
        // Stage 1 有效表示 Stage 0 的数据已经流到了 Stage 1
        valid_stage1 <= valid_stage0;
    end
end

// 当 Stage 1 有效时，组合逻辑输出的 result 已经稳定
assign result_valid = valid_stage1;

endmodule

module salu(
  input  clk,
  input  reset,
  input  wire [18:0] alu_op,
  input  wire [31:0] alu_src1,
  input  wire [31:0] alu_src2,
  output wire [31:0] alu_result,
  output wire forward_ok,
  output wire [31:0] forward_result,
  input  wire EXE_valid
);

wire op_add;   //add operation
wire op_sub;   //sub operation
wire op_slt;   //signed compared and set less than
wire op_sltu;  //unsigned compared and set less than
wire op_and;   //bitwise and
wire op_nor;   //bitwise nor
wire op_or;    //bitwise or
wire op_xor;   //bitwise xor
wire op_sll;   //logic left shift
wire op_srl;   //logic right shift
wire op_sra;   //arithmetic right shift
wire op_lui;   //Load Upper Immediate

// control code decomposition
assign op_add  = alu_op[ 0];
assign op_sub  = alu_op[ 1];
assign op_slt  = alu_op[ 2];
assign op_sltu = alu_op[ 3];
assign op_and  = alu_op[ 4];
assign op_nor  = alu_op[ 5];
assign op_or   = alu_op[ 6];
assign op_xor  = alu_op[ 7];
assign op_sll  = alu_op[ 8];
assign op_srl  = alu_op[ 9];
assign op_sra  = alu_op[10];
assign op_lui  = alu_op[11];

wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;


// 32-bit adder
wire [31:0] adder_a;
wire [31:0] adder_b;
wire        adder_cin;
wire [31:0] adder_result;
wire        adder_cout;

assign adder_a   = alu_src1;
assign adder_b   = (op_sub | op_slt | op_sltu) ? ~alu_src2 : alu_src2;  //src1 - src2 rj-rk
assign adder_cin = (op_sub | op_slt | op_sltu) ? 1'b1      : 1'b0;
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;

// ADD, SUB result
assign add_sub_result = adder_result;

// SLT result
assign slt_result[31:1] = 31'b0;   //rj < rk 1
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31])
                        | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);

// SLTU result
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// bitwise operation
assign and_result = alu_src1 & alu_src2;
assign or_result  = alu_src1 | alu_src2;
assign nor_result = ~or_result;
assign xor_result = alu_src1 ^ alu_src2;
assign lui_result = alu_src2;

// SLL result
assign sll_result = alu_src1 << alu_src2[4:0];   //rj << i5

// SRL, SRA result
assign sr64_result = {{32{op_sra & alu_src1[31]}}, alu_src1[31:0]} >> alu_src2[4:0]; //rj >> i5

assign sr_result   = sr64_result[31:0];

// final result mux
assign alu_result = ({32{op_add|op_sub}} & add_sub_result)
                  | ({32{op_slt       }} & slt_result)
                  | ({32{op_sltu      }} & sltu_result)
                  | ({32{op_and       }} & and_result)
                  | ({32{op_nor       }} & nor_result)
                  | ({32{op_or        }} & or_result)
                  | ({32{op_xor       }} & xor_result)
                  | ({32{op_lui       }} & lui_result)
                  | ({32{op_sll       }} & sll_result)
                  | ({32{op_srl|op_sra}} & sr_result);

assign forward_ok = alu_op[0] | alu_op[1] | alu_op[2] | alu_op[3] | alu_op[4] | alu_op[5] | alu_op[6] | alu_op[7]
                  | alu_op[8] | alu_op[9] | alu_op[10] | alu_op[11];
assign forward_result = ({32{op_add|op_sub}} & add_sub_result)
                      | ({32{op_slt       }} & slt_result)
                      | ({32{op_sltu      }} & sltu_result)
                      | ({32{op_and       }} & and_result)
                      | ({32{op_nor       }} & nor_result)
                      | ({32{op_or        }} & or_result)
                      | ({32{op_xor       }} & xor_result)
                      | ({32{op_lui       }} & lui_result)
                      | ({32{op_sll       }} & sll_result)
                      | ({32{op_srl|op_sra}} & sr_result);

endmodule
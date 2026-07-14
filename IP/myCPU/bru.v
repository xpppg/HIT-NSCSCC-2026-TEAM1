module bru(
  input  wire        en,//是转移指令或者预测跳转
  input  wire [ 8:0] op,
  input  wire [31:0] rj_value,
  input  wire [31:0] rd_value,
  input  wire [31:0] imm,
  input  wire [31:0] pc,
  input  wire [32:0] pred_info,
  
  output wire        inst_br,
  output wire        br_taken,
  output wire [31:0] br_target,
  output wire        actual_taken,
  output wire [31:0] actual_target
);
wire inst_beq;
wire inst_bne;
wire inst_blt;
wire inst_bge;
wire inst_bltu;
wire inst_bgeu;
wire inst_b;
wire inst_bl;
wire inst_jirl;
wire rj_smaller_rd;
wire rj_smaller_rd_u;
wire br_equal_pred;
wire pred_taken;
wire [31:0] pred_target;
wire br_target_wrong;

assign inst_beq  = op[0];
assign inst_bne  = op[1];
assign inst_blt  = op[2];
assign inst_bge  = op[3];
assign inst_bltu = op[4];
assign inst_bgeu = op[5];
assign inst_b    = op[6];
assign inst_bl   = op[7];
assign inst_jirl = op[8];

assign pred_taken = pred_info[32];
assign pred_target = pred_info[31:0];

assign rj_eq_rd = (rj_value == rd_value);
assign rj_smaller_rd = ($signed(rj_value) < $signed(rd_value));
assign rj_smaller_rd_u = (rj_value < rd_value);

assign actual_target = inst_jirl ? (rj_value + imm) : (pc + imm);
assign actual_taken =     inst_beq  &&  rj_eq_rd
                       || inst_bne  && !rj_eq_rd
                       || inst_blt  && rj_smaller_rd
                       || inst_bge  && !rj_smaller_rd
                       || inst_bltu && rj_smaller_rd_u
                       || inst_bgeu && !rj_smaller_rd_u
                       || inst_jirl
                       || inst_bl
                       || inst_b;

assign br_target_wrong = (actual_target != pred_target) & actual_taken & pred_taken ;

assign inst_br = inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu | inst_b | inst_bl | inst_jirl;
assign br_taken = ((actual_taken & ~pred_taken) | (~actual_taken & pred_taken) | br_target_wrong) & en;
assign br_target = actual_taken ? actual_target : (pc + 32'h4);

endmodule
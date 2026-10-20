// -----------------------------------------------------------------------------
// rv_alu.sv : single-cycle integer ALU
// -----------------------------------------------------------------------------
module rv_alu
  import rv_pkg::*;
(
  input  alu_op_e     op_i,
  input  logic [31:0] a_i,
  input  logic [31:0] b_i,
  output logic [31:0] result_o
);
  logic signed [31:0] a_s;
  assign a_s = a_i;

  always_comb begin
    unique case (op_i)
      ALU_ADD:  result_o = a_i + b_i;
      ALU_SUB:  result_o = a_i - b_i;
      ALU_SLL:  result_o = a_i << b_i[4:0];
      ALU_SLT:  result_o = {31'b0, $signed(a_i) < $signed(b_i)};
      ALU_SLTU: result_o = {31'b0, a_i < b_i};
      ALU_XOR:  result_o = a_i ^ b_i;
      ALU_SRL:  result_o = a_i >> b_i[4:0];
      ALU_SRA:  result_o = a_s >>> b_i[4:0];
      ALU_OR:   result_o = a_i | b_i;
      ALU_AND:  result_o = a_i & b_i;
      default:  result_o = 32'h0;
    endcase
  end
endmodule

// -----------------------------------------------------------------------------
// rv_mul.sv : RV32M multiplier
//   * MUL    : single cycle, full 32x32 -> low 32 bits.
//   * MULH/MULHSU/MULHU : 4 cycles using ONE shared 17x17 signed multiplier
//     (schoolbook on 16-bit halves, same idea as CV32E40P):
//        A = ah*2^16 + al,  B = bh*2^16 + bl      (ah/bh signed-or-unsigned, 17 bit)
//        S0: acc = al*bl
//        S1: acc = (acc >> 16) + ah*bl
//        S2: acc = acc + al*bh
//        S3: hi  = ah*bh + (acc >>> 16)           -> result, done
//   Handshake: done_o is high in the cycle the result is valid. The unit
//   advances only while en_i is high (pipeline not frozen).
// -----------------------------------------------------------------------------
module rv_mul (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        en_i,
  input  logic        flush_i,      // squash a running multi-cycle op
  input  logic        valid_i,      // EX currently holds a MUL-class op
  input  logic [2:0]  funct3_i,
  input  logic [31:0] a_i,
  input  logic [31:0] b_i,
  output logic        done_o,
  output logic [31:0] result_o
);

  typedef enum logic [1:0] { S0, S1, S2, S3 } state_e;
  state_e state_q;

  logic is_lo, a_signed, b_signed;
  assign is_lo    = (funct3_i == 3'b000);
  assign a_signed = (funct3_i[1:0] != 2'b11);   // MULH, MULHSU
  assign b_signed = (funct3_i[1:0] == 2'b01);   // MULH

  logic signed [16:0] al, ah, bl, bh;
  assign al = {1'b0, a_i[15:0]};
  assign ah = {a_signed & a_i[31], a_i[31:16]};
  assign bl = {1'b0, b_i[15:0]};
  assign bh = {b_signed & b_i[31], b_i[31:16]};

  logic signed [16:0] mx, my;
  logic signed [33:0] prod;
  logic signed [33:0] acc_q;

  always_comb begin
    unique case (state_q)
      S0:      begin mx = al; my = bl; end
      S1:      begin mx = ah; my = bl; end
      S2:      begin mx = al; my = bh; end
      default: begin mx = ah; my = bh; end
    endcase
  end
  assign prod = mx * my;

  // Single-cycle low multiply
  logic [31:0] lo_result;
  assign lo_result = a_i * b_i;

  logic signed [33:0] hi_sum;
  assign hi_sum = prod + (acc_q >>> 16);

  assign done_o   = is_lo ? 1'b1 : (state_q == S3);
  assign result_o = is_lo ? lo_result : hi_sum[31:0];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= S0;
      acc_q   <= '0;
    end else if (flush_i) begin
      state_q <= S0;
    end else if (en_i && valid_i && !is_lo) begin
      unique case (state_q)
        S0: begin acc_q <= prod;                 state_q <= S1; end
        S1: begin acc_q <= (acc_q >>> 16) + prod; state_q <= S2; end
        S2: begin acc_q <= acc_q + prod;         state_q <= S3; end
        S3: begin                                state_q <= S0; end
      endcase
    end
  end
endmodule

// -----------------------------------------------------------------------------
// rv_div.sv : RV32M iterative radix-2 restoring divider (DIV/DIVU/REM/REMU)
//   Latency: 1 (load) + 32 (iterate) + 1 (done) cycles.
//   Special cases follow the RISC-V spec automatically:
//     x/0      -> quotient all-ones, remainder = dividend
//     INT_MIN/-1 -> quotient INT_MIN, remainder 0
//   Operands a_i/b_i/funct3_i must stay stable while valid_i is high (they do:
//   the ID/EX registers are frozen while EX is busy).
// -----------------------------------------------------------------------------
module rv_div (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        en_i,
  input  logic        flush_i,      // squash a running divide
  input  logic        valid_i,
  input  logic [2:0]  funct3_i,
  input  logic [31:0] a_i,
  input  logic [31:0] b_i,
  output logic        done_o,
  output logic [31:0] result_o
);

  typedef enum logic [1:0] { D_IDLE, D_RUN, D_DONE } state_e;
  state_e state_q;

  logic [5:0]  cnt_q;
  logic [31:0] quo_q;    // dividend shifts out / quotient shifts in
  logic [31:0] rem_q;
  logic [31:0] div_q;    // |divisor|

  logic is_signed, is_rem, a_neg, b_neg, b_zero, neg_q, neg_r;
  assign is_signed = ~funct3_i[0];
  assign is_rem    = funct3_i[1];
  assign a_neg     = is_signed & a_i[31];
  assign b_neg     = is_signed & b_i[31];
  assign b_zero    = (b_i == 32'h0);
  assign neg_q     = (a_neg ^ b_neg) & ~b_zero;
  assign neg_r     = a_neg;

  logic [31:0] a_abs, b_abs;
  assign a_abs = a_neg ? (~a_i + 32'd1) : a_i;
  assign b_abs = b_neg ? (~b_i + 32'd1) : b_i;

  logic [32:0] rem_sh;
  logic [33:0] sub;
  logic        ge;
  assign rem_sh = {rem_q, quo_q[31]};
  assign sub    = {1'b0, rem_sh} - {2'b00, div_q};
  assign ge     = ~sub[33];

  assign done_o = (state_q == D_DONE);

  logic [31:0] q_fix, r_fix;
  assign q_fix    = neg_q ? (~quo_q + 32'd1) : quo_q;
  assign r_fix    = neg_r ? (~rem_q + 32'd1) : rem_q;
  assign result_o = is_rem ? r_fix : q_fix;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= D_IDLE;
      cnt_q   <= '0;
      quo_q   <= '0;
      rem_q   <= '0;
      div_q   <= '0;
    end else if (flush_i) begin
      state_q <= D_IDLE;
    end else if (en_i) begin
      unique case (state_q)
        D_IDLE: begin
          if (valid_i) begin
            quo_q   <= a_abs;
            rem_q   <= 32'h0;
            div_q   <= b_abs;
            cnt_q   <= 6'd0;
            state_q <= D_RUN;
          end
        end
        D_RUN: begin
          rem_q <= ge ? sub[31:0] : rem_sh[31:0];
          quo_q <= {quo_q[30:0], ge};
          cnt_q <= cnt_q + 6'd1;
          if (cnt_q == 6'd31) state_q <= D_DONE;
        end
        D_DONE: begin
          state_q <= D_IDLE;
        end
        default: state_q <= D_IDLE;
      endcase
    end
  end
endmodule

// -----------------------------------------------------------------------------
// Three ready-made configurations of rv_core (identical port list, drop-in replacements).
//
//   rv32imc_base   : RV32IMC, no branch predictor, no CSRs / traps
//   rv32imc_bp     : base + branch predictor (BTB 16 / BHT 64 / RAS 8)
//   rv32imc_zicsr  : bp   + Zicsr + machine-mode traps and interrupts   (full core)
//
// Interrupt inputs and hart_id are ignored (and may be tied to 0) on base and bp.
// Each wrapper only sets parameters; any other combination (e.g. Zicsr without the
// predictor) is rv_core with BP_ENABLE / ZICSR set directly.
// -----------------------------------------------------------------------------
`define RV32IMC_PORTS \
  input  logic        clk_i, rst_ni, \
  input  logic [31:0] boot_addr_i, hart_id_i, \
  input  logic        irq_software_i, irq_timer_i, irq_external_i, \
  output logic        instr_req_o, \
  input  logic        instr_gnt_i, \
  output logic [31:0] instr_addr_o, \
  input  logic        instr_rvalid_i, \
  input  logic [31:0] instr_rdata_i, \
  input  logic        instr_err_i, \
  output logic        data_req_o, \
  input  logic        data_gnt_i, \
  output logic [31:0] data_addr_o, \
  output logic        data_we_o, \
  output logic [3:0]  data_be_o, \
  output logic [31:0] data_wdata_o, \
  input  logic        data_rvalid_i, \
  input  logic [31:0] data_rdata_i, \
  input  logic        data_err_i, \
  output logic        retire_o, ecall_o, ebreak_o, illegal_o, trap_o, mret_o
`define RV32IMC_CONN \
  .clk_i, .rst_ni, .boot_addr_i, .hart_id_i, .irq_software_i, .irq_timer_i, .irq_external_i, \
  .instr_req_o, .instr_gnt_i, .instr_addr_o, .instr_rvalid_i, .instr_rdata_i, .instr_err_i, \
  .data_req_o, .data_gnt_i, .data_addr_o, .data_we_o, .data_be_o, .data_wdata_o, \
  .data_rvalid_i, .data_rdata_i, .data_err_i, .retire_o, .ecall_o, .ebreak_o, .illegal_o, .trap_o, .mret_o

module rv32imc_base #(parameter int unsigned FETCH_DEPTH = 4, parameter bit FAST_REDIRECT = 1'b0)
  (`RV32IMC_PORTS);
  rv_core #(.FETCH_DEPTH(FETCH_DEPTH), .FAST_REDIRECT(FAST_REDIRECT),
            .BP_ENABLE(1'b0), .ZICSR(1'b0)) u_core (`RV32IMC_CONN);
endmodule

module rv32imc_bp #(parameter int unsigned FETCH_DEPTH = 4, parameter bit FAST_REDIRECT = 1'b0)
  (`RV32IMC_PORTS);
  rv_core #(.FETCH_DEPTH(FETCH_DEPTH), .FAST_REDIRECT(FAST_REDIRECT),
            .BP_ENABLE(1'b1), .ZICSR(1'b0)) u_core (`RV32IMC_CONN);
endmodule

module rv32imc_zicsr #(parameter int unsigned FETCH_DEPTH = 4, parameter bit FAST_REDIRECT = 1'b0)
  (`RV32IMC_PORTS);
  rv_core #(.FETCH_DEPTH(FETCH_DEPTH), .FAST_REDIRECT(FAST_REDIRECT),
            .BP_ENABLE(1'b1), .ZICSR(1'b1)) u_core (`RV32IMC_CONN);
endmodule

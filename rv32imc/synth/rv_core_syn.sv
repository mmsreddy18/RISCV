// Synthesis wrapper: ties boot_addr_i to a constant so the PC registers (whose async reset value
// comes from that pin in rv_core) map onto ordinary async-reset standard-cell flops.
module rv_core_syn #(
  parameter int unsigned FETCH_DEPTH   = 4,
  parameter bit          FAST_REDIRECT = 1'b0,
  parameter bit          BP_ENABLE  = 1'b1,
  parameter int unsigned BTB_N      = 16,
  parameter int unsigned BTB_W      = 4,
  parameter int unsigned BHT_N      = 64,
  parameter int unsigned BHT_W      = 6
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        irq_software_i,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,
  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  output logic [31:0] instr_addr_o,
  input  logic        instr_rvalid_i,
  input  logic [31:0] instr_rdata_i,
  output logic        data_req_o,
  input  logic        data_gnt_i,
  output logic [31:0] data_addr_o,
  output logic        data_we_o,
  output logic [3:0]  data_be_o,
  output logic [31:0] data_wdata_o,
  input  logic        data_rvalid_i,
  input  logic [31:0] data_rdata_i,
  output logic        retire_o,
  output logic        ecall_o,
  output logic        ebreak_o,
  output logic        illegal_o,
  output logic        trap_o,
  output logic        mret_o
);
  rv_core #(.FETCH_DEPTH(FETCH_DEPTH), .FAST_REDIRECT(FAST_REDIRECT), .BP_ENABLE(BP_ENABLE),
            .BTB_N(BTB_N), .BTB_W(BTB_W), .BHT_N(BHT_N), .BHT_W(BHT_W)) u_core (
    .clk_i, .rst_ni, .boot_addr_i(32'h0000_0000), .hart_id_i(32'h0), .irq_software_i, .irq_timer_i, .irq_external_i,
    .instr_req_o, .instr_gnt_i, .instr_addr_o, .instr_rvalid_i, .instr_rdata_i,
    .data_req_o, .data_gnt_i, .data_addr_o, .data_we_o, .data_be_o, .data_wdata_o,
    .data_rvalid_i, .data_rdata_i,
    .retire_o, .ecall_o, .ebreak_o, .illegal_o, .trap_o, .mret_o
  );
endmodule

// -----------------------------------------------------------------------------
// rv_obi_imem.sv : INSTRUCTION memory = one block RAM with TWO OBI ports
//   i_*  port A : instruction fetch (read only)
//   d_*  port B : data access to the same memory (constants / tables placed next to the code, loaders, tests)
//   Because it is a true dual-port block RAM, a fetch and a data access to this memory in the same cycle
//   never block each other.  Byte addresses passed in are relative to the start of the memory.
// -----------------------------------------------------------------------------
module rv_obi_imem #(
  parameter int unsigned WORDS     = 8192,        // 32 KiB
  parameter string       INIT_FILE = "",
  parameter bit          STALL     = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  // instruction port
  input  logic        i_req_i,
  input  logic [31:0] i_addr_i,
  output logic        i_gnt_o,
  output logic        i_rvalid_o,
  output logic [31:0] i_rdata_o,
  output logic        i_err_o,
  // data port
  input  logic        d_req_i,
  input  logic        d_we_i,
  input  logic [31:0] d_addr_i,
  input  logic [3:0]  d_be_i,
  input  logic [31:0] d_wdata_i,
  output logic        d_gnt_o,
  output logic        d_rvalid_o,
  output logic [31:0] d_rdata_o,
  output logic        d_err_o
);
  localparam int unsigned AW = $clog2(WORDS);
  logic          a_en, b_en;
  logic [3:0]    a_we, b_we;
  logic [AW-1:0] a_addr, b_addr;
  logic [31:0]   a_wdata, b_wdata, a_rdata, b_rdata;

  rv_obi_ram_port #(.WORDS(WORDS), .STALL(STALL)) u_pa (
    .clk_i, .rst_ni, .req_i(i_req_i), .we_i(1'b0), .addr_i(i_addr_i), .be_i(4'b1111), .wdata_i(32'h0),
    .gnt_o(i_gnt_o), .rvalid_o(i_rvalid_o), .rdata_o(i_rdata_o), .err_o(i_err_o),
    .ram_en_o(a_en), .ram_we_o(a_we), .ram_addr_o(a_addr), .ram_wdata_o(a_wdata), .ram_rdata_i(a_rdata));

  rv_obi_ram_port #(.WORDS(WORDS), .STALL(STALL)) u_pb (
    .clk_i, .rst_ni, .req_i(d_req_i), .we_i(d_we_i), .addr_i(d_addr_i), .be_i(d_be_i), .wdata_i(d_wdata_i),
    .gnt_o(d_gnt_o), .rvalid_o(d_rvalid_o), .rdata_o(d_rdata_o), .err_o(d_err_o),
    .ram_en_o(b_en), .ram_we_o(b_we), .ram_addr_o(b_addr), .ram_wdata_o(b_wdata), .ram_rdata_i(b_rdata));

  rv_bram_tdp #(.WORDS(WORDS), .INIT_FILE(INIT_FILE)) u_bram (
    .clk_i,
    .a_en_i(a_en), .a_we_i(a_we), .a_addr_i(a_addr), .a_wdata_i(a_wdata), .a_rdata_o(a_rdata),
    .b_en_i(b_en), .b_we_i(b_we), .b_addr_i(b_addr), .b_wdata_i(b_wdata), .b_rdata_o(b_rdata));
endmodule

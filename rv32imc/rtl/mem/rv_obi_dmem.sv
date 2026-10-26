// -----------------------------------------------------------------------------
// rv_obi_dmem.sv : DATA memory = one block RAM with one OBI port (loads and stores, byte enables).
//   The second RAM port is unused (tied off).  Byte address passed in is relative to the start of the memory.
// -----------------------------------------------------------------------------
module rv_obi_dmem #(
  parameter int unsigned WORDS     = 8192,        // 32 KiB
  parameter string       INIT_FILE = "",
  parameter bit          STALL     = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [31:0] addr_i,
  input  logic [3:0]  be_i,
  input  logic [31:0] wdata_i,
  output logic        gnt_o,
  output logic        rvalid_o,
  output logic [31:0] rdata_o,
  output logic        err_o
);
  localparam int unsigned AW = $clog2(WORDS);
  logic          a_en;
  logic [3:0]    a_we;
  logic [AW-1:0] a_addr;
  logic [31:0]   a_wdata, a_rdata, b_rdata_unused;

  rv_obi_ram_port #(.WORDS(WORDS), .STALL(STALL)) u_pa (
    .clk_i, .rst_ni, .req_i, .we_i, .addr_i, .be_i, .wdata_i,
    .gnt_o, .rvalid_o, .rdata_o, .err_o,
    .ram_en_o(a_en), .ram_we_o(a_we), .ram_addr_o(a_addr), .ram_wdata_o(a_wdata), .ram_rdata_i(a_rdata));

  rv_bram_tdp #(.WORDS(WORDS), .INIT_FILE(INIT_FILE)) u_bram (
    .clk_i,
    .a_en_i(a_en), .a_we_i(a_we), .a_addr_i(a_addr), .a_wdata_i(a_wdata), .a_rdata_o(a_rdata),
    .b_en_i(1'b0), .b_we_i(4'b0000), .b_addr_i('0), .b_wdata_i(32'h0), .b_rdata_o(b_rdata_unused));
endmodule

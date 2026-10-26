// -----------------------------------------------------------------------------
// rv_bram_tdp.sv : true dual-port RAM with byte write enables, written in the style Vivado
//                  infers as BLOCK RAM (Xilinx UG901, "true dual port, byte-wide write enable, read-first").
//   * 32-bit words, WORDS deep; both ports share one clock.
//   * a port does something only when its *_en_i is high; a read returns the data that was in the
//     RAM BEFORE this cycle's write (read-first); the read data appears in the NEXT cycle.
//   * INIT_FILE: $readmemh image, one 32-bit hex word per line, word 0 first (Vivado uses it as the
//     power-up contents of the block RAM; add the .hex/.mem file to the project, or give a full path).
//   * Do not write the same word from both ports in one cycle (result undefined, as in the hardware).
// -----------------------------------------------------------------------------
module rv_bram_tdp #(
  parameter int unsigned WORDS     = 8192,
  parameter string       INIT_FILE = ""
) (
  input  logic                       clk_i,
  // port A
  input  logic                       a_en_i,
  input  logic [3:0]                 a_we_i,
  input  logic [$clog2(WORDS)-1:0]   a_addr_i,
  input  logic [31:0]                a_wdata_i,
  output logic [31:0]                a_rdata_o,
  // port B
  input  logic                       b_en_i,
  input  logic [3:0]                 b_we_i,
  input  logic [$clog2(WORDS)-1:0]   b_addr_i,
  input  logic [31:0]                b_wdata_i,
  output logic [31:0]                b_rdata_o
);
  (* ram_style = "block" *) logic [31:0] mem [WORDS];

  initial begin
    for (int i = 0; i < WORDS; i++) mem[i] = 32'h0000_0000;
    a_rdata_o = 32'h0;
    b_rdata_o = 32'h0;
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  always @(posedge clk_i) begin : port_a
    if (a_en_i) begin
      for (int b = 0; b < 4; b++)
        if (a_we_i[b]) mem[a_addr_i][8*b +: 8] <= a_wdata_i[8*b +: 8];
      a_rdata_o <= mem[a_addr_i];
    end
  end

  always @(posedge clk_i) begin : port_b
    if (b_en_i) begin
      for (int b = 0; b < 4; b++)
        if (b_we_i[b]) mem[b_addr_i][8*b +: 8] <= b_wdata_i[8*b +: 8];
      b_rdata_o <= mem[b_addr_i];
    end
  end
endmodule

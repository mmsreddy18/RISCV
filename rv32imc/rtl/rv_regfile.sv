// -----------------------------------------------------------------------------
// rv_regfile.sv : 32 x 32 register file, 2 async read ports, 1 write port.
//   No internal write-through; the core bypasses WB data into ID itself.
// -----------------------------------------------------------------------------
module rv_regfile (
  input  logic        clk_i,
  input  logic        we_i,
  input  logic [4:0]  waddr_i,
  input  logic [31:0] wdata_i,
  input  logic [4:0]  raddr1_i,
  input  logic [4:0]  raddr2_i,
  output logic [31:0] rdata1_o,
  output logic [31:0] rdata2_o
);
  logic [31:0] regs_q [1:31];

  assign rdata1_o = (raddr1_i == 5'd0) ? 32'h0 : regs_q[raddr1_i];
  assign rdata2_o = (raddr2_i == 5'd0) ? 32'h0 : regs_q[raddr2_i];

  always_ff @(posedge clk_i) begin
    if (we_i && (waddr_i != 5'd0)) regs_q[waddr_i] <= wdata_i;
  end

  // Simulation hygiene only: avoids X's from uninitialised registers.
  // synthesis translate_off
  initial begin
    for (int i = 1; i < 32; i++) regs_q[i] = 32'h0;
  end
  // synthesis translate_on
endmodule

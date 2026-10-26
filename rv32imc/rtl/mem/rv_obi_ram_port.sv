// -----------------------------------------------------------------------------
// rv_obi_ram_port.sv : OBI subordinate front-end for ONE port of a block RAM.
//
//   OBI side (the core's view):
//     req_i/gnt_o   address phase.  gnt_o = req_i (no wait) - or, with STALL=1, withheld pseudo-randomly
//                   (25% of cycles) to test the core with a slow memory.  gnt_o depends only on req_i and
//                   registered state, never the other way round.
//     rvalid_o      one cycle after a granted request (for loads AND stores, as OBI requires)
//     rdata_o       the loaded word (RAM read data, registered inside the block RAM)
//     err_o         always 0 here; address errors are produced by the decoder (rv_obi_err)
//   RAM side: ram_en_o / ram_we_o (byte enables, 0 for loads) / ram_addr_o (word index) / ram_wdata_o,
//             ram_rdata_i comes back one cycle later.
//   Fixed latency 1: the response to a grant in cycle t is visible in cycle t+1.
// -----------------------------------------------------------------------------
module rv_obi_ram_port #(
  parameter int unsigned WORDS = 8192,
  parameter bit          STALL = 1'b0
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  // OBI
  input  logic                     req_i,
  input  logic                     we_i,
  input  logic [31:0]              addr_i,       // byte address RELATIVE to the start of this memory
  input  logic [3:0]               be_i,
  input  logic [31:0]              wdata_i,
  output logic                     gnt_o,
  output logic                     rvalid_o,
  output logic [31:0]              rdata_o,
  output logic                     err_o,
  // RAM port
  output logic                     ram_en_o,
  output logic [3:0]               ram_we_o,
  output logic [$clog2(WORDS)-1:0] ram_addr_o,
  output logic [31:0]              ram_wdata_o,
  input  logic [31:0]              ram_rdata_i
);
  logic [15:0] lfsr_q;
  logic        stall_now;
  if (STALL) begin : g_stall
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) lfsr_q <= 16'hACE1;
      else         lfsr_q <= {lfsr_q[14:0], lfsr_q[15] ^ lfsr_q[13] ^ lfsr_q[12] ^ lfsr_q[10]};
    end
    assign stall_now = (lfsr_q[1:0] == 2'b11);
  end else begin : g_nostall
    assign lfsr_q    = '0;
    assign stall_now = 1'b0;
  end

  assign gnt_o       = req_i & ~stall_now;
  assign ram_en_o    = gnt_o;
  assign ram_we_o    = we_i ? be_i : 4'b0000;
  assign ram_addr_o  = addr_i[$clog2(WORDS)+1:2];
  assign ram_wdata_o = wdata_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rvalid_o <= 1'b0;
    else         rvalid_o <= gnt_o;
  end
  assign rdata_o = ram_rdata_i;
  assign err_o   = 1'b0;
endmodule

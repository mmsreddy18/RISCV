// -----------------------------------------------------------------------------
// rv_obi_rom.sv : read-only OBI subordinate (boot ROM). Contents: +rom=<file> (32-bit words).
//   gnt always 1; rvalid one cycle after req&gnt; a WRITE is answered with err=1 (store access fault).
// -----------------------------------------------------------------------------
module rv_obi_rom #(
  parameter int unsigned WORDS = 1024
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [31:0] addr_i,
  output logic        gnt_o,
  output logic        rvalid_o,
  output logic [31:0] rdata_o,
  output logic        err_o
);
  logic [31:0] mem [WORDS];
  string       romfile;
  initial begin
    for (int i = 0; i < WORDS; i++) mem[i] = 32'h0000_0073;   // unprogrammed words: ecall (traps visibly)
    if ($value$plusargs("rom=%s", romfile)) $readmemh(romfile, mem);
  end
  assign gnt_o = 1'b1;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rvalid_o <= 1'b0;
      err_o    <= 1'b0;
    end else begin
      rvalid_o <= req_i;
      err_o    <= req_i & we_i;
    end
  end
  always_ff @(posedge clk_i) if (req_i) rdata_o <= mem[addr_i[31:2] % WORDS];
endmodule

// -----------------------------------------------------------------------------
// rv_sram_array.sv : behavioural single-port synchronous SRAM (simulation model)
//   * word-addressed, byte write enables, 1-cycle read latency (rdata valid the cycle AFTER req&gnt)
//   * gnt_o depends only on registered state (R-21 is about the manager, but this keeps the
//     subordinate free of req->gnt loops); STALL=1 withholds gnt pseudo-randomly (LFSR) to exercise
//     back-pressure; the contents are preloaded from +hex=<file> (one 32-bit word per line, address 0 upwards; this array takes the words from BASE_WORD)
// -----------------------------------------------------------------------------
module rv_sram_array #(
  parameter int unsigned WORDS     = 65536,
  parameter int unsigned BASE_WORD = 0,        // this array holds image words BASE_WORD .. BASE_WORD+WORDS-1
  parameter int unsigned IMG_WORDS = 65536,    // size of the +hex image (words)
  parameter bit          STALL     = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] wdata_i,
  input  logic [3:0]  be_i,
  output logic        gnt_o,
  output logic [31:0] rdata_o
);
  logic [31:0] mem [WORDS];
  logic [31:0] rdata_q;
  logic [15:0] lfsr_q;
  logic [31:0] img [IMG_WORDS];
  string       hexfile;

  initial begin
    for (int i = 0; i < WORDS; i++) mem[i] = 32'h0;
    for (int i = 0; i < IMG_WORDS; i++) img[i] = 32'h0;
    if ($value$plusargs("hex=%s", hexfile)) begin
      $readmemh(hexfile, img);
      for (int i = 0; i < WORDS; i++) if (BASE_WORD + i < IMG_WORDS) mem[i] = img[BASE_WORD + i];
    end
  end

  // x^16 + x^14 + x^13 + x^11 + 1
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) lfsr_q <= 16'hACE1;
    else         lfsr_q <= {lfsr_q[14:0], lfsr_q[15] ^ lfsr_q[13] ^ lfsr_q[12] ^ lfsr_q[10]};
  end
  assign gnt_o = ~(STALL & (lfsr_q[1:0] == 2'b11));      // 25 % of the cycles without grant

  always_ff @(posedge clk_i) begin
    if (req_i && gnt_o) begin
      rdata_q <= mem[addr_i[31:2] % WORDS];
      if (we_i) begin
        for (int b = 0; b < 4; b++)
          if (be_i[b]) mem[addr_i[31:2] % WORDS][8*b +: 8] <= wdata_i[8*b +: 8];
      end
    end
  end
  assign rdata_o = rdata_q;
endmodule

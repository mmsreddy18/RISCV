// -----------------------------------------------------------------------------
// rv_obi_err.sv : OBI error responder for addresses that no memory or peripheral owns.
//   Grants every request and answers one cycle later with rvalid=1, err=1 (-> access fault in the core).
// -----------------------------------------------------------------------------
module rv_obi_err (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  output logic        gnt_o,
  output logic        rvalid_o,
  output logic [31:0] rdata_o,
  output logic        err_o
);
  assign gnt_o   = req_i;
  assign rdata_o = 32'hBADC_AB1E;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin rvalid_o <= 1'b0; err_o <= 1'b0; end
    else         begin rvalid_o <= req_i; err_o <= req_i; end
  end
endmodule
